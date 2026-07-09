#!/usr/bin/env bash
# launch_minimal.sh — build (optional) and launch the hemlock-minimal runtime.
# Follows the documented build pattern including the one-time OpenClaw npm
# dependency fix layer, then starts the container with named volumes.
# Usage:
#   bash scripts/launch_minimal.sh                # start (build if image missing)
#   bash scripts/launch_minimal.sh --build        # force rebuild
#   bash scripts/launch_minimal.sh --dry-run      # print what would run
set -euo pipefail

IMAGE="${HEMLOCK_IMAGE:-hemlock/runtime:latest}"
CONTAINER="${HEMLOCK_CONTAINER:-hemlock-runtime}"
PORT="${OPENCLAW_GATEWAY_PORT:-1437}"
CONTEXT="${HEMLOCK_BUILD_CONTEXT:-.}"
DOCKERFILE="${HEMLOCK_DOCKERFILE:-Dockerfile.runtime}"
BUILD=0; DRY=0
for a in "$@"; do
    case "$a" in
        --build) BUILD=1 ;;
        --dry-run) DRY=1 ;;
        *) echo "unknown flag: $a" >&2; exit 2 ;;
    esac
done

run() { if [ "$DRY" -eq 1 ]; then echo "+ $*"; else "$@"; fi; }

if [ "$BUILD" -eq 1 ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[launch] building $IMAGE from $DOCKERFILE"
    run docker build -t "$IMAGE" -f "$CONTEXT/$DOCKERFILE" "$CONTEXT"
    echo "[launch] applying one-time OpenClaw npm dependency layer"
    run docker run -d --name hemlock-fix --entrypoint sleep "$IMAGE" infinity
    run docker exec -u root hemlock-fix bash -c \
        "cd /opt/openclaw/lib/node_modules/openclaw && npm install --production --legacy-peer-deps"
    run docker commit hemlock-fix "$IMAGE"
    run docker rm -f hemlock-fix
fi

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "[launch] $CONTAINER already running"
    exit 0
fi

echo "[launch] starting $CONTAINER (gateway on :$PORT)"
run docker run -d --name "$CONTAINER" \
    -p "${PORT}:${PORT}" \
    -e "OPENCLAW_GATEWAY_PORT=${PORT}" \
    -v hemlock-workspace:/workspace \
    "$IMAGE"

echo "[launch] done — verify with: bash scripts/check_runtime.sh"
