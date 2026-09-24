#!/usr/bin/env bash
# Thinclient Pi launcher.
#   ./run-pi.sh up|down|status|logs     (up builds the streamer image)
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$REPO/pi/docker-compose.yml"
ENV_FILE="$REPO/pi/.env"
[ -f "$ENV_FILE" ] || { cp "$REPO/pi/.env.example" "$ENV_FILE"; echo "created pi/.env — set CLOUD_RTSP_URL first"; }
cmd="${1:-up}"
case "$cmd" in
    up)     docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build ;;
    down)   docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down ;;
    status) docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps ;;
    logs)   shift || true; docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs -f --tail=200 "$@" ;;
    *)      echo "usage: $0 [up|down|status|logs]"; exit 2 ;;
esac
