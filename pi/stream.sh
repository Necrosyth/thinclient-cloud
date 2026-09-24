#!/bin/sh
# Pi USB-cam live streamer — the ONLY thing this container does:
#   /dev/video0 (MJPEG) -> H.264 -> RTSP push to the cloud receiver.
#
# Encoder choice:
#   h264_v4l2m2m  Pi hardware encoder when the kernel offers it (cheapest).
#   libx264       software fallback (ultrafast). On a Pi 3 the PROFILE=pi3
#                 auto-tune kicks in: 10fps, 960x540, 2 threads, ~700k —
#                 RAM stays ~30MB and encode can't starve the system.
#
# Env (see pi/.env.example):
#   VIDEO_DEVICE   default /dev/video0
#   VIDEO_SIZE     default 1280x720 (HW path only; fallback captures native)
#   FPS            default 15 (HW path only)
#   BITRATE        default 1200k (HW path only)
#   CLOUD_RTSP_URL required, e.g. rtsp://pi:PASS@<ec2>:8554/usbcam
#   INPUT_FORMAT   default mjpeg (drop to empty if your cam is YUYV-only)
#   PROFILE        auto (default) | pi3 | full — software-fallback effort.
#                  auto detects a Pi 3 and lightens the encode.
#   OUT_FPS        fallback output fps (default: 10 on pi3, 15 otherwise)
#   SCALE          fallback downscale WIDTHxHEIGHT (default: 960x540 on pi3,
#                  none otherwise) — half the pixels, ~half the encode cost.
#   THREADS        x264 threads (default: 2 on pi3, 0=auto otherwise).
#                  Capped on pi3 so encode can't starve docker/system.
#   BITRATE_PI3    fallback bitrate on pi3 (default 700k)
set -u

log() { echo "[$(date '+%H:%M:%S')] $*"; }

: "${VIDEO_DEVICE:=/dev/video0}"
: "${VIDEO_SIZE:=1280x720}"
: "${FPS:=15}"
: "${BITRATE:=1200k}"
: "${INPUT_FORMAT:=mjpeg}"
: "${MAX_BACKOFF:=30}"
: "${PROFILE:=auto}"

if [ -z "${CLOUD_RTSP_URL:-}" ]; then
    log "error: CLOUD_RTSP_URL is unset — copy pi/.env.example to pi/.env"
    exit 1
fi

# --- wait for the camera ------------------------------------------------------
n=0
while [ ! -e "$VIDEO_DEVICE" ]; do
    n=$((n + 1))
    [ "$n" -ge 60 ] && { log "error: $VIDEO_DEVICE never appeared"; exit 1; }
    log "waiting for $VIDEO_DEVICE ..."
    sleep 2
done

# --- board profile --------------------------------------------------------------
# A Pi 3 (1GB RAM, 4x Cortex-A53) cannot software-encode full 720p in real
# time — a Pi 5 burns ~1.6 fast cores on it. Auto-detect and lighten the
# software-fallback load (fewer fps, downscaled frame, capped threads) so
# encode can never starve docker or the system, even under transient spikes
# (image pull/decompress happens before this process starts; the supervisor
# loop below retries through anything short of that).
if [ "$PROFILE" = "auto" ]; then
    if grep -qi "raspberry pi 3" /proc/cpuinfo 2>/dev/null || \
       grep -qi "raspberry pi 3" /proc/device-tree/model 2>/dev/null; then
        PROFILE="pi3"
    else
        PROFILE="full"
    fi
fi
log "profile: $PROFILE"

# --- pick encoder (functional probe, not just --encoders) ----------------------
# h264_v4l2m2m is compiled into ffmpeg everywhere, but it only works when the
# kernel exposes a V4L2 mem2mem encode node (e.g. /dev/video11 on Pi kernels).
# A 1s testsrc encode proves the whole path opens before we commit to it.
if ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=128x128:rate=5:duration=1 \
        -c:v h264_v4l2m2m -f null - 2>/dev/null; then
    ENC="-vf format=yuv420p -c:v h264_v4l2m2m -b:v $BITRATE"
    SIZE="$VIDEO_SIZE"
    RATE="$FPS"
    OUT_RATE="$FPS"
    log "encoder: h264_v4l2m2m (hardware) ${SIZE}@${RATE} ${BITRATE}"
else
    # Software fallback. IMPORTANT: capture a size+fps the cam REALLY offers
    # (this ROG cam has no 640x480 MJPEG mode — asking for it silently keeps
    # 720p@30 and melts weak CPUs). Capture native, lighten downstream.
    if [ "$PROFILE" = "pi3" ]; then
        OUT_RATE="${OUT_FPS:-10}"
        SCALE="${SCALE:-960x540}"
        THREADS="${THREADS:-2}"
        FB_BITRATE="${BITRATE_PI3:-700k}"
    else
        OUT_RATE="${OUT_FPS:-15}"
        SCALE="${SCALE:-none}"
        THREADS="${THREADS:-0}"
        FB_BITRATE="1000k"
    fi
    VF="format=yuv420p"
    [ "$SCALE" != "none" ] && VF="$VF,scale=$SCALE"
    # shellcheck disable=SC2086
    ENC="-vf $VF -c:v libx264 -preset ultrafast -tune zerolatency -threads $THREADS -b:v $FB_BITRATE"
    SIZE="1280x720"
    RATE="30"
    log "encoder: libx264 ultrafast (software) in=${SIZE}@${RATE} out=${OUT_RATE}fps${SCALE:+ scale=$SCALE} threads=$THREADS ${FB_BITRATE}"
fi

if [ -n "$INPUT_FORMAT" ]; then
    INPUT="-f v4l2 -input_format $INPUT_FORMAT -video_size $SIZE -framerate $RATE -i $VIDEO_DEVICE"
else
    INPUT="-f v4l2 -video_size $SIZE -framerate $RATE -i $VIDEO_DEVICE"
fi

# --- push loop (never exits; reconnects with backoff) --------------------------
# Never log the URL itself — it embeds the publish password.
SAFE_URL=$(printf '%s' "$CLOUD_RTSP_URL" | sed -E 's#(rtsp://[^:]+:)[^@]+@#\1(redacted)@#')
BACKOFF=1
while :; do
    log "pushing $VIDEO_DEVICE -> $SAFE_URL"
    # shellcheck disable=SC2086
    ffmpeg -hide_banner -loglevel warning $INPUT \
        -an -r "$OUT_RATE" $ENC -g $((OUT_RATE * 4)) -f rtsp -rtsp_transport tcp "$CLOUD_RTSP_URL"
    rc=$?
    log "ffmpeg exited rc=$rc; retrying in ${BACKOFF}s"
    sleep "$BACKOFF"
    [ "$BACKOFF" -lt "$MAX_BACKOFF" ] && BACKOFF=$((BACKOFF * 2))
done
