#!/bin/bash
# =============================================================================
# Agent Logs Script - Stream agent logs in real-time
# =============================================================================

set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: $(basename "$0") <AGENT_ID>"
    exit 1
fi

AGENT_ID="$1"

if [[ ! -f .env ]]; then
    echo "Error: .env file not found"
    exit 1
fi

source .env

docker compose -p "$AGENT_ID" -f docker-compose.yml logs -f