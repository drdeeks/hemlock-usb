#!/bin/bash
# =============================================================================
# Crew Export Script
# Exports a crew configuration for backup or transfer
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
${GREEN}Crew Export Tool${NC}

Usage: $0 <crew_name> --dest <destination_path> [options]

Export a crew configuration for backup or transfer to another system.

Arguments:
  crew_name         Name of the crew to export

Options:
  --dest <path>     Destination directory for export (required)
  --skills         Include skills from crew members
  --full           Full export including agent data (large)
  --compress       Create a tarball (.tar.gz)
  --cleanup        Gracefully remove export directory after successful export
  --help, -h       Show this help

Examples:
  $0 dev-team --dest ~/backups/crews/dev-team
  $0 dev-team --dest ~/backups/crews/dev-team --skills --compress
  $0 research-team --dest /mnt/backup/crews/research --full --compress
  $0 my-team --dest /tmp/export --cleanup
EOF
    exit 0
}

# Parse arguments
CREW_NAME=""
DEST=""
INCLUDE_SKILLS=false
FULL_EXPORT=false
COMPRESS=false
CLEANUP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest)
            DEST="$2"
            shift 2
            ;;
        --skills)
            INCLUDE_SKILLS=true
            shift
            ;;
        --full)
            FULL_EXPORT=true
            shift
            ;;
        --compress)
            COMPRESS=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$CREW_NAME" ]]; then
                CREW_NAME="$1"
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$CREW_NAME" ]]; then
    error "Crew name is required"
fi

# Default destination to EXPORTS_DIR if not specified
if [[ -z "$DEST" ]]; then
    DEST="${EXPORTS_DIR:-/data/exports}/${CREW_NAME}"
    log "No destination specified, using: $DEST"
    mkdir -p "${EXPORTS_DIR:-/data/exports}"
fi

# Validate crew exists
if [[ ! -d "$CREWS_DIR/$CREW_NAME" ]]; then
    error "Crew '$CREW_NAME' does not exist"
fi

# Check if crew.yaml exists
CREW_YAML="$CREWS_DIR/$CREW_NAME/crew.yaml"
if [[ ! -f "$CREW_YAML" ]]; then
    error "Crew '$CREW_NAME' has no crew.yaml configuration"
fi

# Create destination directory
log "Creating export directory: $DEST"
mkdir -p "$DEST/$CREW_NAME"

# Export crew configuration
log "Exporting crew configuration..."
cp -r "$CREWS_DIR/$CREW_NAME/crew.yaml" "$DEST/$CREW_NAME/"
cp -r "$CREWS_DIR/$CREW_NAME/SOUL.md" "$DEST/$CREW_NAME/" 2>/dev/null || true
cp -r "$CREWS_DIR/$CREW_NAME/crews.log" "$DEST/$CREW_NAME/" 2>/dev/null || true

# Create manifest
GROUP_LOG="$DEST/$CREW_NAME/export.log"
echo "Crew Export Manifest" > "$GROUP_LOG"
echo "==================" >> "$GROUP_LOG"
echo "Exported: $(date)" >> "$GROUP_LOG"
echo "Source: $CREWS_DIR/$CREW_NAME" >> "$GROUP_LOG"
echo "" >> "$GROUP_LOG"

# Read crew.yaml to get members
log "Reading crew members..."
AGENTS_IN_CREW=()
if command -v yq &> /dev/null; then
    AGENTS_IN_CREW=($(yq eval '.agents[]' "$CREW_YAML" 2>/dev/null || echo ""))
else
    # Parse with grep
    while IFS= read -r line; do
        if [[ "$line" =~ ^\s*-\s*([a-zA-Z0-9_-]+) ]]; then
            AGENTS_IN_CREW+=("${BASH_REMATCH[1]}")
        fi
    done < "$CREW_YAML"
fi

echo "Crew Members: ${AGENTS_IN_CREW[*]}" >> "$GROUP_LOG"
echo "" >> "$GROUP_LOG"

# Export agent configurations (not data by default)
for agent_id in "${AGENTS_IN_CREW[@]}"; do
    if [[ -d "$AGENTS_DIR/$agent_id" ]]; then
        log "Exporting configuration for agent: $agent_id"
        mkdir -p "$DEST/$CREW_NAME/agents/$agent_id/config"
        mkdir -p "$DEST/$CREW_NAME/agents/$agent_id/data"
        
        # Export config
        if [[ -f "$AGENTS_DIR/$agent_id/config.yaml" ]]; then
            cp "$AGENTS_DIR/$agent_id/config.yaml" "$DEST/$CREW_NAME/agents/$agent_id/config/"
        fi
        
        # Export SOUL.md and AGENTS.md (identity files)
        if [[ -f "$AGENTS_DIR/$agent_id/data/SOUL.md" ]]; then
            cp "$AGENTS_DIR/$agent_id/data/SOUL.md" "$DEST/$CREW_NAME/agents/$agent_id/data/"
        fi
        if [[ -f "$AGENTS_DIR/$agent_id/data/AGENTS.md" ]]; then
            cp "$AGENTS_DIR/$agent_id/data/AGENTS.md" "$DEST/$CREW_NAME/agents/$agent_id/data/"
        fi
        
        # Export MEMORY.md if it exists
        if [[ -f "$AGENTS_DIR/$agent_id/data/MEMORY.md" ]]; then
            cp "$AGENTS_DIR/$agent_id/data/MEMORY.md" "$DEST/$CREW_NAME/agents/$agent_id/data/"
        fi
        
        # Full export includes all agent data
        if [[ "$FULL_EXPORT" == true ]]; then
            log "Full export: including all data for $agent_id"
            cp -r "$AGENTS_DIR/$agent_id/skills/" "$DEST/$CREW_NAME/agents/$agent_id/" 2>/dev/null || true
            cp -r "$AGENTS_DIR/$agent_id/tools/" "$DEST/$CREW_NAME/agents/$agent_id/" 2>/dev/null || true
            cp -r "$AGENTS_DIR/$agent_id/logs/" "$DEST/$CREW_NAME/agents/$agent_id/" 2>/dev/null || true
        fi
        
        # Export skills if requested
        if [[ "$INCLUDE_SKILLS" == true ]]; then
            log "Exporting skills for agent: $agent_id"
            mkdir -p "$DEST/$CREW_NAME/agents/$agent_id/skills"
            
            # Copy from agent's skills directory
            if [[ -d "$AGENTS_DIR/$agent_id/skills" ]]; then
                cp -r "$AGENTS_DIR/$agent_id/skills/"* "$DEST/$CREW_NAME/agents/$agent_id/skills/" 2>/dev/null || true
            fi
        fi
        
        echo "  - $agent_id: config exported" >> "$GROUP_LOG"
    else
        echo "  - $agent_id: NOT FOUND (warning)" >> "$GROUP_LOG"
    fi
done

# Create metadata file
echo "" >> "$GROUP_LOG"
echo "Export Options:" >> "$GROUP_LOG"
echo "  Include Skills: $INCLUDE_SKILLS" >> "$GROUP_LOG"
echo "  Full Export: $FULL_EXPORT" >> "$GROUP_LOG"
echo "  Compressed: $COMPRESS" >> "$GROUP_LOG"

success "Crew '$CREW_NAME' exported to $DEST/$CREW_NAME"

# Compress if requested
if [[ "$COMPRESS" == true ]]; then
    log "Compressing export..."
    tar -czf "$DEST/$CREW_NAME.tar.gz" -C "$DEST" "$CREW_NAME"
    success "Compressed archive created: $DEST/$CREW_NAME.tar.gz"
    
    # Optionally remove the uncompressed version
    # rm -rf "$DEST/$CREW_NAME"
fi

success "Crew export completed successfully"

# Cleanup if requested
if [[ "$CLEANUP" == true ]]; then
    log "Cleaning up export directory..."
    rm -rf "$DEST/$CREW_NAME"
    # If compressed, keep the tarball but remove uncompressed dir
    # If not compressed, remove everything
    if [[ "$COMPRESS" != true ]]; then
        rm -f "$DEST/$CREW_NAME.tar.gz"
    fi
    success "Export directory cleaned up"
fi
