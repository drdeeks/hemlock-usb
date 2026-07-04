#!/usr/bin/env bash
# =============================================================================
# volume-git-daemon.sh — Per-volume git snapshots (daily), self-healing
# =============================================================================
# Makes each agent/crew volume a git repository and commits the ENTIRE volume
# once per day, so every agent can roll back any change in any directory
# (see the per-agent tools/rollback.sh). Mirrors the skills-updater supervisor:
# it self-heals (restarts on unexpected exit) and stops ONLY on an explicit stop.
#
# Usage:
#   volume-git-daemon.sh --once        init + commit every volume once, then exit
#   volume-git-daemon.sh --supervise   self-healing daily loop (backgrounded)
#   volume-git-daemon.sh --stop        raise the stop flag for a running supervisor
#
# Env:
#   AGENTS_ROOT           default /data/agents
#   CREWS_ROOT            default /data/crews
#   VOLUME_GIT_INTERVAL   seconds between snapshots (default 86400 = daily)
# =============================================================================

set -uo pipefail

AGENTS_ROOT="${AGENTS_ROOT:-/data/agents}"
CREWS_ROOT="${CREWS_ROOT:-/data/crews}"
INTERVAL="${VOLUME_GIT_INTERVAL:-86400}"
STOP_FLAG="/var/run/hemlock-volume-git.stop"
GIT_USER_NAME="${VOLUME_GIT_NAME:-Hemlock Snapshot}"
GIT_USER_EMAIL="${VOLUME_GIT_EMAIL:-snapshot@hemlock.local}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [volume-git] $*"; }

# Is this dir a real agent/crew volume (not a control/template dir)?
_is_agent_dir() {
    local base; base="$(basename "$1")"
    case "$base" in .*|active|archive|workspace-template) return 1 ;; esac
    [ -d "$1" ]
}

init_repo() {
    local dir="$1"
    git config --global --add safe.directory "$dir" 2>/dev/null || true
    if [ ! -d "$dir/.git" ]; then
        git -C "$dir" init -q 2>/dev/null || { log "init failed: $dir"; return 1; }
        log "initialized git repo: $dir"
    fi
    # Local identity so commits succeed under a bare root container.
    git -C "$dir" config user.name  "$GIT_USER_NAME"  2>/dev/null || true
    git -C "$dir" config user.email "$GIT_USER_EMAIL" 2>/dev/null || true
}

commit_volume() {
    local dir="$1"
    _is_agent_dir "$dir" || return 0
    init_repo "$dir" || return 1
    # Stage everything honoring the volume's .gitignore, commit only if changed.
    git -C "$dir" add -A 2>/dev/null || true
    if git -C "$dir" diff --cached --quiet 2>/dev/null; then
        return 0   # nothing changed
    fi
    if git -C "$dir" commit -q -m "daily snapshot $(date -Iseconds)" 2>/dev/null; then
        log "snapshot: $(basename "$dir")"
    fi
}

run_once() {
    local root d
    for root in "$AGENTS_ROOT" "$CREWS_ROOT"; do
        [ -d "$root" ] || continue
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            commit_volume "${d%/}" || true
        done
    done
}

supervise() {
    rm -f "$STOP_FLAG" 2>/dev/null || true
    log "supervisor started (interval=${INTERVAL}s)"
    # Snapshot once at startup so a fresh boot has a baseline commit.
    run_once
    while [ ! -f "$STOP_FLAG" ]; do
        local waited=0
        while [ "$waited" -lt "$INTERVAL" ] && [ ! -f "$STOP_FLAG" ]; do
            sleep 30; waited=$((waited + 30))
        done
        [ -f "$STOP_FLAG" ] && break
        run_once || log "run_once encountered issues (continuing)"
    done
    log "supervisor stopped (explicit stop)"
}

case "${1:-}" in
    --once)      run_once ;;
    --supervise) trap 'touch "$STOP_FLAG"' USR1; supervise ;;
    --stop)      touch "$STOP_FLAG"; log "stop flag raised" ;;
    *)           echo "usage: volume-git-daemon.sh --once|--supervise|--stop"; exit 1 ;;
esac
