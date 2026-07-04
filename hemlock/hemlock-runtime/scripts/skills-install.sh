#!/bin/bash
# =============================================================================
# Skills Installation Script
# Installs skills from the global skills directory to agent-specific directory
# =============================================================================

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
    echo "Usage: $0 [options] <agent_id> [skill1] [skill2] ..."
    echo ""
    echo "Options:"
    echo "  --all             Install all available skills"
    echo "  --list           List available skills"
    echo "  --force          Overwrite existing skills"
    echo "  --quiet          Suppress output"
    echo "  --validate       Validate skills without installing"
    exit 0
}

# Parse arguments
AGENT_ID=""
SPECIFIC_SKILLS=()
INSTALL_ALL=false
LIST_SKILLS=false
FORCE=false
QUIET=false
VALIDATE_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) INSTALL_ALL=true ;;
        --list) LIST_SKILLS=true ;;
        --force) FORCE=true ;;
        --quiet) QUIET=true ;;
        --validate) VALIDATE_ONLY=true ;;
        --help|-h) usage ;;
        *)
            if [[ -z "$AGENT_ID" ]]; then
                AGENT_ID="$1"
            else
                SPECIFIC_SKILLS+=("$1")
            fi
            ;;
    esac
    shift
done

# Ensure directories exist
mkdir -p "$AGENTS_DIR" "$SKILLS_DIR"

# Validate a skill structure
validate_skill() {
    local skill_dir=$1
    local skill_name=$(basename "$skill_dir")
    
    # Required: directory exists
    [[ ! -d "$skill_dir" ]] && return 1
    
    # Required: SKILL.md exists
    [[ ! -f "$skill_dir/SKILL.md" ]] && return 1
    
    # Required: frontmatter exists
    ! head -1 "$skill_dir/SKILL.md" 2>/dev/null | grep -q '^---$' && return 1
    
    # Required: name field
    ! grep -q '^name:' "$skill_dir/SKILL.md" 2>/dev/null && return 1
    
    # Required: description field
    ! grep -q '^description:' "$skill_dir/SKILL.md" 2>/dev/null && return 1
    
    return 0
}

# List available skills
list_available() {
    log "Available skills ($SKILLS_DIR):"
    count=0
    for skill_dir in "$SKILLS_DIR"/*/; do
        if validate_skill "$skill_dir"; then
            skill_name=$(basename "$skill_dir")
            printf "  - %s\n" "$skill_name"
            ((count++))
        fi
    done
    log "Total: $count valid skills"
    exit 0
}

# Install a skill
install_skill() {
    local agent_id=$1
    local skill_name=$2
    local source="$SKILLS_DIR/$skill_name"
    local dest="$AGENTS_DIR/$agent_id/skills/$skill_name"
    
    # Validate
    if ! validate_skill "$source"; then
        [[ "$QUIET" != true ]] && log "  ERROR: Invalid skill: $skill_name"
        return 1
    fi
    
    # Skip if exists and not forcing
    if [[ -d "$dest" ]] && [[ "$FORCE" != true ]]; then
        [[ "$QUIET" != true ]] && log "  SKIP: $skill_name already installed"
        return 0
    fi
    
    # Install
    mkdir -p "$AGENTS_DIR/$agent_id/skills"
    rm -rf "$dest"
    cp -r "$source" "$dest" 2>/dev/null || return 1
    chmod -R 755 "$dest"
    
    [[ "$QUIET" != true ]] && success "  Installed: $skill_name"
    return 0
}

# Validate only
if [[ "$VALIDATE_ONLY" == true ]]; then
    for skill_name in "${SPECIFIC_SKILLS[@]}"; do
        if validate_skill "$SKILLS_DIR/$skill_name"; then
            success "  Valid: $skill_name"
        else
            error "  Invalid: $skill_name"
        fi
    done
    exit 0
fi

# List only
if [[ "$LIST_SKILLS" == true ]]; then
    list_available
fi

# Validate agent exists
if [[ -n "$AGENT_ID" ]]; then
    if [[ ! -d "$AGENTS_DIR/$AGENT_ID" ]]; then
        error "Agent '$AGENT_ID' does not exist"
    fi
else
    error "No agent ID specified"
fi

# Determine skills to install
if [[ "$INSTALL_ALL" == true ]]; then
    # Install all valid skills
    for skill_dir in "$SKILLS_DIR"/*/; do
        if validate_skill "$skill_dir"; then
            skill_name=$(basename "$skill_dir")
            SKILLS_TO_INSTALL+=("$skill_name")
        fi
    done
else
    # Install specific skills or defaults
    if [[ ${#SPECIFIC_SKILLS[@]} -gt 0 ]]; then
        SKILLS_TO_INSTALL=("${SPECIFIC_SKILLS[@]}")
    else
        # Default skills (verified to exist in the repository)
        SKILLS_TO_INSTALL=("github" "docker-management" "codebase-inspection")
    fi
fi

# Install
log "Installing skills for agent: $AGENT_ID"
log "Skills: ${SKILLS_TO_INSTALL[*]}"
installed=0
failed=0

for skill_name in "${SKILLS_TO_INSTALL[@]}"; do
    if install_skill "$AGENT_ID" "$skill_name"; then
        ((installed++))
    else
        ((failed++))
    fi
done

log "Done: $installed installed, $failed failed"
