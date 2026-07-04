#!/bin/bash
# =============================================================================
# knowledge.sh — capture into the GLOBAL (runtime-root) knowledge store
# =============================================================================
# Every agent shares ONE append-only knowledge base at the runtime root. When
# your owner sends you a link, an llm.txt, a doc, or any reference — capture it
# here so the whole system (and future-you) can find it. Captures are tagged
# with YOUR identity but stored globally, classified by use / function / scope.
#
# This is a thin, PATH-RESOLVING wrapper: it locates the baked engine and
# injects --agent = your id. It writes to the GLOBAL store, never your volume.
#
#   bash tools/knowledge.sh url  <URL>  [--title T --use U --function F --scope S --tag t]
#   bash tools/knowledge.sh file <PATH> [flags]
#   bash tools/knowledge.sh text --title T   < content     # e.g. a pasted llm.txt
#   bash tools/knowledge.sh search <query...>
#   bash tools/knowledge.sh list | status
#
# Env: HEMLOCK_KNOWLEDGE_DIR overrides the store (default runtime-root/knowledge).
# =============================================================================
set -uo pipefail

# Your identity (for --agent tagging): AGENT_ID, else the volume's basename.
WS="${HEMLOCK_HOME:-${HERMES_HOME:-$PWD}}"
AGENT="${AGENT_ID:-$(basename "$WS" 2>/dev/null || echo default)}"

# The GLOBAL store — NOT your volume. Default to the runtime root's knowledge/.
export HEMLOCK_KNOWLEDGE_DIR="${HEMLOCK_KNOWLEDGE_DIR:-${RUNTIME_ROOT:-/data}/knowledge}"

# Locate the baked engine (path-resolving; do not hardcode one location).
ENGINE=""
for c in /scripts/knowledge_capture.py /opt/hermes/scripts/knowledge_capture.py \
         "${RUNTIME_ROOT:-/data}/scripts/knowledge_capture.py"; do
    [ -f "$c" ] && { ENGINE="$c"; break; }
done
if [ -z "$ENGINE" ]; then
    echo "[knowledge] global knowledge engine not found on this runtime" >&2
    exit 127
fi

PY="$(command -v python3 || command -v python)"
[ -z "$PY" ] && { echo "[knowledge] python3 not found" >&2; exit 127; }

cmd="${1:-status}"; shift || true
case "$cmd" in
    # Capture verbs get the agent tag injected automatically.
    url|file|text|message)
        exec "$PY" "$ENGINE" "$cmd" "$@" --agent "$AGENT"
        ;;
    # Read/inspect verbs pass straight through.
    search|list|status|index|rebuild)
        exec "$PY" "$ENGINE" "$cmd" "$@"
        ;;
    *)
        echo "usage: knowledge.sh url|file|text|search|list|status <args>" >&2
        exit 1
        ;;
esac
