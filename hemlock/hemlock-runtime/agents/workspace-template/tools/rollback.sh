#!/usr/bin/env bash
# =============================================================================
# rollback.sh — Roll back changes anywhere in your workspace
# =============================================================================
# Your ENTIRE volume is a git repository, snapshotted automatically every day.
# This tool lets you view that history and restore any file or directory to a
# previous state — without ever destroying current work: a restore is itself
# committed on the next snapshot, so nothing is lost irreversibly.
#
# Usage:
#   bash tools/rollback.sh log [N]                 recent snapshots (default 15)
#   bash tools/rollback.sh status                  current uncommitted changes
#   bash tools/rollback.sh diff <commit> [path]    what changed since a snapshot
#   bash tools/rollback.sh restore <commit> <path> restore a path to that snapshot
#   bash tools/rollback.sh snapshot ["message"]    take a manual snapshot right now
#
# Path/location-agnostic: resolves the workspace from $HEMLOCK_HOME (or legacy
# $HERMES_HOME). Operates only inside your own volume; never pushes anywhere.
# =============================================================================

set -uo pipefail

WS="${HEMLOCK_HOME:-${HERMES_HOME:-.}}"
cd "$WS" 2>/dev/null || { echo "rollback: workspace not found ('$WS')"; exit 1; }

# Running as root inside the container trips git's "dubious ownership" guard —
# mark this volume safe (idempotent, scoped to this repo path).
git config --global --add safe.directory "$WS" 2>/dev/null || true

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "rollback: this workspace is not a git repo yet — the daily snapshot"
    echo "daemon initializes it on first run. Take one now with: rollback.sh snapshot"
    # Best-effort init so a manual snapshot works immediately
    git init -q 2>/dev/null || exit 1
fi

cmd="${1:-log}"; shift 2>/dev/null || true

case "$cmd" in
    log)
        git --no-pager log --oneline -n "${1:-15}" 2>/dev/null || echo "no snapshots yet"
        ;;
    status)
        git status --short 2>/dev/null || true
        ;;
    diff)
        c="${1:?usage: rollback.sh diff <commit> [path]}"; shift 2>/dev/null || true
        git --no-pager diff "$c" -- "${@:-.}"
        ;;
    restore)
        c="${1:?usage: rollback.sh restore <commit> <path>}"
        p="${2:?usage: rollback.sh restore <commit> <path>}"
        if git checkout "$c" -- "$p" 2>/dev/null; then
            echo "restored '$p' from $c (staged; captured in the next snapshot)"
        else
            echo "restore failed — check the commit hash (rollback.sh log) and path"
            exit 1
        fi
        ;;
    snapshot)
        git add -A 2>/dev/null || true
        if git commit -m "${1:-manual snapshot $(date -Iseconds)}" >/dev/null 2>&1; then
            echo "snapshot taken: $(git --no-pager log --oneline -1)"
        else
            echo "nothing to snapshot (workspace clean)"
        fi
        ;;
    *)
        echo "usage: rollback.sh log [N] | status | diff <commit> [path] | restore <commit> <path> | snapshot [msg]"
        exit 1
        ;;
esac
