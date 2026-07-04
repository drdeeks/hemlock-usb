#!/bin/bash
# =============================================================================
# Crew Monitor Script
# Monitor crew activity and agent status
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

# Usage
usage() {
    cat <<EOF
${GREEN}Crew Monitor Tool${NC}

Usage: $0 <crew_name> [--follow] [--logs]

Monitor crew activity and agent status.

Arguments:
  crew_name    Name of the crew to monitor

Options:
  --follow     Follow live logs (like tail -f)
  --logs       Show only crew logs
  --status     Show only agent status (default)
  --help       Show this help

Examples:
  $0 dev-team
  $0 dev-team --follow
  $0 dev-team --logs
EOF
    exit 0
}

# Parse arguments
CREW_NAME=""
FOLLOW=false
LOGS_ONLY=false
STATUS_ONLY=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --follow)
            FOLLOW=true
            STATUS_ONLY=false
            shift
            ;;
        --logs)
            LOGS_ONLY=true
            STATUS_ONLY=false
            shift
            ;;
        --status)
            STATUS_ONLY=true
            LOGS_ONLY=false
            shift
            ;;
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
CREW_FILE="$CREWS_DIR/$CREW_NAME/crew.yaml"
CREW_CHANNEL=$(grep "channel:" "$CREW_FILE" | awk '{print $2}' 2>/dev/null || echo "crew-$CREW_NAME")
CREW_STATUS=$(grep "status:" "$CREW_FILE" | awk '{print $2}' 2>/dev/null || echo "unknown")
CREW_CREATED=$(grep "created:" "$CREW_FILE" | awk '{print $2}' 2>/dev/null || echo "N/A")

# Get agents in crew
AGENTS=($(grep "^    - " "$CREW_FILE" | sed 's/^    - //' || echo ""))

# Show crew header
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Crew: $CREW_NAME                              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Channel:   ${NC}$CREW_CHANNEL"
echo -e "${GREEN}Status:    ${NC}$CREW_STATUS"
echo -e "${GREEN}Created:   ${NC}$CREW_CREATED"
echo ""

# Show agent status if requested
if [[ "$STATUS_ONLY" == true || "$LOGS_ONLY" == false ]]; then
    echo -e "${BLUE}=== Agent Status ===${NC}"
    echo ""
    
    if [[ ${#AGENTS[@]} -eq 0 ]]; then
        echo "No agents in this crew."
    else
        for agent in "${AGENTS[@]}"; do
            CONTAINER_NAME="oc-$agent"
            
            if is_service_running "$CONTAINER_NAME"; then
                STATUS=$(docker ps --filter "name=$CONTAINER_NAME" --format '{{.Status}}' | head -1)
                CREW_ENV=$(docker inspect "$CONTAINER_NAME" --format '{{.Config.Env}}' 2>/dev/null | grep -o "CREW_CHANNEL=[^ ]*" || echo "")
                CREW_CHANNEL_VALUE=$(echo "$CREW_ENV" | cut -d= -f2- || echo "none")
                
                echo -e "  ${GREEN}$agent${NC}:"
                echo "    Status:     RUNNING ($STATUS)"
                echo "    Container:  $CONTAINER_NAME"
                echo "    Crew:       $CREW_CHANNEL_VALUE"
                
                # Show CPU/Memory if available
                if command -v docker &> /dev/null; then
                    STATS=$(docker stats --no-stream "$CONTAINER_NAME" 2>/dev/null | tail -1 || echo "")
                    if [[ -n "$STATS" ]]; then
                        echo "    Stats:      $STATS"
                    fi
                fi
            else
                echo -e "  ${RED}$agent${NC}:"
                echo "    Status:     STOPPED"
                echo "    Container:  $CONTAINER_NAME (not running)"
            fi
            echo ""
        done
    fi
fi

# Show logs if requested
if [[ "$LOGS_ONLY" == true || "$FOLLOW" == true ]]; then
    CREW_LOG="$CREWS_DIR/$CREW_NAME/logs/crew.log"
    
    if [[ -f "$CREW_LOG" ]]; then
        echo -e "${BLUE}=== Crew Logs: $CREW_NAME ===${NC}"
        echo ""
        
        if [[ "$FOLLOW" == true ]]; then
            tail -f "$CREW_LOG"
        else
            # Show last 50 lines
            if [[ -s "$CREW_LOG" ]]; then
                tail -n 50 "$CREW_LOG"
            else
                echo "No logs yet. Crew activity will appear here."
            fi
        fi
    else
        echo "Crew log file not found: $CREW_LOG"
        echo "Crew may not have been started yet, or logs are disabled."
    fi
fi

exit 0
