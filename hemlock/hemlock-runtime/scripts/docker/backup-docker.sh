#!/bin/bash
# =============================================================================
# SAFE Docker Backup System
# 
# Creates safe, validated backups of Docker configurations and data
# Features:
#   - Checksum verification
#   - No overwriting without explicit confirmation
#   - Atomic backup operations
#   - Corruption detection
#   - Timestamped backups
#   - Config validation before backup
# 
# Usage:
#   ./scripts/docker/backup-docker.sh                    # Full backup
#   ./scripts/docker/backup-docker.sh --dry-run         # Test without writing
#   ./scripts/docker/backup-docker.sh --quick            # Fast backup (no validation)
#   ./scripts/docker/backup-docker.sh --verify          # Verify existing backups
# =============================================================================

set -uo pipefail

# Load common library
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SOURCE_DIR}/lib/common.sh"

# =============================================================================
# Configuration
# =============================================================================
BACKUP_DIR="${BACKUP_DIR:-${SOURCE_DIR}/backups/docker}"
CONFIG_FILE="${SOURCE_DIR}/config/backup-config.yaml"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="docker-backup-${TIMESTAMP}"

# =============================================================================
# Global variables
# =============================================================================
DRY_RUN=false
QUICK_MODE=false
VERIFY_MODE=false
FORCE=false
VERBOSE=false

# =============================================================================
# Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Safe Docker configuration backup with corruption protection.

Options:
  --dry-run         Test backup without writing files
  --quick           Skip validation (faster)
  --verify          Verify existing backups
  --force           Overwrite existing backup without warning
  --verbose         Show detailed output
  --name NAME      Custom backup name (default: docker-backup-YYYYMMDD-HHMMSS)
  --dir DIR        Backup directory (default: ./backups/docker)
  --help, -h       Show this help

Examples:
  $(basename "$0")                          # Full safe backup
  $(basename "$0") --dry-run               # Test backup process
  $(basename "$0") --verify                # Verify all backups
  $(basename "$0") --name my-backup        # Custom backup name
  $(basename "$0") --dir /mnt/backups       # Custom backup location
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --quick)
                QUICK_MODE=true
                shift
                ;;
            --verify)
                VERIFY_MODE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --name)
                BACKUP_NAME="$2"
                shift 2
                ;;
            --dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# Main Functions
# =============================================================================

create_backup() {
    local backup_path="$BACKUP_DIR/$BACKUP_NAME"
    local temp_backup="$backup_path.tmp"
    
    # Check if backup directory exists and is writable
    validate_backup_directory "$BACKUP_DIR" || return 1
    
    # Check if backup already exists
    if [[ -d "$backup_path" ]] && [[ "$FORCE" != true ]]; then
        error "Backup '$BACKUP_NAME' already exists at $backup_path"
        error "Use --force to overwrite or --name to specify a different name"
        return 1
    fi
    
    log "Creating backup: $BACKUP_NAME"
    
    # Create temporary directory
    if [[ "$DRY_RUN" == false ]]; then
        safe_mkdir "$temp_backup" || return 1
    fi
    
    # Create backup manifest
    local manifest_file="$temp_backup/BACKUP_MANIFEST.txt"
    local checksum_file="$temp_backup/CHECKSUMS.md5"
    
    echo "# Docker Backup Manifest" > "$manifest_file"
    echo "# Created: $(date -Iseconds)" >> "$manifest_file"
    echo "# Backup Name: $BACKUP_NAME" >> "$manifest_file"
    echo "" >> "$manifest_file"
    
    # Backup Docker files
    if ! backup_docker_files "$temp_backup" "$manifest_file" "$checksum_file"; then
        warn "Failed to backup Docker files"
        if [[ "$DRY_RUN" == false ]]; then
            rm -rf "$temp_backup" 2>/dev/null || warn "Failed to clean up temp dir"
        fi
        return 1
    fi
    
    # Backup agent configurations
    if ! backup_agent_configs "$temp_backup" "$manifest_file" "$checksum_file"; then
        warn "Failed to backup agent configurations"
        if [[ "$DRY_RUN" == false ]]; then
            rm -rf "$temp_backup" 2>/dev/null || warn "Failed to clean up temp dir"
        fi
        return 1
    fi
    
    # Backup crew configurations
    if ! backup_crew_configs "$temp_backup" "$manifest_file" "$checksum_file"; then
        warn "Failed to backup crew configurations"
        if [[ "$DRY_RUN" == false ]]; then
            rm -rf "$temp_backup" 2>/dev/null || warn "Failed to clean up temp dir"
        fi
        return 1
    fi
    
    # Backup configuration files
    if ! backup_config_files "$temp_backup" "$manifest_file" "$checksum_file"; then
        warn "Failed to backup configuration files"
        if [[ "$DRY_RUN" == false ]]; then
            rm -rf "$temp_backup" 2>/dev/null || warn "Failed to clean up temp dir"
        fi
        return 1
    fi
    
    # Validate backup
    if [[ "$QUICK_MODE" == false ]]; then
        if ! validate_backup "$temp_backup" "$manifest_file" "$checksum_file"; then
            error "Backup validation failed"
            if [[ "$DRY_RUN" == false ]]; then
                rm -rf "$temp_backup" 2>/dev/null || warn "Failed to clean up temp dir"
            fi
            return 1
        fi
    fi
    
    # Atomic move to final location
    if [[ "$DRY_RUN" == false ]]; then
        log "Finalizing backup..."
        if ! mv "$temp_backup" "$backup_path" 2>/dev/null; then
            # Fallback: try cp + rm
            log "Atomic move failed, trying copy method..."
            if ! cp -r "$temp_backup"/* "$backup_path/" 2>/dev/null; then
                error "Failed to move backup to final location"
                rm -rf "$temp_backup" 2>/dev/null
                return 1
            fi
            rm -rf "$temp_backup" 2>/dev/null
        fi
        
        success "Backup created: $backup_path"
        log "Backup size: $(du -sh "$backup_path" | cut -f1)"
    else
        success "Dry run: Backup would be created at $backup_path"
    fi
    
    return 0
}

validate_backup_directory() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        log "Creating backup directory: $dir"
        if ! safe_mkdir -p "$dir" 2>/dev/null; then
            error "Failed to create backup directory: $dir"
            return 1
        fi
        # Set permissions
        safe_chmod 755 "$dir" 2>/dev/null || warn "Failed to set permissions on $dir"
    fi
    
    if [[ ! -w "$dir" ]]; then
        error "Backup directory not writable: $dir"
        return 1
    fi
    
    return 0
}

backup_docker_files() {
    local dest="$1"
    local manifest="$2"
    local checksums="$3"
    
    log "Backing up Docker files..."
    
    local files=(
        "Dockerfile"
        "Dockerfile.agent"
        "Dockerfile.export"
        "Dockerfile.crew"
        "docker-compose.yml"
        "docker-config.yaml"
        ".dockerignore"
        "Makefile"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$SOURCE_DIR/$file" ]]; then
            local target="$dest/${file}.backup"
            
            # Create parent directory
            mkdir -p "$(dirname "$target")" 2>/dev/null
            
            # Copy file
            if [[ "$DRY_RUN" == false ]]; then
                if ! cp "$SOURCE_DIR/$file" "$target" 2>/dev/null; then
                    warn "Failed to copy $file"
                    continue
                fi
                # Set permissions
                safe_chmod 644 "$target" 2>/dev/null || warn "Failed to set permissions"
                
                # Add to manifest
                echo "File: $file -> ${file}.backup" >> "$manifest"
                
                # Add to checksums
                if command -v md5sum &>/dev/null; then
                    md5sum "$target" >> "$checksums" 2>/dev/null
                elif command -v sha256sum &>/dev/null; then
                    sha256sum "$target" >> "$checksums" 2>/dev/null
                fi
            else
                echo "  [DRY RUN] Would copy: $file -> ${file}.backup" | sed 's/^/    /'
            fi
        else
            warn "File not found: $SOURCE_DIR/$file"
        fi
    done
    
    return 0
}

backup_agent_configs() {
    local dest="$1"
    local manifest="$2"
    local checksums="$3"
    
    log "Backing up agent configurations..."
    
    if [[ ! -d "$SOURCE_DIR/agents" ]]; then
        warn "No agents directory found"
        return 0
    fi
    
    local agent_count=0
    for agent_dir in "$SOURCE_DIR/agents"/*/; do
        local agent_name=$(basename "$agent_dir")
        local agent_backup="$dest/agents/$agent_name"
        
        if [[ ! -f "$agent_dir/config.yaml" ]]; then
            continue
        fi
        
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$agent_backup" 2>/dev/null
            
            # Copy config.yaml (primary config)
            if [[ -f "$agent_dir/config.yaml" ]]; then
                cp "$agent_dir/config.yaml" "$agent_backup/" 2>/dev/null
                safe_chmod 644 "$agent_backup/config.yaml" 2>/dev/null
            fi
            
            # Copy SOUL.md (identity - critical)
            if [[ -f "$agent_dir/data/SOUL.md" ]]; then
                mkdir -p "$agent_backup/data" 2>/dev/null
                cp "$agent_dir/data/SOUL.md" "$agent_backup/data/" 2>/dev/null
                safe_chmod 644 "$agent_backup/data/SOUL.md" 2>/dev/null
            fi
            
            # Copy other identity files
            for identity_file in USER.md IDENTITY.md AGENTS.md MEMORY.md; do
                if [[ -f "$agent_dir/data/$identity_file" ]]; then
                    cp "$agent_dir/data/$identity_file" "$agent_backup/data/" 2>/dev/null
                    safe_chmod 644 "$agent_backup/data/$identity_file" 2>/dev/null
                fi
            done
            
            # Add to manifest
            echo "Agent: $agent_name" >> "$manifest"
            
            # Add checksums
            if command -v md5sum &>/dev/null; then
                md5sum "$agent_backup/config.yaml" >> "$checksums" 2>/dev/null
            elif command -v sha256sum &>/dev/null; then
                sha256sum "$agent_backup/config.yaml" >> "$checksums" 2>/dev/null
            fi
            
            agent_count=$((agent_count + 1))
        else
            echo "  [DRY RUN] Would backup agent: $agent_name" | sed 's/^/    /'
            agent_count=$((agent_count + 1))
        fi
    done
    
    if [[ $agent_count -gt 0 ]]; then
        echo "  Backed up $agent_count agent(s)" >> "$manifest"
    fi
    
    return 0
}

backup_crew_configs() {
    local dest="$1"
    local manifest="$2"
    local checksums="$3"
    
    log "Backing up crew configurations..."
    
    if [[ ! -d "$SOURCE_DIR/crews" ]]; then
        warn "No crews directory found"
        return 0
    fi
    
    local crew_count=0
    for crew_dir in "$SOURCE_DIR/crews"/*/; do
        local crew_name=$(basename "$crew_dir")
        local crew_backup="$dest/crews/$crew_name"
        
        if [[ ! -f "$crew_dir/crew.yaml" ]]; then
            continue
        fi
        
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$crew_backup" 2>/dev/null
            
            # Copy crew.yaml (primary config)
            if [[ -f "$crew_dir/crew.yaml" ]]; then
                cp "$crew_dir/crew.yaml" "$crew_backup/" 2>/dev/null
                safe_chmod 644 "$crew_backup/crew.yaml" 2>/dev/null
            fi
            
            # Copy SOUL.md (identity)
            if [[ -f "$crew_dir/SOUL.md" ]]; then
                cp "$crew_dir/SOUL.md" "$crew_backup/" 2>/dev/null
                safe_chmod 644 "$crew_backup/SOUL.md" 2>/dev/null
            fi
            
            # Copy workflows if they exist
            if [[ -d "$crew_dir/workflows" ]]; then
                cp -r "$crew_dir/workflows" "$crew_backup/" 2>/dev/null
            fi
            
            # Copy rules if they exist
            if [[ -d "$crew_dir/rules" ]]; then
                cp -r "$crew_dir/rules" "$crew_backup/" 2>/dev/null
            fi
            
            # Add to manifest
            echo "Crew: $crew_name" >> "$manifest"
            
            # Add checksums
            if command -v md5sum &>/dev/null; then
                md5sum "$crew_backup/crew.yaml" >> "$checksums" 2>/dev/null
            elif command -v sha256sum &>/dev/null; then
                sha256sum "$crew_backup/crew.yaml" >> "$checksums" 2>/dev/null
            fi
            
            crew_count=$((crew_count + 1))
        else
            echo "  [DRY RUN] Would backup crew: $crew_name" | sed 's/^/    /'
            crew_count=$((crew_count + 1))
        fi
    done
    
    if [[ $crew_count -gt 0 ]]; then
        echo "  Backed up $crew_count crew(s)" >> "$manifest"
    fi
    
    return 0
}

backup_config_files() {
    local dest="$1"
    local manifest="$2"
    local checksums="$3"
    
    log "Backing up configuration files..."
    
    if [[ -d "$SOURCE_DIR/config" ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$dest/config" 2>/dev/null
            
            # Copy specific config files
            for config_file in runtime.yaml gateway.yaml backup-config.yaml; do
                if [[ -f "$SOURCE_DIR/config/$config_file" ]]; then
                    cp "$SOURCE_DIR/config/$config_file" "$dest/config/" 2>/dev/null
                    safe_chmod 600 "$dest/config/$config_file" 2>/dev/null  # More restrictive for configs
                fi
            done
            
            # Add to manifest
            echo "Config: $(ls -1 $dest/config/ 2>/dev/null | wc -l) files" >> "$manifest"
            
            # Add checksums
            if command -v md5sum &>/dev/null; then
                md5sum "$dest/config/"*.yaml 2>/dev/null >> "$checksums" || true
            elif command -v sha256sum &>/dev/null; then
                sha256sum "$dest/config/"*.yaml 2>/dev/null >> "$checksums" || true
            fi
        else
            echo "  [DRY RUN] Would backup config files" | sed 's/^/    /'
        fi
    fi
    
    return 0
}

validate_backup() {
    local backup_dir="$1"
    local manifest="$2"
    local checksums="$3"
    
    log "Validating backup..."
    
    # Check manifest exists
    if [[ ! -f "$manifest" ]]; then
        error "Backup manifest not found"
        return 1
    fi
    
    # Check checksums exist
    if [[ ! -f "$checksums" ]]; then
        error "Checksum file not found"
        return 1
    fi
    
    # Verify checksums
    if command -v md5sum &>/dev/null; then
        if ! (cd "$backup_dir" && md5sum -c "$checksums" 2>/dev/null); then
            error "Checksum verification failed - backup may be corrupted"
            return 1
        fi
    elif command -v sha256sum &>/dev/null; then
        if ! (cd "$backup_dir" && sha256sum -c "$checksums" 2>/dev/null); then
            error "Checksum verification failed - backup may be corrupted"
            return 1
        fi
    else
        warn "Neither md5sum nor sha256sum available, skipping checksum verification"
    fi
    
    success "Backup validation passed"
    return 0
}

verify_backups() {
    log "Verifying all backups in $BACKUP_DIR..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
        return 1
    fi
    
    local backup_count=0
    local valid_count=0
    local corrupted_count=0
    
    for backup_path in "$BACKUP_DIR"/docker-backup-*/; do
        if [[ -d "$backup_path" ]] && [[ -f "$backup_path/BACKUP_MANIFEST.txt" ]]; then
            backup_count=$((backup_count + 1))
            
            local manifest="$backup_path/BACKUP_MANIFEST.txt"
            local checksums="$backup_path/CHECKSUMS.md5"
            
            if [[ -f "$checksums" ]]; then
                if command -v md5sum &>/dev/null; then
                    if (cd "$backup_path" && md5sum -c "$checksums" 2>/dev/null); then
                        valid_count=$((valid_count + 1))
                        success "✓ $(basename "$backup_path") - VALID"
                    else
                        corrupted_count=$((corrupted_count + 1))
                        error "✗ $(basename "$backup_path") - CORRUPTED"
                    fi
                elif command -v sha256sum &>/dev/null; then
                    if (cd "$backup_path" && sha256sum -c "$checksums" 2>/dev/null); then
                        valid_count=$((valid_count + 1))
                        success "✓ $(basename "$backup_path") - VALID"
                    else
                        corrupted_count=$((corrupted_count + 1))
                        error "✗ $(basename "$backup_path") - CORRUPTED"
                    fi
                else
                    warn "  $(basename "$backup_path") - Cannot verify (no checksum tool)"
                    backup_count=$((backup_count - 1))
                fi
            else
                warn "  $(basename "$backup_path") - No checksum file"
                backup_count=$((backup_count - 1))
            fi
        fi
    done
    
    log "Verification Summary:"
    log "  Total backups found: $backup_count"
    log "  Valid: $valid_count"
    log "  Corrupted: $corrupted_count"
    
    if [[ $corrupted_count -gt 0 ]]; then
        error "$corrupted_count corrupted backups found!"
        return 1
    fi
    
    if [[ $valid_count -gt 0 ]]; then
        success "All $valid_count verified backups are valid"
    else
        warn "No valid backups found"
    fi
    
    return 0
}

# =============================================================================
# Main
# =============================================================================

parse_args "$@"

if [[ "$VERIFY_MODE" == true ]]; then
    verify_backups
else
    create_backup
fi

exit $?
