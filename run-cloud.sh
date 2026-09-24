#!/usr/bin/env bash
# Thinclient cloud launcher (EC2 host, e.g. testbox).
#   ./run-cloud.sh up|down|status|logs
# Security group must allow 8554/tcp inbound from the Pi.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$REPO/cloud/docker-compose.yml"
[ -f "$REPO/cloud/.env" ] || { cp "$REPO/cloud/.env.example" "$REPO/cloud/.env"; echo "created cloud/.env — set RTSP_PUBLISH_PASS first"; }
cmd="${1:-up}"
case "$cmd" in
    up)     docker compose -f "$COMPOSE_FILE" up -d ;;
    down)   docker compose -f "$COMPOSE_FILE" down ;;
    status) docker compose -f "$COMPOSE_FILE" ps ;;
    logs)   shift || true; docker compose -f "$COMPOSE_FILE" logs -f --tail=200 "$@" ;;
    *)      echo "usage: $0 [up|down|status|logs]"; exit 2 ;;
esac
