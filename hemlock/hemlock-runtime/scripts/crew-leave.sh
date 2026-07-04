#!/bin/bash
# =============================================================================
# Crew Leave Script
# Remove an agent from a crew
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Usage
usage() {
    cat <<EOF
${GREEN}Crew Leave Tool${NC}

Usage: $0 <crew_name> <agent_id>

Remove an agent from a crew.

Arguments:
  crew_name    Name of the crew
  agent_id     ID of the agent to remove

Examples:
  $0 dev-team mort
  $0 research-team data-agent

Options:
  --help       Show this help
EOF
    exit 0
}

# Parse arguments
CREW_NAME=""
AGENT_ID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$CREW_NAME" ]]; then
                CREW_NAME="$1"
            elif [[ -z "$AGENT_ID" ]]; then
                AGENT_ID="$1"
            else
                error "Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$CREW_NAME" ]] || [[ -z "$AGENT_ID" ]]; then
    error "Crew name and agent ID are required"
    usage
fi

# Validate crew exists
if [[ ! -d "$CREWS_DIR/$CREW_NAME" ]]; then
    error "Crew '$CREW_NAME' does not exist"
    exit 1
fi

# Validate agent exists
if ! agent_exists "$AGENT_ID"; then
    error "Agent '$AGENT_ID' does not exist"
    exit 1
fi

# Check if agent is in crew
if ! grep -q "^    - $AGENT_ID$" "$CREWS_DIR/$CREW_NAME/crew.yaml" 2>/dev/null; then
    log "Agent '$AGENT_ID' is not in crew '$CREW_NAME'"
    exit 0
fi

# Remove agent from crew.yaml
log "Removing agent '$AGENT_ID' from crew '$CREW_NAME'..."

# Create temporary file
TMP_FILE=$(mktemp)

# Remove agent from agents list
awk -v agent="$AGENT_ID" '
/^  agents:/{print; in_agents=1; next}
in_agents && /^    - /{
    if ($2 != agent) print
    next
}
in_agents && !/^    /{in_agents=0}
{print}
' "$CREWS_DIR/$CREW_NAME/crew.yaml" > "$TMP_FILE"

# Replace original
mv "$TMP_FILE" "$CREWS_DIR/$CREW_NAME/crew.yaml"

success "Agent removed from crew configuration"

# Update docker-compose.yml to remove CREW_CHANNEL
log "Updating docker-compose.yml..."

TMP_FILE=$(mktemp)

awk -v agent_id="$AGENT_ID" '
/oc-' agent_id ':/{
    in_service=1
    print
    next
}
in_service && /CREW_CHANNEL=/{next}
in_service && /environment:/{
    print
    # Print all lines except CREW_CHANNEL
    while (getline > 0) {
        if (/CREW_CHANNEL=/) next
        if (/^[^ ]/ && !/environment:/) {
            in_service=0
            print
            break
        }
        print
    }
    next
}
{print}
' "$DOCKER_COMPOSE_FILE" > "$TMP_FILE" 2>/dev/null

mv "$TMP_FILE" "$DOCKER_COMPOSE_FILE"
success "docker-compose.yml updated"

# Log the leave
TIMESTAMP=$(date -Iseconds)
echo "[$TIMESTAMP] Agent '$AGENT_ID' left crew '$CREW_NAME'" >> "$CREWS_DIR/$CREW_NAME/logs/crew.log"

# Check if crew is now empty
AGENT_COUNT=$(grep -c "^    - " "$CREWS_DIR/$CREW_NAME/crew.yaml" || echo "0")
if [[ "$AGENT_COUNT" -eq 0 ]]; then
    YELLOW="\033[1;33m"
    echo -e "${YELLOW}[WARN]${NC} Crew '$CREW_NAME' has no members. Consider dissolving it."
    echo "  Run: ./scripts/crew-dissolve.sh $CREW_NAME"
fi

# Success
log "Agent '$AGENT_ID' removed from crew '$CREW_NAME' successfully!"
echo ""
echo "Next steps:"
echo "  1. Stop the agent:     ./scripts/agent-control.sh stop $AGENT_ID"
echo "  2. Rebuild the image:  docker compose build oc-$AGENT_ID"
echo "  3. Start the agent:    ./scripts/agent-control.sh start $AGENT_ID"
echo ""
echo "The agent will no longer receive messages from channel '$CREW_CHANNEL'."
