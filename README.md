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

## Pi 3 notes (Ubuntu 24.04 LTS, arm64)

- A Pi 3 CPU **cannot** software-encode 720p H.264 in real time. `stream.sh`
  uses the Pi's hardware H.264 encoder (`h264_v4l2m2m`, via `bcm2835-codec`)
  when present — 1280x720@15 default.
- If no HW encoder is found it falls back to `libx264 ultrafast` at
  640x480@10 so the little CPU survives. Override with `VIDEO_SIZE`/`FPS`.
- MJPEG capture (`input_format mjpeg`) is assumed — true for nearly all USB
  webcams. If yours only does YUYV, drop that flag in `stream.sh`.
- Install docker on the Pi: `curl -fsSL https://get.docker.com | sh`,
  then add your user to the `docker` group and reboot.

## Bring-up

Cloud first (EC2 security group must allow `8554/tcp` from the Pi):

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
