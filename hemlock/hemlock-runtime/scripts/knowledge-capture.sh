#!/bin/bash
# =============================================================================
# Hemlock — knowledge-capture.sh  (T15 global knowledge store, front-end)
#
# Thin, PATH-RESOLVING wrapper around knowledge_capture.py. Resolves the
# runtime root the same way every other tool does, then execs the engine so
# all arbitrary/inbound values pass through argv (never string-interpolated).
#
#   knowledge-capture.sh url <URL> [--title T --use U --function F --scope S ...]
#   knowledge-capture.sh file <PATH> [flags]
#   knowledge-capture.sh text  [--title T] < content
#   knowledge-capture.sh message --agent <id> --source gateway:<platform> --text "<msg>"
#   knowledge-capture.sh index <PATH>
#   knowledge-capture.sh search <query...>
#   knowledge-capture.sh list | status | rebuild
#
# Store location (global, append-only): $HEMLOCK_KNOWLEDGE_DIR
#   default $RUNTIME_ROOT/knowledge  (e.g. /data/knowledge in the container).
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve RUNTIME_ROOT via helpers.sh when present (host + container both work).
if [ -f "$SCRIPT_DIR/helpers.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/helpers.sh" >/dev/null 2>&1 || true
fi
: "${RUNTIME_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"

# Canonical global knowledge dir (env override wins; else runtime-root/knowledge).
export HEMLOCK_KNOWLEDGE_DIR="${HEMLOCK_KNOWLEDGE_DIR:-$RUNTIME_ROOT/knowledge}"
export RUNTIME_ROOT

PY="$(command -v python3 || command -v python)"
if [ -z "$PY" ]; then
    echo "[knowledge-capture] python3 not found" >&2
    exit 127
fi

exec "$PY" "$SCRIPT_DIR/knowledge_capture.py" "$@"
