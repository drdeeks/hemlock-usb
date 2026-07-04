#!/usr/bin/env bash
# =============================================================================
# knowledge-watcher.sh — Global knowledge inbox watcher (self-healing)
# =============================================================================
# Watches the runtime-root, append-only knowledge store's inbox/ for NEW files
# (docs captured via the gateway on any platform, agent `text`/`file` captures,
# fetched llm.txt, etc.) and indexes each one into knowledge/index.json so the
# store stays searchable. Mirrors volume-git-daemon.sh: it self-heals (restarts
# its scan loop on unexpected error) and stops ONLY on an explicit --stop.
#
# Real-time via inotifywait when available; otherwise a poll every
# KNOWLEDGE_WATCH_INTERVAL seconds. Indexing is idempotent, so a missed event
# is always caught by the next full scan (belt-and-suspenders).
#
# Usage:
#   knowledge-watcher.sh --once        index every un-indexed inbox file, exit
#   knowledge-watcher.sh --supervise   self-healing watch loop (backgrounded)
#   knowledge-watcher.sh --stop        raise the stop flag for a running watcher
#
# Env:
#   HEMLOCK_KNOWLEDGE_DIR      default $RUNTIME_ROOT/knowledge (else /data/knowledge)
#   KNOWLEDGE_WATCH_INTERVAL   poll seconds when inotify is absent (default 30)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The capture engine wrapper (repo scripts/ is the source of truth; the image
# also stages it under /opt/hermes/scripts). Resolve whichever exists.
_find_capture() {
    for c in \
        "$SCRIPT_DIR/../scripts/knowledge-capture.sh" \
        "/scripts/knowledge-capture.sh" \
        "/opt/hermes/scripts/knowledge-capture.sh" \
        "${RUNTIME_ROOT:-/data}/scripts/knowledge-capture.sh"; do
        [ -x "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}
CAPTURE="$(_find_capture || true)"

KDIR="${HEMLOCK_KNOWLEDGE_DIR:-${RUNTIME_ROOT:-/data}/knowledge}"
INBOX="$KDIR/inbox"
STATE="$KDIR/.watch-state"
INTERVAL="${KNOWLEDGE_WATCH_INTERVAL:-30}"
STOP_FLAG="/var/run/hemlock-knowledge-watch.stop"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [knowledge-watch] $*"; }

_is_doc() {
    # A real capture doc: a regular file in inbox that is not sidecar metadata.
    local base; base="$(basename "$1")"
    case "$base" in *.meta.json|.*) return 1 ;; esac
    [ -f "$1" ]
}

_already() { [ -f "$STATE" ] && grep -qxF "$1" "$STATE" 2>/dev/null; }
_mark()    { printf '%s\n' "$1" >> "$STATE"; }

index_one() {
    local path="$1" base
    _is_doc "$path" || return 0
    base="$(basename "$path")"
    _already "$base" && return 0
    if [ -z "$CAPTURE" ]; then
        log "capture engine not found — cannot index $base"
        return 1
    fi
    if "$CAPTURE" index "$path" >/dev/null 2>&1; then
        _mark "$base"
        log "indexed: $base"
    else
        log "index failed (will retry next scan): $base"
    fi
}

scan_all() {
    [ -d "$INBOX" ] || return 0
    local f
    for f in "$INBOX"/*; do
        [ -e "$f" ] || continue
        index_one "$f" || true
    done
}

supervise() {
    rm -f "$STOP_FLAG" 2>/dev/null || true
    mkdir -p "$INBOX" 2>/dev/null || true
    touch "$STATE" 2>/dev/null || true
    log "watcher started (dir=$KDIR)"
    scan_all   # baseline: catch anything captured while we were down

    if command -v inotifywait >/dev/null 2>&1; then
        log "using inotify (real-time)"
        while [ ! -f "$STOP_FLAG" ]; do
            # -q quiet, -t timeout so we periodically re-check the stop flag and
            # do a safety re-scan even if an event was missed.
            local newfile
            newfile="$(inotifywait -q -t "$INTERVAL" -e close_write -e moved_to \
                        --format '%f' "$INBOX" 2>/dev/null)" || true
            [ -f "$STOP_FLAG" ] && break
            if [ -n "$newfile" ]; then
                index_one "$INBOX/$newfile" || true
            else
                scan_all || true   # timeout tick → safety sweep
            fi
        done
    else
        log "inotifywait absent — polling every ${INTERVAL}s"
        while [ ! -f "$STOP_FLAG" ]; do
            local waited=0
            while [ "$waited" -lt "$INTERVAL" ] && [ ! -f "$STOP_FLAG" ]; do
                sleep 5; waited=$((waited + 5))
            done
            [ -f "$STOP_FLAG" ] && break
            scan_all || log "scan encountered issues (continuing)"
        done
    fi
    log "watcher stopped (explicit stop)"
}

case "${1:-}" in
    --once)      mkdir -p "$INBOX" 2>/dev/null || true; touch "$STATE" 2>/dev/null || true; scan_all ;;
    --supervise) trap 'touch "$STOP_FLAG"' USR1; supervise ;;
    --stop)      touch "$STOP_FLAG"; log "stop flag raised" ;;
    *)           echo "usage: knowledge-watcher.sh --once|--supervise|--stop"; exit 1 ;;
esac
