#!/bin/bash
# =============================================================================
# Self-Update Mechanism for Enterprise Framework
# Automatically updates the framework to the latest version
# Learnings: Configurable URLs, signature verification, rollback capability
# =============================================================================

set -uo pipefail

# Find RUNTIME_ROOT by searching for lib/common.sh (current Hemlock runtime
# anchor; legacy snapshots used runtime.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$SCRIPT_DIR"
while [[ "$RUNTIME_ROOT" != "/" && ! -f "$RUNTIME_ROOT/lib/common.sh" ]]; do
    RUNTIME_ROOT="$(dirname "$RUNTIME_ROOT")"
done
if [[ ! -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    RUNTIME_ROOT="$SCRIPT_DIR"
fi

# Load common utilities if available
if [[ -f "$RUNTIME_ROOT/lib/common.sh" ]]; then
    source "$RUNTIME_ROOT/lib/common.sh"
fi

# =============================================================================
# CONFIGURATION - Security Enhanced
# =============================================================================

# Auto-update URL — configurable via environment variable. Empty by default:
# auto-update is OFF unless explicitly enabled (avoids silent network calls
# to a placeholder URL that may not exist for this fork). Set via
# `AUTO_UPDATE_URL=https://… ./.auto-update.sh` or via menu wizard.
AUTO_UPDATE_URL="${AUTO_UPDATE_URL:-}"

# SHA256 signature URL — also configurable. Without it, only basic checks run.
AUTO_UPDATE_SIG_URL="${AUTO_UPDATE_SIG_URL:-}"

# Update interval in seconds (default: 24 hours = 86400)
AUTO_UPDATE_INTERVAL="${AUTO_UPDATE_INTERVAL:-86400}"

# Maximum number of backup versions to keep for rollback
MAX_BACKUP_VERSIONS="${MAX_BACKUP_VERSIONS:-5}"

# Last update tracking file
LAST_UPDATE_FILE="$RUNTIME_ROOT/.last-auto-update"

# Update lock file to prevent concurrent updates
UPDATE_LOCK="$RUNTIME_ROOT/.update-in-progress"

# Temporary file for downloads
TEMP_UPDATE_FILE="$RUNTIME_ROOT/.auto-update-temp.sh"

# Temporary signature file
TEMP_SIG_FILE="$RUNTIME_ROOT/.auto-update-temp.sh.sha256"

# Rollback directory
ROLLBACK_DIR="$RUNTIME_ROOT/.update-rollback"

# Track cleanup hooks
CLEANUP_HOOKS=()

# =============================================================================
# SECURITY UTILITIES
# =============================================================================

# Validate and sanitize a URL
validate_url() {
    local url="$1"
    
    # Check if URL uses https (security requirement)
    if [[ ! "$url" =~ ^https:// ]]; then
        error "URL must use HTTPS: $url"
        return 1
    fi
    
    # Basic URL format validation
    if [[ ! "$url" =~ ^https://[a-zA-Z0-9.-]+(/[a-zA-Z0-9._-]*)*$ ]]; then
        error "Invalid URL format: $url"
        return 1
    fi
    
    log "URL validated: $url"
    return 0
}

# Validate and sanitize file paths
sanitize_path() {
    local path="$1"
    
    # Remove any path traversal attempts
    path=$(echo "$path" | sed 's|/\.\.| |g; s|\.\./||g')
    
    # Ensure path is within RUNTIME_ROOT for relative safety
    if [[ "$path" != /* ]]; then
        path="$RUNTIME_ROOT/$path"
    fi
    
    # Normalize path
    path=$(realpath -m "$path" 2>/dev/null || echo "$path")
    
    echo "$path"
}

# Register cleanup hook
register_cleanup() {
    local hook="$1"
    CLEANUP_HOOKS+=("$hook")
}

# Run cleanup hooks
run_cleanup() {
    local exit_code=$?
    
    # Run cleanup hooks in reverse order
    for ((i=${#CLEANUP_HOOKS[@]}-1; i>=0; i--)); do
        debug "Running cleanup hook: ${CLEANUP_HOOKS[$i]}"
        eval "${CLEANUP_HOOKS[$i]}" 2>/dev/null || warn "Cleanup hook failed: ${CLEANUP_HOOKS[$i]}"
    done
    
    exit $exit_code
}

# Register cleanup for temp files
register_cleanup "rm -f '$TEMP_UPDATE_FILE'"
register_cleanup "rm -f '$TEMP_SIG_FILE'"
register_cleanup "release_update_lock"

# Trap exit for cleanup
trap run_cleanup EXIT

# =============================================================================
# ROLLBACK MECHANISMS
# =============================================================================

# Initialize rollback directory
init_rollback() {
    mkdir -p "$ROLLBACK_DIR"
    debug "Rollback directory initialized: $ROLLBACK_DIR"
}

# Rotate backups - keep only MAX_BACKUP_VERSIONS
rotate_backups() {
    local backup_files=()
    
    # Find all backup files
    while IFS= read -r file; do
        backup_files+=("$file")
    done < <(find "$ROLLBACK_DIR" -name ".auto-update.sh.*" -type f 2>/dev/null | sort)
    
    # Remove oldest backups if we exceed max
    local num_backups=${#backup_files[@]}
    if [[ $num_backups -gt $MAX_BACKUP_VERSIONS ]]; then
        local to_remove=$((num_backups - MAX_BACKUP_VERSIONS))
        for ((i=0; i<to_remove; i++)); do
            local old_file="${backup_files[$i]}"
            debug "Removing old backup: $old_file"
            rm -f "$old_file"
        done
    fi
}

# Save current version for rollback
save_for_rollback() {
    local version="$1"
    local timestamp="$2"
    local backup_file="$ROLLBACK_DIR/.auto-update.sh.$timestamp"
    
    init_rollback
    rotate_backups
    
    # Create version info file
    local version_info="$ROLLBACK_DIR/.auto-update.sh.$timestamp.version"
    echo "VERSION=$version" > "$version_info"
    echo "TIMESTAMP=$timestamp" >> "$version_info"
    echo "SOURCE=$AUTO_UPDATE_URL" >> "$version_info"
    
    # Copy current script
    cp "$SCRIPT_DIR/.auto-update.sh" "$backup_file" 2>/dev/null
    chmod 600 "$backup_file" "$version_info" 2>/dev/null
    
    debug "Saved rollback version: $backup_file"
    return $?
}

# List available rollback versions
list_rollbacks() {
    log "Available rollback versions:"
    
    local versions=()
    while IFS= read -r version_file; do
        if [[ -f "$version_file" ]]; then
            local timestamp=$(grep "^TIMESTAMP=" "$version_file" | cut -d= -f2)
            local version=$(grep "^VERSION=" "$version_file" | cut -d= -f2)
            local script_file="${version_file%.version}"
            
            if [[ -f "$script_file" ]]; then
                local file_time=$(stat -c %y "$script_file" 2>/dev/null || date)
                versions+=("$timestamp|$version|$file_time")
            fi
        fi
    done < <(find "$ROLLBACK_DIR" -name ".auto-update.sh.*.version" 2>/dev/null | sort -r)
    
    if [[ ${#versions[@]} -eq 0 ]]; then
        log "No rollback versions available"
        return 1
    fi
    
    for v in "${versions[@]}"; do
        local timestamp=$(echo "$v" | cut -d'|' -f1)
        local version=$(echo "$v" | cut -d'|' -f2)
        local file_time=$(echo "$v" | cut -d'|' -f3)
        log "  Version: $version | Timestamp: $timestamp | File: $file_time"
    done
    
    return 0
}

# Rollback to a specific version
rollback_to() {
    local target="$1"
    
    # If target is empty, list available versions
    if [[ -z "$target" ]]; then
        list_rollbacks
        return 1
    fi
    
    local backup_file="$ROLLBACK_DIR/.auto-update.sh.$target"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Rollback version not found: $target"
        list_rollbacks
        return 1
    fi
    
    log "Rolling back to: $backup_file"
    
    # Validate the rollback file
    if ! verify_updater_file "$backup_file"; then
        error "Rollback file verification failed: $backup_file"
        return 1
    fi
    
    # Perform rollback (atomic operation)
    local temp_rollback="$SCRIPT_DIR/.auto-update.sh.rollback.tmp"
    cp "$backup_file" "$temp_rollback" 2>/dev/null || return 1
    
    # Atomic move
    if mv "$temp_rollback" "$SCRIPT_DIR/.auto-update.sh" 2>/dev/null; then
        chmod 755 "$SCRIPT_DIR/.auto-update.sh"
        log "Rollback successful to: $target"
        return 0
    else
        error "Rollback failed: could not move file"
        rm -f "$temp_rollback" 2>/dev/null
        return 1
    fi
}

# =============================================================================
# UPDATE FUNCTIONS
# =============================================================================

# Check if an update is needed
check_update_needed() {
    log "Checking if update is needed..."
    
    # Check if last update file exists
    if [[ ! -f "$LAST_UPDATE_FILE" ]]; then
        log "No previous update recorded, update needed"
        return 0
    fi
    
    # Read last update timestamp
    local last_update
    last_update=$(cat "$LAST_UPDATE_FILE" 2>/dev/null || echo "0")
    
    # Get current timestamp
    local now
    now=$(date +%s)
    
    # Calculate elapsed time
    local elapsed=$((now - last_update))
    
    log "Last update: $(date -d "@$last_update" 2>/dev/null || echo "unknown")"
    log "Time elapsed: ${elapsed}s (interval: ${AUTO_UPDATE_INTERVAL}s)"
    
    # Check if interval has passed
    if [[ $elapsed -ge $AUTO_UPDATE_INTERVAL ]]; then
        log "Update interval passed, update needed"
        return 0
    else
        log "Update not needed yet (${elapsed}s < ${AUTO_UPDATE_INTERVAL}s)"
        return 1
    fi
}

# Check if update is already in progress
check_update_lock() {
    if [[ -f "$UPDATE_LOCK" ]]; then
        local lock_pid
        lock_pid=$(cat "$UPDATE_LOCK" 2>/dev/null || echo "")
        
        # Check if the process is still running
        if [[ -n "$lock_pid" && -d "/proc/$lock_pid" ]]; then
            warn "Update already in progress (PID: $lock_pid)"
            return 1
        else
            # Stale lock file, remove it after validation
            warn "Stale lock file found (PID: $lock_pid), removing..."
            # Verify it's actually stale (not running for more than 1 hour)
            local lock_age=0
            if [[ -f "$UPDATE_LOCK" ]]; then
                local lock_mtime=$(stat -c %Y "$UPDATE_LOCK" 2>/dev/null || echo "0")
                local now=$(date +%s)
                lock_age=$((now - lock_mtime))
            fi
            
            # Remove if older than 1 hour (stale)
            if [[ $lock_age -gt 3600 ]]; then
                rm -f "$UPDATE_LOCK"
                log "Removed stale lock file (age: ${lock_age}s)"
            else
                # Recent lock file but process not found - could be race condition
                warn "Lock file is recent (${lock_age}s) but process not found - waiting..."
                sleep 5
                # Check again
                if [[ ! -d "/proc/$lock_pid" ]]; then
                    rm -f "$UPDATE_LOCK"
                    log "Removed stale lock file after retry"
                else
                    error "Lock file exists and process is running"
                    return 1
                fi
            fi
        fi
    fi
    
    # Create new lock file with current PID and timestamp
    echo $$ > "$UPDATE_LOCK"
    echo "START_TIME=$(date +%s)" >> "$UPDATE_LOCK"
    return 0
}

# Release update lock
release_update_lock() {
    if [[ -f "$UPDATE_LOCK" ]]; then
        # Verify the lock belongs to us
        local lock_pid
        lock_pid=$(head -1 "$UPDATE_LOCK" 2>/dev/null || echo "")
        
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$UPDATE_LOCK"
            debug "Update lock released"
        else
            warn "Lock file belongs to PID $lock_pid, not releasing"
        fi
    fi
}

# Download the latest updater script
download_updater() {
    # Validate URL first
    if ! validate_url "$AUTO_UPDATE_URL"; then
        error "Invalid update URL: $AUTO_UPDATE_URL"
        return 1
    fi
    
    log "Downloading latest updater from $AUTO_UPDATE_URL..."
    
    # Try curl first with progress
    if command -v curl &>/dev/null; then
        if curl -sSf -L --progress-bar -o "$TEMP_UPDATE_FILE" "$AUTO_UPDATE_URL" 2>/dev/null; then
            log "Successfully downloaded with curl"
            # Also download signature if available
            if [[ -n "$AUTO_UPDATE_SIG_URL" ]]; then
                curl -sSf -L -o "$TEMP_SIG_FILE" "$AUTO_UPDATE_SIG_URL" 2>/dev/null && \
                    log "Successfully downloaded signature" || \
                    warn "Could not download signature file"
            fi
            return 0
        fi
    fi
    
    # Fallback to wget
    if command -v wget &>/dev/null; then
        if wget -q -O "$TEMP_UPDATE_FILE" "$AUTO_UPDATE_URL" 2>/dev/null; then
            log "Successfully downloaded with wget"
            if [[ -n "$AUTO_UPDATE_SIG_URL" ]]; then
                wget -q -O "$TEMP_SIG_FILE" "$AUTO_UPDATE_SIG_URL" 2>/dev/null && \
                    log "Successfully downloaded signature" || \
                    warn "Could not download signature file"
            fi
            return 0
        fi
    fi
    
    error "Failed to download updater (no curl or wget available)"
    return 1
}

# Download signature file separately (if signature verification is enabled)
download_signature() {
    if [[ -z "$AUTO_UPDATE_SIG_URL" ]]; then
        warn "No signature URL configured, skipping signature download"
        return 1
    fi
    
    log "Downloading signature from $AUTO_UPDATE_SIG_URL..."
    
    if command -v curl &>/dev/null; then
        if curl -sSf -L -o "$TEMP_SIG_FILE" "$AUTO_UPDATE_SIG_URL" 2>/dev/null; then
            log "Successfully downloaded signature"
            return 0
        fi
    fi
    
    if command -v wget &>/dev/null; then
        if wget -q -O "$TEMP_SIG_FILE" "$AUTO_UPDATE_SIG_URL" 2>/dev/null; then
            log "Successfully downloaded signature"
            return 0
        fi
    fi
    
    warn "Failed to download signature file"
    return 1
}

# Verify the downloaded updater with SHA256 signature
verify_updater() {
    local temp_file="${1:-$TEMP_UPDATE_FILE}"
    local sig_file="${2:-$TEMP_SIG_FILE}"
    
    # Check if file exists
    if [[ ! -f "$temp_file" ]]; then
        error "Downloaded updater file not found: $temp_file"
        return 1
    fi
    
    # Check if file is not empty
    if [[ ! -s "$temp_file" ]]; then
        error "Downloaded updater file is empty: $temp_file"
        return 1
    fi
    
    # Check if file has proper shebang
    local first_line
    first_line=$(head -1 "$temp_file")
    if [[ "$first_line" != "#!/bin/bash" ]]; then
        error "Downloaded updater has invalid shebang: $first_line"
        return 1
    fi
    
    # Verify with SHA256 signature if available
    if [[ -f "$sig_file" && -s "$sig_file" ]]; then
        log "Verifying signature..."
        
        # Get expected hash from signature file
        local expected_hash
        expected_hash=$(cat "$sig_file" 2>/dev/null | head -1 | xargs)
        
        if [[ -n "$expected_hash" ]]; then
            # Calculate actual hash
            local actual_hash
            actual_hash=$(sha256sum "$temp_file" 2>/dev/null | awk '{print $1}' || \
                         shasum -a 256 "$temp_file" 2>/dev/null | awk '{print $1}')
            
            if [[ "$actual_hash" == "$expected_hash" ]]; then
                log "Signature verification passed"
                return 0
            else
                error "Signature verification FAILED!"
                error "Expected: $expected_hash"
                error "Actual:   $actual_hash"
                # Security: Do NOT proceed with installation
                rm -f "$temp_file" "$sig_file"
                return 1
            fi
        else
            warn "Signature file is empty or invalid"
        fi
    else
        warn "No signature file available, using fallback verification only"
        # Fallback: basic checks passed above
        log "Updater verification passed (basic checks only)"
    fi
    
    return 0
}

# Verify a file (for rollback validation)
verify_updater_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        return 1
    fi
    
    if [[ ! -s "$file" ]]; then
        error "File is empty: $file"
        return 1
    fi
    
    local first_line
    first_line=$(head -1 "$file")
    if [[ "$first_line" != "#!/bin/bash" ]]; then
        error "Invalid shebang in: $file"
        return 1
    fi
    
    log "File verification passed: $file"
    return 0
}

# Run the updater
run_updater() {
    local temp_file="$TEMP_UPDATE_FILE"
    
    # Security: Validate the temporary file path is safe
    local safe_temp_file
    safe_temp_file=$(sanitize_path "$temp_file")
    
    if [[ ! -f "$safe_temp_file" ]]; then
        error "Safe temp file path validation failed"
        return 1
    fi
    
    log "Running updater script..."
    
    # Run with bash and pass RUNTIME_ROOT
    # Use exec to replace current process if possible
    if bash "$safe_temp_file" --runtime-root="$RUNTIME_ROOT" 2>&1; then
        log "Updater executed successfully"
        return 0
    else
        error "Updater execution failed"
        return 1
    fi
}

# Record update time
record_update() {
    date +%s > "$LAST_UPDATE_FILE"
    log "Update recorded at $(date)"
}

# Generate signature for current file (for distribution)
generate_signature() {
    local file="${1:-$SCRIPT_DIR/.auto-update.sh}"
    local output="${2:-$file.sha256}"
    
    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        return 1
    fi
    
    local hash
    hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}' || \
           shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
    
    if [[ -n "$hash" ]]; then
        echo "$hash" > "$output"
        log "Signature generated: $output"
        return 0
    else
        error "Could not generate signature"
        return 1
    fi
}

# =============================================================================
# SELF-HEALING CAPABILITIES
# =============================================================================

# If update fails, attempt self-healing
self_heal() {
    warn "Update failed, attempting self-healing..."
    
    # Try to restore from backup if available
    local backup_file="$RUNTIME_ROOT/.auto-update.sh.backup"
    if [[ -f "$backup_file" ]]; then
        log "Attempting to restore from backup..."
        if verify_updater_file "$backup_file"; then
            cp "$backup_file" "$SCRIPT_DIR/.auto-update.sh" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                chmod 755 "$SCRIPT_DIR/.auto-update.sh"
                log "Successfully restored from backup"
                return 0
            fi
        fi
    fi
    
    # Try rollback directory
    local rollback_files=()
    while IFS= read -r file; do
        rollback_files+=("$file")
    done < <(find "$ROLLBACK_DIR" -name ".auto-update.sh.*" -type f 2>/dev/null | sort -r)
    
    for candidate in "${rollback_files[@]}"; do
        if verify_updater_file "$candidate"; then
            log "Attempting rollback to: $candidate"
            cp "$candidate" "$SCRIPT_DIR/.auto-update.sh" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                chmod 755 "$SCRIPT_DIR/.auto-update.sh"
                log "Successfully restored from rollback"
                return 0
            fi
        fi
    done
    
    error "Self-healing failed, manual intervention required"
    return 1
}

# =============================================================================
# MAIN UPDATE PROCESS
# =============================================================================

auto_update() {
    log "=========================================="
    log "Auto-Update Process Started"
    log "=========================================="

    # Guard: refuse to run if no update source is configured.
    if [[ -z "$AUTO_UPDATE_URL" ]]; then
        warn "AUTO_UPDATE_URL is empty — auto-update is disabled."
        warn "Set AUTO_UPDATE_URL=https://… and AUTO_UPDATE_SIG_URL=https://…"
        warn "to enable, or use 'Hemlock Manager → Update' in menu.sh."
        return 1
    fi
    
    # Register cleanup for this session
    register_cleanup "release_update_lock"
    
    # Check if update lock can be acquired
    if ! check_update_lock; then
        warn "Skipping update due to lock"
        return 1
    fi
    
    # Check if update is needed (automatic check mode)
    if [[ "${1:-}" != "--force" ]]; then
        if ! check_update_needed; then
            log "No update needed at this time"
            release_update_lock
            return 0
        fi
    fi
    
    # Backup current script for rollback
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local current_version="$(head -2 "$SCRIPT_DIR/.auto-update.sh" 2>/dev/null | tail -1 | tr -d '# ' || echo "unknown")"
    
    init_rollback
    save_for_rollback "$current_version" "$timestamp" 2>/dev/null || \
        warn "Failed to save current version for rollback"
    
    # Download the latest updater
    if ! download_updater; then
        warn "Failed to download updater"
        cleanup
        if ! self_heal; then
            return 1
        fi
        return 1
    fi
    
    # Download signature if not already downloaded
    if [[ ! -f "$TEMP_SIG_FILE" ]]; then
        download_signature 2>/dev/null || \
            warn "Could not download signature, using basic verification"
    fi
    
    # Verify the updater
    if ! verify_updater "$TEMP_UPDATE_FILE" "$TEMP_SIG_FILE"; then
        warn "Updater verification failed"
        rm -f "$TEMP_UPDATE_FILE" "$TEMP_SIG_FILE"
        release_update_lock
        return 1
    fi
    
    # Run the updater
    if ! run_updater; then
        warn "Updater execution failed"
        rm -f "$TEMP_UPDATE_FILE" "$TEMP_SIG_FILE"
        release_update_lock
        if ! self_heal; then
            return 1
        fi
        return 1
    fi
    
    # Record successful update
    record_update
    
    # Clean up temporary files
    rm -f "$TEMP_UPDATE_FILE" "$TEMP_SIG_FILE"
    release_update_lock
    
    log "=========================================="
    log "Auto-Update Process Completed Successfully"
    log "=========================================="
    
    return 0
}

# =============================================================================
# ROLLBACK COMMANDS
# =============================================================================

# List available rollback versions
cmd_rollback_list() {
    list_rollbacks
}

# Rollback to a specific version
cmd_rollback() {
    local target="${1:-}"
    rollback_to "$target"
}

# Generate signature for distribution
cmd_generate_signature() {
    generate_signature
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Handle command-line arguments
FORCE_UPDATE=false
ROLLBACK_MODE=false
ROLLBACK_TARGET=""
GENERATE_SIG=false
for arg in "$@"; do
    case "$arg" in
        --force)
            FORCE_UPDATE=true
            ;;
        --runtime-root=*)
            RUNTIME_ROOT="${arg#*=}"
            ;;
        --rollback)
            ROLLBACK_MODE=true
            ;;
        --rollback=*)
            ROLLBACK_MODE=true
            ROLLBACK_TARGET="${arg#*=}"
            ;;
        --rollback-list)
            cmd_rollback_list
            exit $?
            ;;
        --generate-signature)
            GENERATE_SIG=true
            ;;
        --help|-h)
            cat <<EOF
Enterprise Framework Auto-Update Utility

Usage: $0 [options]

Options:
  --force                    Force update even if not needed
  --runtime-root=<path>     Override runtime root directory
  --rollback                Rollback to latest version
  --rollback=<version>      Rollback to specific version
  --rollback-list           List available rollback versions
  --generate-signature      Generate SHA256 signature for current file
  --help, -h                Show this help

Environment Variables:
  AUTO_UPDATE_URL       URL to fetch updates from (default: GitHub)
  AUTO_UPDATE_SIG_URL   URL to fetch SHA256 signature from
  AUTO_UPDATE_INTERVAL   Update check interval in seconds (default: 86400)
  MAX_BACKUP_VERSIONS   Max rollback versions to keep (default: 5)
  AUTO_UPDATE            Set to 'false' to disable auto-update (default: true)

Security Notes:
  - Always use HTTPS URLs
  - Signature verification provides integrity protection
  - Rollback capability ensures recovery from bad updates
  - Configurable URLs allow use with private repositories
EOF
            exit 0
            ;;
        *)
            # Unknown argument
            ;;
    esac
done

# Check if auto-update is disabled
if [[ "${AUTO_UPDATE:-true}" == "false" ]]; then
    log "Auto-update is disabled"
    exit 0
fi

# Handle rollback command
if [[ "$ROLLBACK_MODE" == "true" ]]; then
    cmd_rollback "$ROLLBACK_TARGET"
    exit $?
fi

# Handle signature generation
if [[ "$GENERATE_SIG" == "true" ]]; then
    cmd_generate_signature
    exit $?
fi

# Run auto-update
if $FORCE_UPDATE; then
    auto_update --force
else
    auto_update
fi

exit $?
