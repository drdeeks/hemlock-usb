#!/bin/bash
# =============================================================================
# Crew Import Script
# Imports a crew configuration from backup or transfer
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
${GREEN}Crew Import Tool${NC}

Usage: $0 <source_path> [options]

Import a crew configuration from a backup or transfer.

Arguments:
  source_path    Path to the exported crew directory or tarball

Options:
  --name <name>      Override crew name (default: use directory name)
  --skills         Install skills from import (default: yes)
  --no-skills       Skip skills installation
  --force          Overwrite existing crew/agents
  --help, -h       Show this help

Examples:
  $0 ~/backups/crews/dev-team
  $0 ~/backups/crews/dev-team.tar.gz --name new-dev-team
  $0 /mnt/backup/crews/research --skills --force
EOF
    exit 0
}

# Parse arguments
SOURCE_PATH=""
CREW_NAME=""
INSTALL_SKILLS=true
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            CREW_NAME="$2"
            shift 2
            ;;
        --skills)
            INSTALL_SKILLS=true
            shift
            ;;
        --no-skills)
            INSTALL_SKILLS=false
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$SOURCE_PATH" ]]; then
                SOURCE_PATH="$1"
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$SOURCE_PATH" ]]; then
    error "Source path is required"
fi

# ── Resolve source path ──────────────────────────────────────────────────────
# If the raw SOURCE_PATH doesn't exist, try IMPORTS_DIR staging area
if [[ ! -e "$SOURCE_PATH" ]]; then
    _basename="$(basename "$SOURCE_PATH")"
    if [[ -e "${IMPORTS_DIR:-/data/imports}/${_basename}" ]]; then
        log "Resolved: $SOURCE_PATH → ${IMPORTS_DIR:-/data/imports}/${_basename}"
        SOURCE_PATH="${IMPORTS_DIR:-/data/imports}/${_basename}"
    else
        error "Source path does not exist: $SOURCE_PATH
  Also checked: ${IMPORTS_DIR:-/data/imports}/${_basename}

  To import from the host, stage the file first:
    ./scripts/hemlock-stage.sh crew-import <path> [crew_name]"
    fi
fi

# Determine if source is a tarball
IS_TARBALL=false
TEMP_DIR=""
EXTRACTED_PATH=""

if [[ "$SOURCE_PATH" == *.tar.gz ]] || [[ "$SOURCE_PATH" == *.tgz ]]; then
    IS_TARBALL=true
    TEMP_DIR=$(mktemp -d)
    EXTRACTED_PATH="$TEMP_DIR/extracted"
    
    log "Extracting tarball: $SOURCE_PATH"
    mkdir -p "$EXTRACTED_PATH"
    tar -xzf "$SOURCE_PATH" -C "$EXTRACTED_PATH"
    SOURCE_PATH="$EXTRACTED_PATH"
fi

# Find crew directory in source
CREW_DIRS=($SOURCE_PATH/*/)
if [[ ${#CREW_DIRS[@]} -eq 0 ]]; then
    # Source might be the crew directory itself
    if [[ -f "$SOURCE_PATH/crew.yaml" ]]; then
        CREW_DIRS=("$SOURCE_PATH")
    else
        error "No valid crew found in: $SOURCE_PATH"
    fi
fi

IMPORTED_CREW_DIR="${CREW_DIRS[0]}"
IMPORTED_CREW_NAME=$(basename "$IMPORTED_CREW_DIR")

# Use provided name or extracted name
FINAL_CREW_NAME="${CREW_NAME:-$IMPORTED_CREW_NAME}"

# Validate crew name
if ! validate_agent_id "$FINAL_CREW_NAME"; then
    error "Invalid crew name: $FINAL_CREW_NAME"
fi

# Check if crew already exists
if [[ -d "$CREWS_DIR/$FINAL_CREW_NAME" ]] && [[ "$FORCE" != true ]]; then
    error "Crew '$FINAL_CREW_NAME' already exists. Use --force to overwrite."
fi

# Create crew directory
log "Creating crew directory: $CREWS_DIR/$FINAL_CREW_NAME"
if [[ "$FORCE" == true ]]; then
    rm -rf "$CREWS_DIR/$FINAL_CREW_NAME"
fi
mkdir -p "$CREWS_DIR/$FINAL_CREW_NAME"

# Import crew configuration
log "Importing crew configuration..."
cp "$IMPORTED_CREW_DIR/crew.yaml" "$CREWS_DIR/$FINAL_CREW_NAME/"
cp "$IMPORTED_CREW_DIR/SOUL.md" "$CREWS_DIR/$FINAL_CREW_NAME/" 2>/dev/null || true

# Read manifest if it exists
if [[ -f "$IMPORTED_CREW_DIR/export.log" ]]; then
    log "Reading export manifest..."
    cat "$IMPORTED_CREW_DIR/export.log"
fi

# Get agents from crew.yaml
log "Reading crew members..."
AGENTS_IN_SOURCE=()

# Read the agents directory from the import
AGENTS_SOURCE_DIR="$IMPORTED_CREW_DIR/agents"
if [[ -d "$AGENTS_SOURCE_DIR" ]]; then
    for agent_dir in "$AGENTS_SOURCE_DIR"/*/; do
        AGENTS_IN_SOURCE+=("(basename "$agent_dir")")
    done
else
    # Parse crew.yaml for agents
    if command -v yq &> /dev/null; then
        AGENTS_IN_SOURCE=($(yq eval '.agents[]' "$CREWS_DIR/$FINAL_CREW_NAME/crew.yaml" 2>/dev/null || echo ""))
    else
        while IFS= read -r line; do
            if [[ "$line" =~ ^\\s*-\\s*([a-zA-Z0-9_-]+) ]]; then
                AGENTS_IN_SOURCE+=("${BASH_REMATCH[1]}")
            fi
        done < "$CREWS_DIR/$FINAL_CREW_NAME/crew.yaml"
    fi
fi

log "Found ${#AGENTS_IN_SOURCE[@]} agents in export: ${AGENTS_IN_SOURCE[*]}"

# Import and install skills for each agent
for agent_id in "${AGENTS_IN_SOURCE[@]}"; do
    AGENT_SOURCE="$AGENTS_SOURCE_DIR/$agent_id"
    
    if [[ -d "$AGENT_SOURCE" ]]; then
        log "Importing agent: $agent_id"
        
        # Create agent directory if it doesn't exist
        if [[ ! -d "$AGENTS_DIR/$agent_id" ]]; then
            log "Creating agent directory: $AGENTS_DIR/$agent_id"
            create_agent_structure "$agent_id"
        fi
        
        # Import configuration
        if [[ -f "$AGENT_SOURCE/config/config.yaml" ]]; then
            cp "$AGENT_SOURCE/config/config.yaml" "$AGENTS_DIR/$agent_id/config.yaml"
            log "  Imported config.yaml"
        fi
        
        # Import identity files
        if [[ -f "$AGENT_SOURCE/data/SOUL.md" ]]; then
            cp "$AGENT_SOURCE/data/SOUL.md" "$AGENTS_DIR/$agent_id/data/SOUL.md"
            log "  Imported SOUL.md"
        fi
        
        if [[ -f "$AGENT_SOURCE/data/AGENTS.md" ]]; then
            cp "$AGENT_SOURCE/data/AGENTS.md" "$AGENTS_DIR/$agent_id/data/AGENTS.md"
            log "  Imported AGENTS.md"
        fi
        
        if [[ -f "$AGENT_SOURCE/data/MEMORY.md" ]]; then
            cp "$AGENT_SOURCE/data/MEMORY.md" "$AGENTS_DIR/$agent_id/data/MEMORY.md"
            log "  Imported MEMORY.md"
        fi
        
        # Install skills if requested and source has them
        if [[ "$INSTALL_SKILLS" == true ]] && [[ -d "$AGENT_SOURCE/skills" ]]; then
            log "  Installing skills from export..."
            install_skills_for_agent "$agent_id" "$AGENT_SOURCE/skills"
        fi
        
        success "Agent $agent_id imported"
    else
        log "  Agent $agent_id: source directory not found (will be created on first start)"
    fi
done

# Clean up temp directory if we extracted a tarball
if [[ "$IS_TARBALL" == true ]] && [[ -n "$TEMP_DIR" ]]; then
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
fi

# Provision the shared crew docker volume (CL-012). Idempotent — import keeps an
# existing volume if it was created earlier by crew-create or a prior import.
if command -v docker >/dev/null 2>&1; then
    CREW_VOLUME="hemlock_crew_${FINAL_CREW_NAME}"
    if ! docker volume inspect "$CREW_VOLUME" >/dev/null 2>&1; then
        if docker volume create \
                --label "crew=${FINAL_CREW_NAME}" \
                --label "framework=hemlock" \
                --label "origin=imported" \
                "$CREW_VOLUME" >/dev/null 2>&1; then
            success "Docker volume created: $CREW_VOLUME"
        else
            log "  (docker volume create failed for $CREW_VOLUME — continuing)"
        fi
    else
        log "  Docker volume already exists: $CREW_VOLUME"
    fi
fi

success "Crew '$FINAL_CREW_NAME' imported successfully"
log ""
log "Next steps:"
log "  1. Review crew configuration: $CREWS_DIR/$FINAL_CREW_NAME/crew.yaml"
log "  2. Start the crew: ./scripts/crew-start.sh $FINAL_CREW_NAME"
log "  3. Or add agents individually: ./scripts/crew-join.sh $FINAL_CREW_NAME <agent_id>"

# Helper function to install skills for an agent
install_skills_for_agent() {
    local agent_id=$1
    local source_skills_dir=$2
    
    # Create agent skills directory
    mkdir -p "$AGENTS_DIR/$agent_id/skills"
    
    # Copy each skill from source
    if [[ -d "$source_skills_dir" ]]; then
        for skill_dir in "$source_skills_dir"/*/; do
            if [[ -d "$skill_dir" ]]; then
                skill_name=$(basename "$skill_dir")
                log "    Installing skill: $skill_name"
                cp -r "$skill_dir" "$AGENTS_DIR/$agent_id/skills/"
                
                # Validate the skill
                validate_skill "$AGENTS_DIR/$agent_id/skills/$skill_name"
            fi
        done
    fi
}

# Helper function to validate a skill meets OpenClaw & Hermes requirements
validate_skill() {
    local skill_dir=$1
    
    # Check if directory exists
    if [[ ! -d "$skill_dir" ]]; then
        log "      WARNING: Skill directory not found: $skill_dir"
        return 1
    fi
    
    # Check for SKILL.md
    if [[ ! -f "$skill_dir/SKILL.md" ]]; then
        log "      WARNING: Missing SKILL.md in $skill_name"
        return 1
    fi
    
    # Check YAML frontmatter exists
    if ! head -1 "$skill_dir/SKILL.md" | grep -q '^---$'; then
        log "      WARNING: Missing YAML frontmatter in $skill_dir/SKILL.md"
        return 1
    fi
    
    # Check for required fields in YAML
    if ! grep -q '^name:' "$skill_dir/SKILL.md"; then
        log "      WARNING: Missing 'name' field in $skill_dir/SKILL.md"
        return 1
    fi
    
    if ! grep -q '^description:' "$skill_dir/SKILL.md"; then
        log "      WARNING: Missing 'description' field in $skill_dir/SKILL.md"
        return 1
    fi
    
    if ! grep -q '^version:' "$skill_dir/SKILL.md"; then
        log "      WARNING: Missing 'version' field in $skill_dir/SKILL.md"
        return 1
    fi
    
    # Check for Hermes metadata (optional but recommended)
    if grep -q 'hermes:' "$skill_dir/SKILL.md"; then
        log "      Hermès metadata: FOUND"
    else
        log "      Hermès metadata: NOT FOUND (optional)"
    fi
    
    # Check for OpenClaw compatibility metadata
    if grep -q 'openclaw:' "$skill_dir/SKILL.md"; then
        log "      OpenClaw metadata: FOUND"
    else
        log "      OpenClaw metadata: NOT FOUND (optional)"
    fi
    
    log "      Skill $skill_name: VALID"
    return 0
}
