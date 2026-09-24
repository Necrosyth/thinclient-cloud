#!/usr/bin/env bash
# Thinclient cloud launcher (EC2 host, e.g. testbox).
#   ./run-cloud.sh up|down|status|logs
# Security group must allow 8554/tcp inbound from the Pi.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$REPO/cloud/docker-compose.yml"
ENV_FILE="$REPO/cloud/.env"
[ -f "$ENV_FILE" ] || { cp "$REPO/cloud/.env.example" "$ENV_FILE"; echo "created cloud/.env — set RTSP_PUBLISH_PASS first"; }
cmd="${1:-up}"
case "$cmd" in
    up)     docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d ;;
    down)   docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down ;;
    status) docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps ;;
    logs)   shift || true; docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs -f --tail=200 "$@" ;;
    *)      echo "usage: $0 [up|down|status|logs]"; exit 2 ;;
esac
