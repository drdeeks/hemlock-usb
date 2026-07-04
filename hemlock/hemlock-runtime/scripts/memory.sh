#!/bin/bash
# =============================================================================
# Agent Memory Protocol
# Integrates the memory architecture into the runtime
# =============================================================================

set +euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Memory Logging
# =============================================================================

memory_log() {
    local workspace="$1"
    local message="$2"
    local tag="$3"
    
    # Ensure memory directory exists
    mkdir -p "${workspace}/memory"
    
    # Get today's date
    local today="$(date +%Y-%m-%d)"
    local memory_file="${workspace}/memory/${today}.md"
    
    # Create file if it doesn't exist
    if [[ ! -f "$memory_file" ]]; then
        echo "# Memory — ${today}" > "$memory_file"
        echo "" >> "$memory_file"
    fi
    
    # Log the message
    local timestamp="$(date +%H:%M)"
    if [[ -n "$tag" ]]; then
        echo "- ${timestamp} — [${tag}] ${message}" >> "$memory_file"
    else
        echo "- ${timestamp} — ${message}" >> "$memory_file"
    fi
    
    echo -e "${GREEN}[MEMORY]${NC} Logged: ${message}"
}

# =============================================================================
# Memory Promotion
# =============================================================================

memory_promote() {
    local workspace="$1"
    local days="$2"
    
    echo -e "${BLUE}=== Memory Promotion ===${NC}"
    echo ""
    
    # Default to 2 days (today + yesterday)
    if [[ -z "$days" ]]; then
        days=2
    fi
    
    # Get list of memory files
    local memory_files=()
    for ((i=0; i<days; i++)); do
        local date="$(date -d "${i} days ago" +%Y-%m-%d)"
        local file="${workspace}/memory/${date}.md"
        if [[ -f "$file" ]]; then
            memory_files+=("$file")
        fi
    done
    
    if [[ ${#memory_files[@]} -eq 0 ]]; then
        echo "No memory files found for the last ${days} days."
        return 1
    fi
    
    # Display each file
    for file in "${memory_files[@]}"; do
        local date="$(basename "$file" | sed 's/.md$//')"
        echo -e "${YELLOW}=== ${date} ===${NC}"
        echo ""
        cat "$file"
        echo ""
    done
    
    # Instructions for promotion
    echo -e "${BLUE}=== Promotion Instructions ===${NC}"
    echo "1. Review the entries above"
    echo "2. Identify lasting insights"
    echo "3. Add them to ${workspace}/MEMORY.md"
    echo "4. Keep daily files intact (never delete)"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local workspace="${RUNTIME_ROOT}/agents"
    local action=""
    local message=""
    local tag=""
    local days=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -t|--tag) tag="$2"; shift 2 ;;
            -d|--days) days="$2"; shift 2 ;;
            log) action="log"; message="$2"; shift 2 ;;
            promote) action="promote"; days="$2"; shift 2 ;;
            *) workspace="$1"; shift ;;
        esac
    done
    
    # Validate workspace
    if [[ ! -d "$workspace" ]]; then
        echo -e "${RED}[ERROR]${NC} Workspace not found: $workspace"
        exit 1
    fi
    
    # Perform action
    case "$action" in
        log) memory_log "$workspace" "$message" "$tag" ;;
        promote) memory_promote "$workspace" "$days" ;;
        *) usage ;;
    esac
}

usage() {
    cat << EOF
${GREEN}Agent Memory Protocol${NC}

Usage: $0 [OPTIONS] [WORKSPACE]

Actions:
    log <message>        Log a memory entry
    promote [days]      Promote memories to long-term

Options:
    -h, --help          Show this help
    -t, --tag <TAG>     Tag for memory entry (LESSON, TODO, etc.)
    -d, --days <DAYS>   Number of days to promote (default: 2)

Examples:
    $0 log "Fixed auth-login.sh across all agents"
    $0 log -t LESSON "Always use -it with docker exec"
    $0 promote
    $0 promote --days 7

EOF
    exit 1
}

main "$@"