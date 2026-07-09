#!/usr/bin/env bash
# tooling-update.sh — keep the tooling volume + system toolchain current.
# Runs on boot from startup.sh (fail-soft; full log kept on the USB) or on
# demand. Updates: apt toolchain, node/npm globals, pip libraries INSIDE this
# volume (pylib), and reports versions so drift is visible per boot.
# Usage: bash tooling-update.sh [--offline] [--log <file>]
set -u

TOOLING_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# prefer the volume's own toolchain
export PATH="$TOOLING_ROOT/bin:$TOOLING_ROOT/node/bin:$PATH"
OFFLINE=0
LOG="${TOOLING_LOG:-$TOOLING_ROOT/logs/tooling-update-$(date +%Y%m%d).log}"
while [ $# -gt 0 ]; do
    case "$1" in
        --offline) OFFLINE=1; shift ;;
        --log) LOG="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done
mkdir -p "$(dirname "$LOG")"
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== tooling update start (offline=$OFFLINE) ==="
log "volume: $TOOLING_ROOT"

# ── Version snapshot (always, even offline) ──────────────────────────────────
for tool in python3 node npm git docker; do
    if command -v "$tool" >/dev/null 2>&1; then
        log "  $tool: $("$tool" --version 2>&1 | head -1)"
    else
        log "  $tool: NOT PRESENT"
    fi
done

[ "$OFFLINE" -eq 1 ] && { log "offline — snapshot only, no updates"; exit 0; }

# ── System toolchain (root only; skipped gracefully otherwise) ───────────────
if [ "$(id -u)" -eq 0 ] && command -v apt-get >/dev/null 2>&1; then
    log "apt: update + upgrade toolchain packages"
    apt-get update >>"$LOG" 2>&1 && \
      apt-get install -y --only-upgrade build-essential git curl nodejs npm python3 python3-pip >>"$LOG" 2>&1 \
      || log "apt upgrade reported issues (see log)"
else
    log "apt: skipped (not root or no apt)"
fi

# ── in-volume node/npm (portable toolchain) ──────────────────────────────────
if [ -x "$TOOLING_ROOT/node/bin/npm" ]; then
    log "node(volume): updating npm + globals in-place"
    "$TOOLING_ROOT/node/bin/npm" install -g npm >>"$LOG" 2>&1 || log "in-volume npm self-update reported issues"
    "$TOOLING_ROOT/node/bin/npm" update -g >>"$LOG" 2>&1 || log "in-volume npm -g update reported issues"
elif command -v npm >/dev/null 2>&1; then
    log "npm(system): updating globals"
    npm update -g >>"$LOG" 2>&1 || log "npm -g update reported issues"
fi

# ── Python libs carried on THIS volume (pylib) ───────────────────────────────
if [ -d "$TOOLING_ROOT/pylib" ]; then
    log "pylib: upgrading huggingface_hub in-place"
    python3 -m pip install --quiet --upgrade --target "$TOOLING_ROOT/pylib" huggingface_hub >>"$LOG" 2>&1 \
      || log "pylib upgrade reported issues"
fi

log "=== tooling update done ==="
