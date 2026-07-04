#!/bin/bash
# =============================================================================
# Crew Join Script
# Add an agent to an existing crew
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
${GREEN}Crew Join Tool${NC}

Usage: $0 <crew_name> <agent_id>

Add an agent to an existing crew.

Arguments:
  crew_name    Name of the crew to join
  agent_id     ID of the agent to add

Examples:
  $0 dev-team mort
  $0 research-team data-agent

Options:
  --force      Force re-add if already in crew
  --help       Show this help
EOF
    exit 0
}

# Parse arguments
CREW_NAME=""
AGENT_ID=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
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
    error "Crew '$CREW_NAME' does not exist. Use crew-create.sh first."
    exit 1
fi

# Validate agent exists
if ! agent_exists "$AGENT_ID"; then
    error "Agent '$AGENT_ID' does not exist. Use agent-create.sh first."
    exit 1
fi

# Check if agent is already in crew
if grep -q "^    - $AGENT_ID$" "$CREWS_DIR/$CREW_NAME/crew.yaml" 2>/dev/null; then
    if [[ "$FORCE" == true ]]; then
        log "Agent '$AGENT_ID' already in crew, forcing re-add..."
    else
        log "Agent '$AGENT_ID' is already in crew '$CREW_NAME'"
        echo "Use --force to re-add or check: cat $CREWS_DIR/$CREW_NAME/crew.yaml"
        exit 0
    fi
fi

# Read crew config
CREW_CHANNEL=$(grep "channel:" "$CREWS_DIR/$CREW_NAME/crew.yaml" | awk '{print $2}' 2>/dev/null || echo "crew-$CREW_NAME")
CREW_STATUS=$(grep "status:" "$CREWS_DIR/$CREW_NAME/crew.yaml" | awk '{print $2}' 2>/dev/null || echo "active")

# Add agent to crew.yaml
log "Adding agent '$AGENT_ID' to crew '$CREW_NAME'..."

# Create temporary file
TMP_FILE=$(mktemp)

# Update agents list
awk -v agent="$AGENT_ID" '
/^  agents:/{print; in_agents=1; next}
in_agents && /^    - /{print; next}
in_agents && !/^    /{in_agents=0}
in_agents && !seen_agent{
    print "    - " agent;
    seen_agent=1
}
{print}
' "$CREWS_DIR/$CREW_NAME/crew.yaml" > "$TMP_FILE"

# Replace original
mv "$TMP_FILE" "$CREWS_DIR/$CREW_NAME/crew.yaml"

success "Agent added to crew configuration"

# Now update docker-compose.yml if needed
if ! grep -q "CREW_CHANNEL=$CREW_CHANNEL" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
    log "Updating docker-compose.yml for agent '$AGENT_ID'..."
    
    # Find the agent service and add/update CREW_CHANNEL
    awk -v agent_id="$AGENT_ID" -v channel="$CREW_CHANNEL" '
    /oc-' agent_id ':/{
        in_service=1
        print
        next
    }
    in_service && /environment:/{
        print
        # Check if CREW_CHANNEL already exists
        if (!seen_crew) {
            print "      - CREW_CHANNEL='" channel "'"
            seen_crew=1
        }
        in_service=0
        next
    }
    in_service && /^$/{
        # If we hit a blank line before environment, add it
        if (!seen_env && !seen_crew) {
            print "    environment:"
            print "      - CREW_CHANNEL='" channel "'"
            seen_env=1
            seen_crew=1
        }
        in_service=0
    }
    {print}
    ' "$DOCKER_COMPOSE_FILE" > "$TMP_FILE" 2>/dev/null
    
    mv "$TMP_FILE" "$DOCKER_COMPOSE_FILE"
    success "docker-compose.yml updated"
fi

# Install default skills for the agent if not already installed
if [[ -d "$AGENTS_DIR/$AGENT_ID" ]]; then
    log "Installing default skills for agent '$AGENT_ID'..."
    "$SCRIPT_DIR/skills-install.sh" --quiet "$AGENT_ID" 2>/dev/null || \
        log "  Note: Some skills for $AGENT_ID may not be available"
fi

# Log the join
log "Updating crew logs..."
TIMESTAMP=$(date -Iseconds)
echo "[$TIMESTAMP] Agent '$AGENT_ID' joined crew '$CREW_NAME'" >> "$CREWS_DIR/$CREW_NAME/logs/crew.log"

# Success
log "Crew '$CREW_NAME' updated successfully!"
echo ""
echo "  Crew:      $CREW_NAME"
echo "  Channel:   $CREW_CHANNEL"
echo "  Agent:     $AGENT_ID"
echo ""
echo "Next steps:"
echo "  1. Stop the agent:     ./scripts/agent-control.sh stop $AGENT_ID"
echo "  2. Rebuild the image:  docker compose build oc-$AGENT_ID"
echo "  3. Start the agent:    ./scripts/agent-control.sh start $AGENT_ID"
echo ""
echo "The agent will automatically join channel '$CREW_CHANNEL' on startup."
