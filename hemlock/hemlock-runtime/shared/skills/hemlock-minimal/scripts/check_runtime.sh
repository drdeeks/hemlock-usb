#!/usr/bin/env bash
# check_runtime.sh — verify the hemlock-minimal runtime is present and healthy.
# Checks: image exists, container running, gateway port answering, named volumes.
# Usage: bash scripts/check_runtime.sh [--json]
set -euo pipefail

IMAGE="${HEMLOCK_IMAGE:-hemlock/runtime:latest}"
CONTAINER="${HEMLOCK_CONTAINER:-hemlock-runtime}"
PORT="${OPENCLAW_GATEWAY_PORT:-1437}"
JSON=0
[ "${1:-}" = "--json" ] && JSON=1

ok=0; fail=0
declare -a results

check() { # name, 0/1, detail
    if [ "$2" -eq 0 ]; then ok=$((ok+1)); results+=("PASS|$1|$3");
    else fail=$((fail+1)); results+=("FAIL|$1|$3"); fi
}

command -v docker >/dev/null 2>&1 || { echo "docker not found on PATH" >&2; exit 2; }

docker image inspect "$IMAGE" >/dev/null 2>&1
check "image" $? "$IMAGE"

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    check "container" 0 "$CONTAINER running"
    if docker exec "$CONTAINER" python3 -m health.doctor_bridge --quick >/dev/null 2>&1; then
        check "doctor" 0 "health.doctor_bridge --quick"
    else
        check "doctor" 1 "doctor_bridge failed (run --json inside for detail)"
    fi
else
    check "container" 1 "$CONTAINER not running"
    check "doctor" 1 "skipped (container down)"
fi

if command -v curl >/dev/null 2>&1 && curl -fsS -m 3 "http://localhost:${PORT}/" >/dev/null 2>&1; then
    check "gateway-port" 0 "localhost:${PORT}"
else
    check "gateway-port" 1 "no answer on localhost:${PORT}"
fi

vols=$(docker volume ls --format '{{.Name}}' | grep -c '^hemlock-' || true)
check "volumes" 0 "${vols} hemlock-* named volume(s)"

if [ "$JSON" -eq 1 ]; then
    printf '{"ok":%d,"fail":%d,"checks":[' "$ok" "$fail"
    first=1
    for r in "${results[@]}"; do
        IFS='|' read -r s n d <<<"$r"
        [ $first -eq 0 ] && printf ','
        printf '{"status":"%s","name":"%s","detail":"%s"}' "$s" "$n" "$d"
        first=0
    done
    printf ']}\n'
else
    for r in "${results[@]}"; do IFS='|' read -r s n d <<<"$r"; printf '%-4s %-14s %s\n' "$s" "$n" "$d"; done
    echo "---"
    echo "passed: $ok  failed: $fail"
fi
[ "$fail" -eq 0 ]
