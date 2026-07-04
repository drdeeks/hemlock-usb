#!/bin/bash
# =============================================================================
# Agent Restart Script - Stop and start with optional overrides
# =============================================================================

set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: $(basename "$0") <AGENT_ID> [OVERRIDE...]"
    exit 1
fi

AGENT_ID="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

./scripts/agent-stop.sh "$AGENT_ID"
./scripts/agent-run.sh "$AGENT_ID" "$@"