# Pi streamer — Ubuntu 24.04 base so the image matches the Pi 3 host OS and
# ships an ffmpeg with h264_v4l2m2m (Pi hardware H.264 encoder) + libx264.
# Multi-arch (arm64 for the Pi 3, amd64 for testing on a laptop).
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg curl \
    && rm -rf /var/lib/apt/lists/* \
    && ffmpeg -hide_banner -encoders 2>/dev/null | grep -E "h264" | head -5 || true

COPY pi/stream.sh /usr/local/bin/stream.sh
RUN chmod +x /usr/local/bin/stream.sh

CMD ["/usr/local/bin/stream.sh"]
