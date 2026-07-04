#!/bin/bash
# =============================================================================
# Crew Creation Script
# Creates a new crew session with multiple agents for collaborative work
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
${GREEN}Crew Creation Tool${NC}

Usage: $0 <crew_name> <agent1> [agent2] [agent3] ...

Create a collaborative crew session with multiple agents.

Arguments:
  crew_name    Unique name for the crew (e.g., dev-team, research)
  agents      List of agent IDs to include in the crew

Examples:
  $0 dev-team mort avery lex
  $0 research-team data-agent research-agent
  $0 analysis crew1 agent1 agent2 agent3

Options:
  --duration <seconds>   Crew session duration (default: 86400 = 24 hours)
  --owner <user>        Crew owner (default: current user)
  --private            Make crew private (invite-only)
  --help               Show this help
EOF
    exit 0
}

# Parse arguments
CREW_NAME=""
AGENTS=()
DURATION=86400
OWNER="$(whoami)"
PRIVATE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --owner)
            OWNER="$2"
            shift 2
            ;;
        --private)
            PRIVATE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$CREW_NAME" ]]; then
                CREW_NAME="$1"
            else
                AGENTS+=("$1")
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$CREW_NAME" ]]; then
    error "Crew name is required"
    echo "Usage: $0 <crew_name> <agent1> [agent2] ..."
    exit 1
fi

if [[ ${#AGENTS[@]} -eq 0 ]]; then
    error "At least one agent is required"
    echo "Usage: $0 <crew_name> <agent1> [agent2] ..."
    exit 1
fi

# Validate crew name
if ! [[ "$CREW_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{2,20}$ ]]; then
    error "Invalid crew name. Must be 3-21 chars, alphanumeric, start with letter/number, only a-zA-Z0-9_-"
    exit 1
fi

# Check if crew already exists
if [[ -d "$CREWS_DIR/$CREW_NAME" ]]; then
    error "Crew '$CREW_NAME' already exists"
    exit 1
fi

# Validate all agents exist
for agent in "${AGENTS[@]}"; do
    if ! agent_exists "$agent"; then
        error "Agent '$agent' does not exist"
        exit 1
    fi
done

# Docker availability is OPTIONAL per CL-012 / CL-014: crews live as a per-crew
# named volume IF docker is reachable from this caller (host-side menu, or a
# container with --network=host AND docker socket). Inside the runtime
# container (the common path) docker is NOT available — that's by design (no
# socket bind). Downgraded from fatal exit to warning so the rest of the crew
# scaffolding (yaml, SOUL.md, log dir) still happens.
if ! check_docker; then
    log "  (docker not available from this caller — skipping per-crew volume provisioning)"
fi

# Create crew directory
log "Creating crew: $CREW_NAME"
mkdir -p "$CREWS_DIR/$CREW_NAME"

# Create crew.yaml
CREW_ID="crew-$(date +%s)-$(openssl rand -hex 3)"
CREW_CHANNEL="crew-$CREW_NAME"
TIMESTAMP=$(date -Iseconds)

cat > "$CREWS_DIR/$CREW_NAME/crew.yaml" <<EOF
crew:
  name: $CREW_NAME
  id: $CREW_ID
  channel: $CREW_CHANNEL
  agents:
$(for agent in "${AGENTS[@]}"; do echo "    - $agent"; done)
  created: $TIMESTAMP
  expires: $(date -d "+$DURATION seconds" -Iseconds 2>/dev/null || date -d "+$DURATION seconds" -Iseconds 2>/dev/null || echo "")
  duration: $DURATION
  status: active
  owner: $OWNER
  private: $PRIVATE
  security:
    isolate_agents: true
    allow_agent_dm: false
    shared_memory: false
EOF

success "Crew configuration created"

# Create crew SOUL.md
cat > "$CREWS_DIR/$CREW_NAME/SOUL.md" <<EOF
# Crew: $CREW_NAME

**Identity:** Collaborative team of agents

**Purpose:** $CREW_NAME crew for multi-agent collaboration

**Created:** $TIMESTAMP
**Owner:** $OWNER
**Duration:** ${DURATION} seconds ($(echo "scale=1; $DURATION/3600" | bc 2>/dev/null) hours)

**Members:**
$(for agent in "${AGENTS[@]}"; do echo "- $agent"; done)

**Channel:** $CREW_CHANNEL

**Security:**
- Agents remain isolated (separate containers)
- No direct agent-to-agent communication
- All messages routed through Gateway
- Each agent maintains its own brain and memory
EOF

success "Crew SOUL.md created"

# Provision the shared crew docker volume (per CL-012: one container, dynamically
# generated/destroyed Docker volumes per crew — nothing on host filesystem).
if command -v docker >/dev/null 2>&1; then
    CREW_VOLUME="hemlock_crew_${CREW_NAME}"
    if ! docker volume inspect "$CREW_VOLUME" >/dev/null 2>&1; then
        if docker volume create \
                --label "crew=${CREW_NAME}" \
                --label "crew_id=${CREW_ID}" \
                --label "framework=hemlock" \
                "$CREW_VOLUME" >/dev/null 2>&1; then
            success "Docker volume created: $CREW_VOLUME"
        else
            log "  (docker volume create failed for $CREW_VOLUME — continuing)"
        fi
    else
        log "  Docker volume already exists: $CREW_VOLUME"
    fi
else
    log "  docker not available — skipping crew volume provisioning"
fi

# Install default skills for each agent in the crew
echo "Installing default skills for crew members..."
for agent in "${AGENTS[@]}"; do
    if [[ -d "$AGENTS_DIR/$agent" ]]; then
        "$SCRIPT_DIR/skills-install.sh" --quiet "$agent" 2>/dev/null || \
            echo "  Note: Some skills for $agent may not be available"
    else
        log "  Agent $agent does not exist yet, skills will be installed on first creation"
    fi
done

# Create crew log directory
mkdir -p "$CREWS_DIR/$CREW_NAME/logs"
touch "$CREWS_DIR/$CREW_NAME/logs/crew.log"

# Notify users about next steps
log "Crew '$CREW_NAME' created successfully!"
echo ""
echo "  Crew ID:       $CREW_ID"
echo "  Channel:       $CREW_CHANNEL"
echo "  Members:      ${AGENTS[*]}"
echo "  Location:      $CREWS_DIR/$CREW_NAME"
echo "  Expires:       $(date -d "+$DURATION seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'N/A')"
echo ""
echo "To start the crew, assign agents to the channel:"
for agent in "${AGENTS[@]}"; do
    echo "  1. Stop agent:       ./scripts/agent-control.sh stop $agent"
    echo "  2. Add to crew:      ./scripts/crew-join.sh $CREW_NAME $agent"
    echo "  3. Start agent:      ./scripts/agent-control.sh start $agent"
done
echo ""
echo "Or use the automated crew start:"
echo "  ./scripts/crew-start.sh $CREW_NAME"
