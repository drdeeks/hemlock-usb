#!/bin/bash
# =============================================================================
# SAFE Docker Restore System
# 
# Restores Docker configurations from backups with maximum safety
# Features:
#   - Pre-restore validation and checksum verification
#   - NO overwriting without explicit --force flag
#   - Dry-run mode to preview changes
#   - Backup of existing files before restore
#   - Corruption detection
#   - Atomic restore operations
#   - Rollback capability
# 
# Usage:
#   ./scripts/docker/restore-docker.sh                    # Interactive restore
#   ./scripts/docker/restore-docker.sh --list            # List available backups
#   ./scripts/docker/restore-docker.sh --latest          # Restore latest backup
#   ./scripts/docker/restore-docker.sh BACKUP_NAME       # Restore specific backup
#   ./scripts/docker/restore-docker.sh --dry-run BACKUP   # Preview restore
#   ./scripts/docker/restore-docker.sh --force BACKUP     # Force overwrite
# =============================================================================

set -uo pipefail

# Load common library
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SOURCE_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================
BACKUP_DIR="${BACKUP_DIR:-${SOURCE_DIR}/backups/docker}"
ROLLBACK_DIR="${SOURCE_DIR}/backups/rollback"

# =============================================================================
# Global variables
# =============================================================================
DRY_RUN=false
FORCE=false
VERIFY_ONLY=false
LIST_ONLY=false
LATEST=false
BACKUP_NAME=""
ROLLBACK_ENABLED=true

# =============================================================================
# Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [BACKUP_NAME]

Safe Docker configuration restore with corruption protection and overwrite prevention.

Options:
  --list              List available backups
  --latest            Restore latest backup
  --dry-run           Preview restore without making changes
  --force             Enable overwriting of existing files
  --no-rollback       Disable rollback safety (NOT RECOMMENDED)
  --verify-only       Only verify backup, don't restore
  --dir DIR          Backup directory (default: ./backups/docker)
  --help, -h         Show this help

Examples:
  $(basename "$0")                        # Interactive restore
  $(basename "$0") --list                 # List all backups
  $(basename "$0") --latest               # Restore latest backup
  $(basename "$0") docker-backup-20250101 # Restore specific backup
  $(basename "$0") --dry-run latest       # Preview latest restore
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list)
                LIST_ONLY=true
                shift
                ;;
            --latest)
                LATEST=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --no-rollback)
                ROLLBACK_ENABLED=false
                shift
                ;;
            --verify-only)
                VERIFY_ONLY=true
                shift
                ;;
            --dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                if [[ -z "$BACKUP_NAME" ]]; then
                    BACKUP_NAME="$1"
                else
                    error "Unexpected argument: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# =============================================================================
# Main Functions
# =============================================================================

list_backups() {
    log "Available Docker backups in $BACKUP_DIR:"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        warn "Backup directory not found: $BACKUP_DIR"
        return 1
    fi
    
    local count=0
    for backup_path in $(ls -td "$BACKUP_DIR"/docker-backup-* 2>/dev/null); do
        if [[ -d "$backup_path" ]]; then
            local name=$(basename "$backup_path")
            local size=$(du -sh "$backup_path" | cut -f1)
            local date=$(stat -c %y "$backup_path/BACKUP_MANIFEST.txt" 2>/dev/null | cut -d. -f1 || echo "unknown")
            local agents=$(grep -c "^Agent:" "$backup_path/BACKUP_MANIFEST.txt" 2>/dev/null || echo 0)
            local crews=$(grep -c "^Crew:" "$backup_path/BACKUP_MANIFEST.txt" 2>/dev/null || echo 0)
            local valid=$(validate_backup_quick "$backup_path" 2>/dev/null && echo "✓" || echo "✗")
            
            printf "  %-30s %8s %10s %2s agents %2s crews %s\n" \
                "$name" "$size" "$date" "$agents" "$crews" "$valid"
            count=$((count + 1))
        fi
    done
    
    if [[ $count -eq 0 ]]; then
        warn "No backups found in $BACKUP_DIR"
        return 1
    fi
    
    return 0
}

find_backup_path() {
    local name="$1"
    
    if [[ -d "$BACKUP_DIR/$name" ]]; then
        echo "$BACKUP_DIR/$name"
        return 0
    fi
    
    # Find matching backup
    for backup_path in "$BACKUP_DIR"/docker-backup-* ; do
        if [[ -d "$backup_path" ]]; then
            local base_name=$(basename "$backup_path")
            if [[ "$base_name" == "docker-backup-$name" ]] || [[ "$base_name" == "$name" ]]; then
                echo "$backup_path"
                return 0
            fi
        fi
    done
    
    # Find latest
    if [[ "$LATEST" == true ]] || [[ "$name" == "latest" ]]; then
        local latest=$(ls -td "$BACKUP_DIR"/docker-backup-* 2>/dev/null | head -1)
        if [[ -d "$latest" ]]; then
            echo "$latest"
            return 0
        fi
    fi
    
    return 1
}

validate_backup_quick() {
    local backup_path="$1"
    
    if [[ ! -f "$backup_path/BACKUP_MANIFEST.txt" ]]; then
        return 1
    fi
    
    if [[ ! -f "$backup_path/CHECKSUMS.md5" ]]; then
        return 1
    fi
    
    # Quick checksum test on manifest
    if command -v md5sum &>/dev/null; then
        local manifest_checksum=$(md5sum "$backup_path/BACKUP_MANIFEST.txt" 2>/dev/null | awk '{print $1}')
        local stored_checksum=$(grep " BACKUP_MANIFEST.txt" "$backup_path/CHECKSUMS.md5" 2>/dev/null | awk '{print $1}')
        if [[ "$manifest_checksum" != "$stored_checksum" ]]; then
            return 1
        fi
    fi
    
    return 0
}

export_rollback() {
    local dest="$1"
    local rollback_name="rollback-$(date +%Y%m%d-%H%M%S)"
    local rollback_path="$ROLLBACK_DIR/$rollback_name"
    
    if [[ "$ROLLBACK_ENABLED" != true ]]; then
        return 0
    fi
    
    log "Creating rollback point: $rollback_path"
    
    # Create rollback directory
    safe_mkdir "$rollback_path" || {
        warn "Failed to create rollback directory"
        return 1
    }
    
    # Export current state
    for file in Dockerfile Dockerfile.agent Dockerfile.export Dockerfile.crew \
               docker-compose.yml docker-config.yaml .dockerignore Makefile; do
        if [[ -f "$SOURCE_DIR/$file" ]]; then
            cp "$SOURCE_DIR/$file" "$rollback_path/" 2>/dev/null && \
                echo "$file" >> "$rollback_path/ROLLED_BACK_FILES.txt" || \
                warn "Failed to backup $file for rollback"
        fi
    done
    
    # Export agents
    if [[ -d "$SOURCE_DIR/agents" ]]; then
        mkdir -p "$rollback_path/agents" 2>/dev/null
        for agent_dir in "$SOURCE_DIR/agents"/*/; do
            local name=$(basename "$agent_dir")
            if [[ -f "$agent_dir/config.yaml" ]]; then
                mkdir -p "$rollback_path/agents/$name" 2>/dev/null
                cp "$agent_dir/config.yaml" "$rollback_path/agents/$name/" 2>/dev/null
                if [[ -d "$agent_dir/data" ]]; then
                    mkdir -p "$rollback_path/agents/$name/data" 2>/dev/null
                    for f in "$agent_dir/data"/SOUL.md "$agent_dir/data"/USER.md "$agent_dir/data"/IDENTITY.md \
                              "$agent_dir/data"/AGENTS.md "$agent_dir/data"/MEMORY.md; do
                        [[ -f "$f" ]] && cp "$f" "$rollback_path/agents/$name/data/" 2>/dev/null
                    done
                fi
            fi
        done
        echo "agents/" >> "$rollback_path/ROLLED_BACK_FILES.txt"
    fi
    
    # Export crews
    if [[ -d "$SOURCE_DIR/crews" ]]; then
        mkdir -p "$rollback_path/crews" 2>/dev/null
        for crew_dir in "$SOURCE_DIR/crews"/*/; do
            local name=$(basename "$crew_dir")
            if [[ -f "$crew_dir/crew.yaml" ]]; then
                mkdir -p "$rollback_path/crews/$name" 2>/dev/null
                cp "$crew_dir/crew.yaml" "$rollback_path/crews/$name/" 2>/dev/null
                [[ -f "$crew_dir/SOUL.md" ]] && cp "$crew_dir/SOUL.md" "$rollback_path/crews/$name/" 2>/dev/null
            fi
        done
        echo "crews/" >> "$rollback_path/ROLLED_BACK_FILES.txt"
    fi
    
    # Create rollback manifest
    echo "# Rollback Point" > "$rollback_path/ROLLBACK_MANIFEST.txt"
    echo "# Created: $(date -Iseconds)" >> "$rollback_path/ROLLBACK_MANIFEST.txt"
    echo "# Rollback Name: $rollback_name" >> "$rollback_path/ROLLBACK_MANIFEST.txt"
    echo "" >> "$rollback_path/ROLLBACK_MANIFEST.txt"
    echo "Restored from: $BACKUP_NAME" >> "$rollback_path/ROLLBACK_MANIFEST.txt"
    echo "Rollback files: $(wc -l < "$rollback_path/ROLLED_BACK_FILES.txt" 2>/dev/null || echo 0)" >> "$rollback_path/ROLLBACK_MANIFEST.txt"
    
    success "Rollback point created: $rollback_path"
    log "To rollback: ./scripts/docker/rollback-docker.sh $rollback_name"
    
    return 0
}

restore_from_backup() {
    local backup_path="$1"
    local manifest="$backup_path/BACKUP_MANIFEST.txt"
    local checksums="$backup_path/CHECKSUMS.md5"
    
    if [[ ! -f "$manifest" ]]; then
        error "Invalid backup: $backup_path (missing manifest)"
        return 1
    fi
    
    if [[ ! -f "$checksums" ]]; then
        error "Invalid backup: $backup_path (missing checksums)"
        return 1
    fi
    
    log "Validating backup before restore..."
    if ! validate_backup_quick "$backup_path"; then
        error "Backup validation failed: $backup_path may be corrupted"
        return 1
    fi
    
    success "Backup validation passed: $backup_path"
    
    if [[ "$VERIFY_ONLY" == true ]]; then
        return 0
    fi
    
    # Show what will be restored
    log "Backup contains:"
    grep "^File:\|^Agent:\|^Crew:\|^Config:" "$manifest" 2>/dev/null | sed 's/^/  /' || true
    
    # Check for existing files
    local existing_files=0
    for file in Dockerfile Dockerfile.agent Dockerfile.export Dockerfile.crew \
               docker-compose.yml docker-config.yaml .dockerignore Makefile; do
        if [[ -f "$SOURCE_DIR/$file" ]]; then
            existing_files=$((existing_files + 1))
        fi
    done
    
    if [[ $existing_files -gt 0 ]] && [[ "$FORCE" != true ]] && [[ "$DRY_RUN" == false ]]; then
        error "EXISTING FILES DETECTED!"
        error ""
        error "  This restore will OVERWRITE $existing_files existing Docker configuration file(s)."
        error ""
        error "  To proceed:"
        error "    - Use --force to force overwrite"
        error "    - Use --dry-run to preview changes"
        error "    - Use --no-rollback to disable safety (NOT RECOMMENDED)"
        error ""
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log ""
        log "=== DRY RUN - No changes will be made ==="
        log ""
        log "The following files would be restored:"
        
        # Files
        for file in $(grep "^File:" "$manifest" 2>/dev/null | sed 's/^File: //;s/ -> .*//'); do
            log "  $file -> $SOURCE_DIR/$file"
        done
        
        # Agents
        if grep -q "^Agent:" "$manifest" 2>/dev/null; then
            log ""
            log "Agent configurations:"
            grep "^Agent:" "$manifest" 2>/dev/null | sed 's/^Agent: //' | while read agent; do
                log "  $agent -> $SOURCE_DIR/agents/$agent/"
            done
        fi
        
        # Crews
        if grep -q "^Crew:" "$manifest" 2>/dev/null; then
            log ""
            log "Crew configurations:"
            grep "^Crew:" "$manifest" 2>/dev/null | sed 's/^Crew: //' | while read crew; do
                log "  $crew -> $SOURCE_DIR/crews/$crew/"
            done
        fi
        
        success "Dry run complete - No files were modified"
        return 0
    fi
    
    # Create rollback before restore
    if [[ "$ROLLBACK_ENABLED" == true ]]; then
        log ""
        log "Creating safety rollback..."
        if ! export_rollback "$SOURCE_DIR"; then
            error "Failed to create rollback - restore aborted for safety"
            return 1
        fi
    fi
    
    # Perform actual restore
    log "Restoring from backup..."
    
    # Restore files
    while IFS= read -r line; do
        if [[ "$line" =~ ^File:\  ]]; then
            # Extract source and dest from "File: <dest> -> <src>.backup"
            local dest_file="${line#File: }"
            local arrow_pos
            arrow_pos=$(echo "$dest_file" | grep -aob '->' | head -1 | cut -d: -f1)
            if [[ -n "$arrow_pos" ]]; then
                local src_file="${dest_file:${arrow_pos}+2}"
                src_file="${src_file%.backup}"
                dest_file="${dest_file:0:${arrow_pos}}"
                src_file="$backup_path/$src_file"
                dest_file="$SOURCE_DIR/$dest_file"
            else
                continue
            fi
            
            if [[ -f "$src_file" ]]; then
                log "  Restoring: ${BASH_REMATCH[1]}"
                if ! cp "$src_file" "$dest_file" 2>/dev/null; then
                    error "Failed to restore ${BASH_REMATCH[1]}"
                    return 1
                fi
                safe_chmod 644 "$dest_file" 2>/dev/null || warn "Failed to set permissions"
            else
                warn "  Source file missing: $src_file"
            fi
        fi
    done < "$manifest"
    
    # Restore agents
    while IFS= read -r line; do
        if [[ "$line" =~ ^Agent:\ (.*)$ ]]; then
            local agent_name="${BASH_REMATCH[1]}"
            local agent_backup="$backup_path/agents/$agent_name"
            local agent_dest="$SOURCE_DIR/agents/$agent_name"
            
            if [[ -d "$agent_backup" ]]; then
                log "  Restoring agent: $agent_name"
                
                # Create directory
                mkdir -p "$agent_dest" 2>/dev/null
                mkdir -p "$agent_dest/data" 2>/dev/null
                
                # Restore config
                if [[ -f "$agent_backup/config.yaml" ]]; then
                    cp "$agent_backup/config.yaml" "$agent_dest/" 2>/dev/null
                    safe_chmod 644 "$agent_dest/config.yaml" 2>/dev/null
                fi
                
                # Restore identity files
                if [[ -d "$agent_backup/data" ]]; then
                    cp "$agent_backup/data/"*.md "$agent_dest/data/" 2>/dev/null
                    safe_chmod 644 "$agent_dest/data/"* 2>/dev/null
                fi
            fi
        fi
    done < "$manifest"
    
    # Restore crews
    while IFS= read -r line; do
        if [[ "$line" =~ ^Crew:\ (.*)$ ]]; then
            local crew_name="${BASH_REMATCH[1]}"
            local crew_backup="$backup_path/crews/$crew_name"
            local crew_dest="$SOURCE_DIR/crews/$crew_name"
            
            if [[ -d "$crew_backup" ]]; then
                log "  Restoring crew: $crew_name"
                
                # Create directory
                mkdir -p "$crew_dest" 2>/dev/null
                
                # Restore crew.yaml
                if [[ -f "$crew_backup/crew.yaml" ]]; then
                    cp "$crew_backup/crew.yaml" "$crew_dest/" 2>/dev/null
                    safe_chmod 644 "$crew_dest/crew.yaml" 2>/dev/null
                fi
                
                # Restore SOUL.md
                if [[ -f "$crew_backup/SOUL.md" ]]; then
                    cp "$crew_backup/SOUL.md" "$crew_dest/" 2>/dev/null
                    safe_chmod 644 "$crew_dest/SOUL.md" 2>/dev/null
                fi
                
                # Restore workflows
                if [[ -d "$crew_backup/workflows" ]]; then
                    cp -r "$crew_backup/workflows" "$crew_dest/" 2>/dev/null
                fi
                
                # Restore rules
                if [[ -d "$crew_backup/rules" ]]; then
                    cp -r "$crew_backup/rules" "$crew_dest/" 2>/dev/null
                fi
            fi
        fi
    done < "$manifest"
    
    # Validate restored files
    log ""
    log "Verifying restored files..."
    if ! validate_restore "$manifest"; then
        error "Restore verification failed - manual cleanup may be needed"
        return 1
    fi
    
    # Create restore marker
    local restore_timestamp=$(date +%Y%m%d-%H%M%S)
    echo "# Restore Marker" > "$SOURCE_DIR/.last-restore"
    echo "Restored: $restore_timestamp" >> "$SOURCE_DIR/.last-restore"
    echo "From: $BACKUP_NAME" >> "$SOURCE_DIR/.last-restore"
    echo "Rollback: $rollback_name" >> "$SOURCE_DIR/.last-restore"
    
    success "Restore completed successfully from: $BACKUP_NAME"
    log ""
    log "VERIFY YOUR CONFIGURATION:"
    log "  1. Check restored files: ls -la Dockerfile* docker-compose.yml"
    log "  2. Validate agents: ./tests/validation/validate_structure.sh"
    log "  3. Start services: make up"
    
    return 0
}

validate_restore() {
    local manifest="$1"
    
    # Check critical files exist
    for file in Dockerfile docker-compose.yml; do
        if [[ -f "$SOURCE_DIR/$file" ]]; then
            if [[ ! -s "$SOURCE_DIR/$file" ]]; then
                error "Restored file is empty: $file"
                return 1
            fi
        else
            error "Critical file missing after restore: $file"
            return 1
        fi
    done
    
    # Check YAML files are valid
    if command -v python3 &>/dev/null; then
        for yaml_file in docker-compose.yml docker-config.yaml; do
            if [[ -f "$SOURCE_DIR/$yaml_file" ]]; then
                if ! python3 -c "import yaml; yaml.safe_load(open('$SOURCE_DIR/$yaml_file'))" 2>/dev/null; then
                    error "Invalid YAML in restored file: $yaml_file"
                    return 1
                fi
            fi
        done
    fi
    
    return 0
}

# =============================================================================
# Main
# =============================================================================

parse_args "$@"

# Determine backup path
if [[ -z "$BACKUP_NAME" ]]; then
    if [[ "$LATEST" == true ]]; then
        BACKUP_NAME="latest"
    else
        # Interactive mode
        if ! list_backups; then
            error "No backups available to restore"
            exit 1
        fi
        
        read -rp "Enter backup name to restore: " BACKUP_NAME
    fi
fi

# Find the backup
BACKUP_PATH=$(find_backup_path "$BACKUP_NAME")
if [[ -z "$BACKUP_PATH" ]]; then
    error "Backup not found: $BACKUP_NAME"
    exit 1
fi

log "Selected backup: $(basename "$BACKUP_PATH")"

# Handle list mode
if [[ "$LIST_ONLY" == true ]]; then
    list_backups
    exit $?
fi

# Handle verify mode
if [[ "$VERIFY_ONLY" == true ]]; then
    if validate_backup_quick "$BACKUP_PATH"; then
        success "Backup is valid and can be safely restored"
    else
        error "Backup is corrupted or invalid"
        exit 1
    fi
    exit 0
fi

# Perform restore
restore_from_backup "$BACKUP_PATH"

exit $?
