#!/bin/bash
# =============================================================================
# Autonomy Protocol Helper
# Implements the autonomy protocol decision framework
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
# Autonomy Protocol Decision Framework
# =============================================================================

decide_autonomy_layer() {
    local task="$1"
    
    echo -e "${BLUE}=== Autonomy Protocol Decision ===${NC}"
    echo -e "Task: ${YELLOW}${task}${NC}"
    echo ""
    
    # Layer 1: Script
    echo -e "${BLUE}1. Script${NC} - Deterministic, repeatable, code"
    read -rp "  Has this been done before? [y/N] " done_before
    if [[ "$done_before" =~ ^[Yy]$ ]]; then
        echo -e "  ${GREEN}→ Use existing script/tool${NC}"
        return 1
    fi
    
    read -rp "  Is it deterministic? [y/N] " deterministic
    if [[ "$deterministic" =~ ^[Yy]$ ]]; then
        echo -e "  ${GREEN}→ Write a script (Layer 1)${NC}"
        return 1
    fi
    
    # Layer 2: Tool
    echo -e "${BLUE}2. Tool${NC} - Packaged capability"
    read -rp "  Does a packaged tool exist? [y/N] " tool_exists
    if [[ "$tool_exists" =~ ^[Yy]$ ]]; then
        echo -e "  ${GREEN}→ Use the tool (Layer 2)${NC}"
        return 2
    fi
    
    # Layer 3: Skill
    echo -e "${BLUE}3. Skill${NC} - Methodology/protocol"
    read -rp "  Is there a methodology? [y/N] " methodology
    if [[ "$methodology" =~ ^[Yy]$ ]]; then
        echo -e "  ${GREEN}→ Use a skill (Layer 3)${NC}"
        return 3
    fi
    
    # Layer 4: Subagent
    echo -e "${BLUE}4. Subagent${NC} - Fresh context"
    read -rp "  Needs LLM judgment? [y/N] " llm_judgment
    if [[ "$llm_judgment" =~ ^[Yy]$ ]]; then
        read -rp "  Self-contained description possible? [y/N] " self_contained
        if [[ "$self_contained" =~ ^[Yy]$ ]]; then
            echo -e "  ${GREEN}→ Spawn subagent (Layer 4)${NC}"
            return 4
        fi
    fi
    
    # Layer 5: Main Agent
    echo -e "${BLUE}5. Main Agent${NC} - Coordinate and decide"
    echo -e "  ${GREEN}→ Main agent handles (Layer 5)${NC}"
    return 5
}

# =============================================================================
# Main
# =============================================================================

main() {
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Task description required"
        usage
    fi
    
    local task="$*"
    local layer=$(decide_autonomy_layer "$task")
    
    echo ""
    echo -e "${GREEN}Decision:${NC} Layer $layer"
    
    case "$layer" in
        1) echo "Action: Write a script";;
        2) echo "Action: Use existing tool";;
        3) echo "Action: Load relevant skill";;
        4) echo "Action: Spawn subagent";;
        5) echo "Action: Main agent handles";;
    esac
    
    echo ""
    echo -e "${BLUE}=== Axioms ===${NC}"
    case "$layer" in
        1|2) echo "- That which can be deterministic OUGHT to be"
           echo "- State belongs in files, not in your head"
           echo "- Use a tool if one exists. Write a script if it doesn't"
           ;;
        3) echo "- Skills constrain emergence"
           echo "- Skills are bridges, not crutches"
           ;;
        4) echo "- Fresh context beats exhausted context"
           echo "- Subagents get full SOUL"
           ;;
        5) echo "- Main agent coordinates and decides"
           ;;
    esac
}

usage() {
    cat << EOF
${GREEN}Autonomy Protocol Helper${NC}

Usage: $0 <task description>

Example:
    $0 "Respond to 3 emails in my voice"
    $0 "Check API status and alert if down"

EOF
    exit 1
}

main "$@"