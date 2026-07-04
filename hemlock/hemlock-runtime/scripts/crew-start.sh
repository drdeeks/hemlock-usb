#!/bin/bash
# =============================================================================
# Crew Start Script
# Start all agents in a crew with their channel assignments
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
${GREEN}Crew Start Tool${NC}

Usage: $0 <crew_name>

Start all agents in a crew with their channel assignments.

Arguments:
  crew_name    Name of the crew to start

Examples:
  $0 dev-team
  $0 research-team

Options:
  --help       Show this help
EOF
    exit 0
}

# Parse arguments
CREW_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$CREW_NAME" ]]; then
                CREW_NAME="$1"
            else
                error "Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$CREW_NAME" ]]; then
    error "Crew name is required"
    usage
fi

# Validate crew exists
if [[ ! -d "$CREWS_DIR/$CREW_NAME" ]]; then
    error "Crew '$CREW_NAME' does not exist"
    exit 1
fi

# Get crew info
CREW_CHANNEL=$(grep "channel:" "$CREWS_DIR/$CREW_NAME/crew.yaml" | awk '{print $2}' 2>/dev/null || echo "crew-$CREW_NAME")
CREW_STATUS=$(grep "status:" "$CREWS_DIR/$CREW_NAME/crew.yaml" | awk '{print $2}' 2>/dev/null || echo "unknown")

# Get agents in crew
AGENTS=$(grep "^    - " "$CREWS_DIR/$CREW_NAME/crew.yaml" | sed 's/^    - //' || echo "")

if [[ -z "$AGENTS" ]]; then
    error "No agents found in crew '$CREW_NAME'. Add agents first with crew-join.sh"
    exit 1
fi

# Check if crew is already active
if [[ "$CREW_STATUS" == "active" ]]; then
    log "Crew '$CREW_NAME' is already active"
    echo ""
    echo "Current status:"
    for agent in $AGENTS; do
        if is_service_running "oc-$agent"; then
            STATUS=$(docker ps --filter "name=oc-$agent" --format '{{.Status}}' | head -1)
            echo -e "  ${GREEN}$agent: RUNNING${NC} ($STATUS)"
        else
            echo -e "  ${RED}$agent: STOPPED${NC}"
        fi
    done
    echo ""
    read -rp "Restart all agents in this crew? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Crew start cancelled"
        exit 0
    fi
fi

# Update crew status
TMP_FILE=$(mktemp)
sed "s/status: .*/status: active/" "$CREWS_DIR/$CREW_NAME/crew.yaml" > "$TMP_FILE"
mv "$TMP_FILE" "$CREWS_DIR/$CREW_NAME/crew.yaml"

# Ensure CREW_CHANNEL environment variable is set in docker-compose.yml
log "Verifying CREW_CHANNEL assignments..."

# First, rebuild all agent images with crew channel
log "Rebuilding agent images with crew channel '$CREW_CHANNEL'..."

for agent in $AGENTS; do
    # Check if CREW_CHANNEL is already in the service
    if ! grep -q "oc-$agent:" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        warn "Agent 'oc-$agent' not found in docker-compose.yml. Skipping..."
        continue
    fi
    
    # Add or update CREW_CHANNEL
    if grep -q "CREW_CHANNEL=" "$DOCKER_COMPOSE_FILE" && grep -B5 "oc-$agent:" "$DOCKER_COMPOSE_FILE" | grep -q "CREW_CHANNEL="; then
        # Update existing
        TMP_FILE=$(mktemp)
        sed "s/CREW_CHANNEL=.*/CREW_CHANNEL='$CREW_CHANNEL'/g" "$DOCKER_COMPOSE_FILE" > "$TMP_FILE"
        mv "$TMP_FILE" "$DOCKER_COMPOSE_FILE"
        log "Updated CREW_CHANNEL for $agent"
    else
        # Add to oc-$agent service
        TMP_FILE=$(mktemp)
        awk -v agent_id="$agent" -v channel="$CREW_CHANNEL" '
        /oc-' agent_id '/{
            in_service=1
            print
            next
        }
        in_service && /environment:/{
            print
            print "      - CREW_CHANNEL='" channel "'"
            in_service=0
            next
        }
        in_service && /^[a-zA-Z]/ && !/environment/{
            print "    environment:"
            print "      - CREW_CHANNEL='" channel "'"
            in_service=0
        }
        {print}
        ' "$DOCKER_COMPOSE_FILE" > "$TMP_FILE" 2>/dev/null
        mv "$TMP_FILE" "$DOCKER_COMPOSE_FILE"
        log "Added CREW_CHANNEL for $agent"
    fi
done

# Validate docker-compose.yml
if ! docker compose -f "$DOCKER_COMPOSE_FILE" config > /dev/null 2>&1; then
    error "docker-compose.yml has errors after crew channel updates"
    error "Please check the file and try again"
    exit 1
fi

success "Docker Compose configuration validated"

# Rebuild images
log "Rebuilding Docker images..."
if ! docker compose -f "$DOCKER_COMPOSE_FILE" build 2>&1; then
    error "Failed to rebuild Docker images"
    exit 1
fi

success "Docker images rebuilt"

# Start all agents in the crew
log "Starting agents in crew '$CREW_NAME'..."
FAILED_AGENTS=()
SUCCESS_COUNT=0

for agent in $AGENTS; do
    CONTAINER_NAME="oc-$agent"
    
    # Stop if already running
    if is_service_running "$CONTAINER_NAME"; then
        log "Stopping existing container: $CONTAINER_NAME"
        docker compose -f "$DOCKER_COMPOSE_FILE" stop "$CONTAINER_NAME" 2>/dev/null || true
        sleep 2
    fi
    
    # Start
    log "Starting agent: $agent"
    if docker compose -f "$DOCKER_COMPOSE_FILE" up -d "$CONTAINER_NAME" 2>&1; then
        # Wait a moment
        sleep 5
        
        # Check if running
        if is_service_running "$CONTAINER_NAME"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            success "Agent '$agent' started"
            
            # Log to crew log
            TIMESTAMP=$(date -Iseconds)
            echo "[$TIMESTAMP] Agent '$agent' started and joined channel '$CREW_CHANNEL'" >> "$CREWS_DIR/$CREW_NAME/logs/crew.log"
        else
            FAILED_AGENTS+=("$agent")
            error "Agent '$agent' failed to start"
        fi
    else
        FAILED_AGENTS+=("$agent")
        error "Failed to start agent '$agent'"
    fi
done

# Summary
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Crew Start Summary                            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Crew:        $CREW_NAME"
echo "  Channel:     $CREW_CHANNEL"
echo "  Started:     $SUCCESS_COUNT agent(s)"

if [[ ${#FAILED_AGENTS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}Failed to start:${NC}"
    for agent in "${FAILED_AGENTS[@]}"; do
        echo "  - $agent"
    done
    echo ""
    echo "Check logs with:"
    for agent in "${FAILED_AGENTS[@]}"; do
        echo "  docker logs oc-$agent"
    done
    exit 1
else
    echo ""
    echo -e "${GREEN}All agents started successfully!${NC}"
    echo ""
    echo "Crew '$CREW_NAME' is now active and ready for collaboration."
    echo "All agents are connected to channel '$CREW_CHANNEL'."
    echo ""
    echo "Monitor the crew with:"
    echo "  ./scripts/crew-monitor.sh $CREW_NAME"
fi
