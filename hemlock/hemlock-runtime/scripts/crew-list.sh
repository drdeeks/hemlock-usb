#!/bin/bash
# =============================================================================
# Crew List Script
# List all active crews and their members
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

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Active Crews                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if crews directory exists
if [[ ! -d "$CREWS_DIR" ]]; then
    echo "No crews directory found. No crews created yet."
    echo ""
    echo "Create your first crew with:"
    echo "  ./scripts/crew-create.sh <crew_name> <agent1> [agent2] ..."
    exit 0
fi

# Count crews
CREW_COUNT=$(find "$CREWS_DIR" -maxdepth 1 -type d ! -name "crews" | wc -l)

if [[ "$CREW_COUNT" -eq 0 ]]; then
    echo "No active crews found."
    echo ""
    echo "Create your first crew with:"
    echo "  ./scripts/crew-create.sh <crew_name> <agent1> [agent2] ..."
    exit 0
fi

# List all crews
for crew_dir in "$CREWS_DIR"/*; do
    if [[ -d "$crew_dir" ]]; then
        crew_name=$(basename "$crew_dir")
        crew_file="$crew_dir/crew.yaml"
        
        if [[ -f "$crew_file" ]]; then
            # Extract crew info
            CREW_CHANNEL=$(grep "channel:" "$crew_file" | awk '{print $2}' 2>/dev/null || echo "N/A")
            CREW_STATUS=$(grep "status:" "$crew_file" | awk '{print $2}' 2>/dev/null || echo "unknown")
            CREW_OWNER=$(grep "owner:" "$crew_file" | awk '{print $2}' 2>/dev/null || echo "unknown")
            CREW_CREATED=$(grep "created:" "$crew_file" | awk '{print $2}' 2>/dev/null || echo "N/A")
            CREW_EXPIRES=$(grep "expires:" "$crew_file" | awk '{print $2}' 2>/dev/null || echo "N/A")
            
            # Get agent count
            AGENT_COUNT=$(grep -c "^    - " "$crew_file" || echo "0")
            
            # Get agents list
            AGENTS=$(grep "^    - " "$crew_file" | sed 's/^    - //' | tr '\n' ',' | sed 's/,$//')
            
            # Display crew info
            echo -e "${GREEN} Crew: ${NC} $crew_name"
            echo "  Channel:   $CREW_CHANNEL"
            echo "  Status:    $CREW_STATUS"
            echo "  Owner:     $CREW_OWNER"
            echo "  Created:   $CREW_CREATED"
            echo "  Expires:   $CREW_EXPIRES"
            echo "  Agents:    $AGENT_COUNT member(s): $AGENTS"
            
            # Check if crew is expired
            if [[ "$CREW_EXPIRES" != "N/A" ]]; then
                EXPIRY_EPOCH=$(date -d "$CREW_EXPIRES" +%s 2>/dev/null || echo "0")
                NOW_EPOCH=$(date +%s)
                if [[ "$EXPIRY_EPOCH" -lt "$NOW_EPOCH" ]]; then
                    echo -e "  ${RED}Status: EXPIRED${NC}"
                fi
            fi
            
            echo ""
        fi
    fi
done

echo -e "${BLUE}Total: $CREW_COUNT crew(s)${NC}"
echo ""
