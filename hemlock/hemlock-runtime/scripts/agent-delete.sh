#!/bin/bash
# =============================================================================
# Agent Delete Script
# Deletes an agent and all its associated files from the framework
# 
# Usage:
#   ./scripts/agent-delete.sh --id <agent_id> [--force]
#   ./scripts/agent-delete.sh <agent_id> [--force]
# 
# Options:
#   --force    Skip confirmation prompt
#   --help     Show this help message
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers.sh"
AGENTS_DIR="${AGENTS_DIR:-/data/agents}"
CREWS_DIR="${CREWS_DIR:-/data/crews}"
CONFIG_DIR="${CONFIG_DIR:-/config}"
LOGS_DIR="${LOGS_DIR:-/logs}"

# Color codes
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
error()   { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
${GREEN}Agent Delete Tool${NC}

Deletes an agent and all its associated files from the Hemlock framework.

Usage:
  $0 --id <agent_id> [--force]
  $0 <agent_id> [--force]

Arguments:
  agent_id      ID of the agent to delete (required)

Options:
  --force      Skip confirmation prompt (default: false)
  --help, -h   Show this help message

Examples:
  $0 my-agent
  $0 --id my-agent
  $0 --id my-agent --force

Note: This permanently deletes the agent directory and all its contents.
EOF
    exit 0
}

# =============================================================================
# DELETE AGENT
# =============================================================================
delete_agent() {
    local agent_id="$1"
    local force="$2"
    
    # Validate agent ID
    if ! validate_agent_id "$agent_id" 2>/dev/null; then
        error "Invalid agent ID: $agent_id. Only alphanumeric, hyphens, underscores, and dots allowed."
    fi
    
    local agent_dir="$AGENTS_DIR/$agent_id"
    
    # Check if agent exists
    if [[ ! -d "$agent_dir" ]]; then
        error "Agent '$agent_id' does not exist at $agent_dir"
    fi
    
    # Check if agent is running (Docker check)
    if command -v docker &>/dev/null; then
        if docker ps -a 2>/dev/null | grep -q "$agent_id"; then
            warn "Agent '$agent_id' has running containers. Stopping first..."
            docker stop "$agent_id" 2>/dev/null || true
            docker rm "$agent_id" 2>/dev/null || true
        fi
    fi
    
    # Check if agent is in any crews
    local in_crews=false
    if [[ -d "$CREWS_DIR" ]]; then
        for crew_dir in "$CREWS_DIR"/*/; do
            if [[ -f "$crew_dir/crew.yaml" ]] || [[ -f "$crew_dir/crew.json" ]]; then
                if grep -q "$agent_id" "$crew_dir/crew.yaml" "$crew_dir/crew.json" 2>/dev/null; then
                    in_crews=true
                    warn "Agent '$agent_id' is a member of crew: $(basename "$crew_dir")"
                fi
            fi
        done
    fi
    
    # Confirmation
    if [[ "$force" != "true" ]]; then
        echo ""
        echo -e "${RED}WARNING: This will PERMANENTLY delete agent '$agent_id'${NC}"
        echo ""
        echo "  Location: $agent_dir"
        [[ "$in_crews" == true ]] && echo "  Agent is in one or more crews"
        echo ""
        read -rp "Are you sure you want to delete? [y/N]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Deletion cancelled."
            exit 0
        fi
    fi
    
    # Perform deletion
    log "Deleting agent: $agent_id"
    
    # Move agent to archive (status: archived) instead of permanent deletion
    local agent_json="$agent_dir/agent.json"
    if [[ -f "$agent_json" ]]; then
        log "Archiving agent: $agent_id (setting status to archived)"
        set_agent_status "$agent_id" "archived"
    fi
    
    # Move active registration to archive
    register_agent_archive "$agent_id"
    
    # Remove agent directory
    log "Removing agent directory: $agent_dir"
    rm -rf "$agent_dir"
    
    # Remove agent-specific logs
    if [[ -f "$LOGS_DIR/$agent_id.log" ]]; then
        rm -f "$LOGS_DIR/$agent_id.log"
        log "Removed log file: $LOGS_DIR/$agent_id.log"
    fi
    
    # Remove from runtime.log if present
    if [[ -f "$LOGS_DIR/runtime.log" ]]; then
        sed -i "/$agent_id/d" "$LOGS_DIR/runtime.log" 2>/dev/null || true
        log "Cleaned runtime.log"
    fi
    
    # Remove isolated Docker volume
    if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
        local volume_name="hemlock_agent_${agent_id}"
        if docker volume inspect "$volume_name" &>/dev/null; then
            log "Removing Docker volume: $volume_name"
            docker volume rm "$volume_name" 2>/dev/null && \
                success "Docker volume removed: $volume_name" || \
                warn "Failed to remove Docker volume: $volume_name"
        fi
    fi
    
    # Success
    success "Agent '$agent_id' deleted successfully"
    echo ""
    echo "Agent directory '$agent_dir' has been removed."
    
    # Return exit code for script use
    return 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
AGENT_ID=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --id)
            AGENT_ID="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$AGENT_ID" ]]; then
                AGENT_ID="$1"
            else
                error "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate agent ID
if [[ -z "$AGENT_ID" ]]; then
    error "Agent ID is required. Usage: $0 --id <agent_id> [--force]"
fi

# Call delete function
delete_agent "$AGENT_ID" "$FORCE"

exit 0
