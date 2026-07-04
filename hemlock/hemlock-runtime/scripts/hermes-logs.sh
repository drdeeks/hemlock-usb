#!/bin/bash
# =============================================================================
# Hermes Agent Logs Script
# View logs from Hermes agents
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
${GREEN}Hermes Agent Logs Script${NC}

Usage: $0 <AGENT_ID> [OPTIONS]

Arguments:
    AGENT_ID          Agent identifier

Options:
    -h, --help        Show this help
    -f, --follow      Follow log output
    -t, --tail        Number of lines to show (default: 100)
    --timestamps      Show timestamps

Examples:
    $0 mort
    $0 mort --follow
    $0 mort --tail 50 --timestamps

EOF
    exit 1
}

AGENT_ID=""
TAIL="--tail 100"
FOLLOW=""
TIMESTAMPS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -f|--follow) FOLLOW="-f"; shift ;;
        -t|--tail) TAIL="--tail $2"; shift 2 ;;
        --timestamps) TIMESTAMPS="--timestamps"; shift ;;
        *)
            if [[ -z "$AGENT_ID" ]]; then
                AGENT_ID="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$AGENT_ID" ]]; then
    error "Agent ID is required"
    usage
fi

CONTAINER_NAME="oc-${AGENT_ID}"

if docker ps -a --filter "name=${CONTAINER_NAME}" -q 2>/dev/null | grep -q .; then
    docker logs $TIMESTAMPS $FOLLOW $TAIL "$CONTAINER_NAME" 2>&1
else
    error "Agent not found: ${AGENT_ID}"
    exit 1
fi