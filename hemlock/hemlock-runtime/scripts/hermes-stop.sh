#!/bin/bash
# =============================================================================
# Hermes Agent Stop Script
# Stops running Hermes agents
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
success() { echo -e "${GREEN}[OK]${NC} $1"; }

usage() {
    cat << EOF
${GREEN}Hermes Agent Stop Script${NC}

Usage: $0 <AGENT_ID> [OPTIONS]

Arguments:
    AGENT_ID          Agent identifier

Options:
    -h, --help        Show this help
    -f, --force       Force stop
    -t, --timeout     Seconds to wait before kill (default: 10)

Examples:
    $0 mort
    $0 mort --force

EOF
    exit 1
}

AGENT_ID=""
FORCE=""
TIMEOUT=10

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -f|--force) FORCE="--signal=SIGKILL"; shift ;;
        -t|--timeout) TIMEOUT="$2"; shift 2 ;;
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
    log "Stopping agent: ${AGENT_ID}"
    docker stop $FORCE -t "$TIMEOUT" "$CONTAINER_NAME" 2>/dev/null && \
        docker rm "$CONTAINER_NAME" 2>/dev/null && \
        success "Agent '${AGENT_ID}' stopped and removed" || \
        success "Agent '${AGENT_ID}' stopped"
else
    error "Agent not running: ${AGENT_ID}"
    exit 1
fi