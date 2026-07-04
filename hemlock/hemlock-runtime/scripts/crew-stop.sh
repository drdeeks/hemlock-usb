#!/bin/bash
# =============================================================================
# Crew Stop Script
# Stop all agents in a crew
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[FAIL]${NC} $1"; }

usage() {
    cat <<EOF
${GREEN}Crew Stop Tool${NC}

Usage: $0 <crew_name>

Stop all agents in a crew.

Arguments:
  crew_name    Name of the crew to stop

Examples:
  $0 dev-team
  $0 research-team

Options:
  --help       Show this help
EOF
    exit 0
}

CREW_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage ;;
        *)
            if [[ -z "$CREW_NAME" ]]; then
                CREW_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$CREW_NAME" ]]; then
    error "Crew name is required"
    usage
fi

if [[ ! -d "$CREWS_DIR/$CREW_NAME" ]]; then
    warn "Crew '$CREW_NAME' does not exist or is already stopped"
    exit 0
fi

log "Stopping crew '$CREW_NAME'..."

AGENTS=$(grep "^    - " "$CREWS_DIR/$CREW_NAME/crew.yaml" | sed 's/^    - //' 2>/dev/null || echo "")

if [[ -z "$AGENTS" ]]; then
    warn "No agents found in crew '$CREW_NAME'"
else
    for agent in $AGENTS; do
        CONTAINER_NAME="oc-$agent"
        if command -v docker &>/dev/null && docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' 2>/dev/null | grep -q "$CONTAINER_NAME"; then
            log "Stopping agent: $agent"
            docker compose -f "$DOCKER_COMPOSE_FILE" stop "$CONTAINER_NAME" 2>/dev/null || true
            success "Agent '$agent' stopped"
        else
            log "Agent '$agent' is not running (Docker unavailable or container not found)"
        fi
    done
fi

TMP_FILE=$(mktemp)
sed "s/status: active/status: stopped/" "$CREWS_DIR/$CREW_NAME/crew.yaml" > "$TMP_FILE" 2>/dev/null && \
    mv "$TMP_FILE" "$CREWS_DIR/$CREW_NAME/crew.yaml" || true

TIMESTAMP=$(date -Iseconds 2>/dev/null || date)
mkdir -p "$CREWS_DIR/$CREW_NAME/logs"
echo "[$TIMESTAMP] Crew '$CREW_NAME' stopped" >> "$CREWS_DIR/$CREW_NAME/logs/crew.log" 2>/dev/null || true

success "Crew '$CREW_NAME' stop completed"
