#!/bin/sh
# Pi USB-cam live streamer — the ONLY thing this container does:
#   /dev/video0 (MJPEG) -> H.264 -> RTSP push to the cloud receiver.
#
# Encoder choice (Pi 3 survival rules):
#   h264_v4l2m2m  Pi hardware encoder — 720p@15, default when present.
#   libx264       software fallback (ultrafast, 480p@10) — the Pi 3 CPU
#                 cannot do more in real time; override at your own risk.
#
# Env (see pi/.env.example):
#   VIDEO_DEVICE   default /dev/video0
#   VIDEO_SIZE     default 1280x720 (fallback forces 640x480)
#   FPS            default 15 (fallback forces 10)
#   BITRATE        default 1200k (fallback forces 800k)
#   CLOUD_RTSP_URL required, e.g. rtsp://pi:PASS@<ec2>:8554/usbcam
#   INPUT_FORMAT   default mjpeg (drop to empty if your cam is YUYV-only)
set -u

log() { echo "[$(date '+%H:%M:%S')] $*"; }

: "${VIDEO_DEVICE:=/dev/video0}"
: "${VIDEO_SIZE:=1280x720}"
: "${FPS:=15}"
: "${BITRATE:=1200k}"
: "${INPUT_FORMAT:=mjpeg}"
: "${MAX_BACKOFF:=30}"

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

# --- pick encoder (functional probe, not just --encoders) ----------------------
# h264_v4l2m2m is compiled into ffmpeg everywhere, but it only works when the
# kernel exposes a V4L2 mem2mem encode node (e.g. /dev/video11 on Pi kernels).
# A 1s testsrc encode proves the whole path opens before we commit to it.
if ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=128x128:rate=5:duration=1 \
        -c:v h264_v4l2m2m -f null - 2>/dev/null; then
    ENC="-vf format=yuv420p -c:v h264_v4l2m2m -b:v $BITRATE"
    SIZE="$VIDEO_SIZE"
    RATE="$FPS"
    log "encoder: h264_v4l2m2m (hardware) ${SIZE}@${RATE} ${BITRATE}"
else
    # Pi 3 CPU fallback — keep it small or frames will lag behind live.
    ENC="-c:v libx264 -preset ultrafast -tune zerolatency -b:v 800k"
    SIZE="640x480"
    RATE="10"
    log "encoder: libx264 ultrafast (software fallback) ${SIZE}@${RATE} — consider HW encode"
fi

if [ -n "$INPUT_FORMAT" ]; then
    INPUT="-f v4l2 -input_format $INPUT_FORMAT -video_size $SIZE -framerate $RATE -i $VIDEO_DEVICE"
else
    INPUT="-f v4l2 -video_size $SIZE -framerate $RATE -i $VIDEO_DEVICE"
fi

# --- push loop (never exits; reconnects with backoff) --------------------------
BACKOFF=1
while :; do
    log "pushing $VIDEO_DEVICE -> $CLOUD_RTSP_URL"
    # shellcheck disable=SC2086
    ffmpeg -hide_banner -loglevel warning $INPUT \
        -an $ENC -g $((RATE * 4)) -f rtsp -rtsp_transport tcp "$CLOUD_RTSP_URL"
    rc=$?
    log "ffmpeg exited rc=$rc; retrying in ${BACKOFF}s"
    sleep "$BACKOFF"
    [ "$BACKOFF" -lt "$MAX_BACKOFF" ] && BACKOFF=$((BACKOFF * 2))
done
