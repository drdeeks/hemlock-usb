#!/usr/bin/env bash
# =============================================================================
# run-native.sh — run the Hemlock runtime WITHOUT a container
#
# Informative + optional: checks what you have, tells you what each mode needs,
# forces nothing. Same topology toggle as the image: HEMLOCK_MODE=full|hermes|openclaw
# (native default: hermes — cognition standalone; full needs node + OpenClaw lib).
#
#   HEMLOCK_HOME   base for all mutable state (default: ~/.hemlock)
#   HEMLOCK_MODE   full | hermes | openclaw   (default: hermes)
#
# Usage:  scripts/run-native.sh            # hermes cognition, no container
#         HEMLOCK_MODE=full scripts/run-native.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

log()  { echo "[hemlock-native] $*"; }
warn() { echo "[hemlock-native][warn] $*" >&2; }

# ── HOST ISOLATION: users may run their OWN OpenClaw or Hermes on this host.
#    Hemlock is its own combined system — it NEVER adopts host OPENCLAW_*/
#    HERMES_* values and NEVER touches the host install. Everything Hemlock
#    is namespaced under HEMLOCK_HOME; foreign env is warned about and
#    overridden FOR THIS PROCESS TREE ONLY (the host shell is untouched).
export HEMLOCK_HOME="${HEMLOCK_HOME:-$HOME/.hemlock}"
_is_ours() { case "$1" in "$HEMLOCK_HOME"*|"$REPO_ROOT"*) return 0 ;; *) return 1 ;; esac; }
for _v in HERMES_HOME OPENCLAW_ROOT RUNTIME_ROOT AGENTS_DIR CREWS_DIR IMPORTS_DIR EXPORTS_DIR; do
    _cur="${!_v:-}"
    if [ -n "$_cur" ] && ! _is_ours "$_cur"; then
        warn "host $_v=$_cur detected (a host OpenClaw/Hermes install?) — Hemlock will not use or touch it; scoping $_v to HEMLOCK_HOME for this run"
        unset "$_v"
    fi
done
export HERMES_HOME="${HERMES_HOME:-$HEMLOCK_HOME/runtime}"     # legacy alias kept
export RUNTIME_ROOT="${RUNTIME_ROOT:-$HEMLOCK_HOME/data}"
export AGENTS_DIR="${AGENTS_DIR:-$RUNTIME_ROOT/agents}"
export CREWS_DIR="${CREWS_DIR:-$RUNTIME_ROOT/crews}"
export IMPORTS_DIR="${IMPORTS_DIR:-$RUNTIME_ROOT/imports}"
export EXPORTS_DIR="${EXPORTS_DIR:-$RUNTIME_ROOT/exports}"
export OPENCLAW_ROOT="${OPENCLAW_ROOT:-$REPO_ROOT/docker/openclaw-runtime}"
export PYTHONPATH="$REPO_ROOT/docker/hermes-agent:${OPENCLAW_ROOT}/lib${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONUNBUFFERED=1
unset HEMLOCK_DOCKER 2>/dev/null || true
# Never let a host openclaw/hermes binary shadow the bundled ones (PATH may
# lead with a host or USB install; we call ours by absolute path only).

mkdir -p "$HERMES_HOME" "$AGENTS_DIR" "$CREWS_DIR" "$IMPORTS_DIR" "$EXPORTS_DIR" \
         "$RUNTIME_ROOT/knowledge/inbox" "$HEMLOCK_HOME/logs" "$HEMLOCK_HOME/skills"

# Seed agent template + skills on first run (copy, never overwrite existing)
if [ ! -d "$AGENTS_DIR/workspace-template" ] && [ -d "$REPO_ROOT/agents/workspace-template" ]; then
    cp -r "$REPO_ROOT/agents/workspace-template" "$AGENTS_DIR/workspace-template"
    log "Seeded agent workspace-template → $AGENTS_DIR/workspace-template"
fi
if [ -z "$(ls -A "$HEMLOCK_HOME/skills" 2>/dev/null)" ] && [ -d "$REPO_ROOT/shared/skills" ]; then
    cp -r "$REPO_ROOT/shared/skills/." "$HEMLOCK_HOME/skills/"
    log "Seeded curated skills → $HEMLOCK_HOME/skills"
fi

# ── What do we have? (informative, never forced) ──────────────────────────────
MODE="${HEMLOCK_MODE:-full}"   # full = OpenClaw gateway fronting, Hermes brain over MCP
command -v python3 >/dev/null || { warn "python3 is required"; exit 1; }

HAVE_NODE=0; command -v node >/dev/null && HAVE_NODE=1
HAVE_OPENCLAW_LIB=0; [ -d "$OPENCLAW_ROOT/lib/node_modules/openclaw" ] && HAVE_OPENCLAW_LIB=1

# Hermes python deps present? (native machines may not have the package installed)
if ! python3 -c "import gateway.protocol" 2>/dev/null; then
    warn "Hermes python package not importable. Install once with:"
    warn "  pip install --user $REPO_ROOT/docker/hermes-agent"
    exit 1
fi

log "Mode: $MODE  (HEMLOCK_HOME=$HEMLOCK_HOME)"
log "node: $([ $HAVE_NODE -eq 1 ] && node --version || echo 'not found')  |  openclaw lib: $([ $HAVE_OPENCLAW_LIB -eq 1 ] && echo present || echo 'not present')"

run_openclaw() {
    if [ $HAVE_NODE -eq 0 ] || [ $HAVE_OPENCLAW_LIB -eq 0 ]; then
        warn "OpenClaw needs node + $OPENCLAW_ROOT/lib/node_modules/openclaw — falling back to hermes mode"
        return 1
    fi
    export NODE_PATH="$OPENCLAW_ROOT/lib/node_modules${NODE_PATH:+:$NODE_PATH}"
    log "Starting OpenClaw gateway (native)..."
    node "$OPENCLAW_ROOT/lib/node_modules/openclaw/dist/index.js" gateway run --allow-unconfigured &
    OPENCLAW_PID=$!
    log "OpenClaw gateway PID: $OPENCLAW_PID"
    return 0
}

run_hermes() {
    log "Starting Hermes gateway (native)..."
    python3 -m hermes_cli.main gateway run &
    HERMES_PID=$!
    log "Hermes gateway PID: $HERMES_PID"
}

case "$MODE" in
    full)
        if run_openclaw; then
            [ "${ENABLE_HERMES_GATEWAY:-false}" = "true" ] && run_hermes
        else
            run_hermes
        fi
        ;;
    openclaw) run_openclaw || exit 1 ;;
    hermes|*) run_hermes ;;
esac

trap 'kill ${OPENCLAW_PID:-} ${HERMES_PID:-} 2>/dev/null || true' INT TERM
wait
