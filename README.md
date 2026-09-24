# Thinclient-Cloud — Pi USB-cam live streamer

The simplest possible split: the Raspberry Pi **only streams** its USB camera,
live, to AWS. All processing and display happens in the cloud.

```
Pi 3 (Ubuntu 24.04, /dev/video0)
  └─ streamer (ONE container: ffmpeg) ──RTSP push──▶ EC2 (MediaMTX :8554/usbcam)
                                                      └─▶ perception reads rtsp://media:8554/usbcam
                                                      └─▶ dashboard displays it
```

Why RTSP push: the pipeline ingests `rtsp://<host>:8554/<camera>` (H.264 over
TCP — see `perception/ingest.py: go2rtc_url()` in the main repo). The Pi opens
an **outbound** connection to the cloud, so no port-forwarding or NAT setup on
the Pi side. No KVS, no SDK builds, no AWS keys on the Pi.

No recording anywhere in this repo — live only.

## Layout

```
pi/                  # runs on the Pi 3
  Dockerfile         # ubuntu:24.04 + ffmpeg (arm64, HW-encode capable)
  stream.sh          # capture /dev/video0 → H.264 → RTSP push, with reconnect
  docker-compose.yml # single service: streamer
  .env.example
cloud/               # runs on the EC2 host (e.g. testbox)
  docker-compose.yml # single service: mediamtx (RTSP receiver)
  mediamtx.yml
  .env.example
run-pi.sh            # Pi launcher: up | down | status | logs
run-cloud.sh         # cloud launcher: up | down | status | logs
```

## Pi 3 notes (Ubuntu 24.04 LTS, arm64, 1 GB RAM)

- RAM is a non-issue: the streamer uses ~30 MB. The constraint is CPU.
- A Pi 3 CPU **cannot** software-encode 720p H.264 in real time, so the image
  **auto-detects a Pi 3** and lightens the software fallback: 10 fps,
  960x540, 2 encoder threads, ~700 kbit/s. Pi 4/5 keep full 720p@15.
  Force it with `PROFILE=pi3` (or `full`) — see `pi/.env.example`.
- If the kernel offers the hardware encoder (`h264_v4l2m2m`), it is used on
  any Pi — cheapest path, no tuning needed.
- MJPEG capture (`input_format mjpeg`) is assumed — true for nearly all USB
  webcams. If yours only does YUYV, drop that flag in `stream.sh`.
- Install docker on the Pi: `curl -fsSL https://get.docker.com | sh`,
  then add your user to the `docker` group and reboot.

## Bring-up

### Brand-new Pi 3: one command

Docker first (once per Pi): `curl -fsSL https://get.docker.com | sh`,
then log out/in (docker group) and reboot. Then:

```bash
docker run -d --name thinclient-streamer --restart unless-stopped \
  --device /dev/video0 --group-add 44 \
  -e CLOUD_RTSP_URL=rtsp://pi:PASSWORD@<EC2-PUBLIC-DNS>:8554/usbcam \
  ghcr.io/necrosyth/thinclient-streamer:latest
```

No clone, no build, no env file — image is prebuilt (arm64) and updates
ship via `:latest`. Logs: `docker logs -f thinclient-streamer`.

### Cloud first (EC2 security group must allow `8554/tcp` from the Pi):

```bash
cp cloud/.env.example cloud/.env   # set RTSP_PUBLISH_USER / RTSP_PUBLISH_PASS
./run-cloud.sh up
```

Then the Pi:

```bash
cp pi/.env.example pi/.env          # set CLOUD_RTSP_URL to your EC2 host
./run-pi.sh up                      # streams until stopped
```

`CLOUD_RTSP_URL` looks like:

```
rtsp://pi:PASSWORD@<EC2-PUBLIC-DNS>:8554/usbcam
```

Verify on the cloud host: `./run-cloud.sh logs` shows the `usbcam` publish,
and `ffprobe rtsp://127.0.0.1:8554/usbcam` lists an H.264 stream. Point the
pipeline's camera at `rtsp://media:8554/usbcam` and it ingests like any CCTV
feed — no pipeline changes needed.
