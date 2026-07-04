#!/bin/bash
# =============================================================================
# Hemlock Cleanup System
# Robust cleansing logic for logs, cache, and temporary files
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# =============================================================================
# Configuration
# =============================================================================

# Log retention: Keep logs for X days (default: 7)
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-7}

# Cache directories to clean
CACHE_DIRS=(
    "$RUNTIME_ROOT/.cache"
    "$LOGS_DIR/.cache"
    "/tmp/hemlock_*"
    "$HOME/.cache/hermes"
    "$HOME/.cache/openclaw"
)

# Log directories to clean
LOG_DIRS=(
    "$LOGS_DIR"
    "$AGENTS_DIR/*/logs"
    "$CREWS_DIR/*/logs"
)

# Temporary file patterns
TEMP_PATTERNS=(
    "*.tmp"
    "*.temp"
    "*.swp"
    "*.swo"
    "*~"
    ".*.bak"
    ".*.backup"
    "*.log.old"
    "core.*"
)

# Files to never clean (protected)
PROTECTED_FILES=(
    "runtime.log"
    ".gitignore"
    "docker-compose.yml"
)

# =============================================================================
# Helper Functions
# =============================================================================

# Check if file is protected
is_protected() {
    local file="$1"
    for protected in "${PROTECTED_FILES[@]}"; do
        if [[ "$file" == *"$protected"* ]]; then
            return 0
        fi
    done
    return 1
}

# Clean files matching pattern in directory
clean_pattern() {
    local dir="$1"
    local pattern="$2"
    local max_age="$3"
    
    if [[ ! -d "$dir" ]]; then
        return 0
    fi
    
    find "$dir" -name "$pattern" -type f ! -newermt "$(date -d "$max_age days ago" +%Y-%m-%d)" 2>/dev/null | while read -r file; do
        if ! is_protected "$file"; then
            rm -f "$file"
        fi
    done
}

# Clean directory by age
clean_by_age() {
    local dir="$1"
    local max_age_days="$2"
    
    if [[ ! -d "$dir" ]]; then
        return 0
    fi
    
    find "$dir" -type f -mtime +"$max_age_days" 2>/dev/null | while read -r file; do
        if ! is_protected "$file"; then
            rm -f "$file"
        fi
    done
}

# Clean empty directories
clean_empty_dirs() {
    local dir="$1"
    find "$dir" -type d -empty -delete 2>/dev/null
}

# Clean cache directories
clean_caches() {
    for cache_dir in "${CACHE_DIRS[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            rm -rf "$cache_dir/*"
            log "INFO" "Cleaned cache: $cache_dir"
        fi
    done
}

# =============================================================================
# Cleanup Functions
# =============================================================================

clean_logs() {
    log "INFO" "Cleaning log files older than $LOG_RETENTION_DAYS days"
    
    # Clean log directories by age
    for log_dir in "${LOG_DIRS[@]}"; do
        clean_by_age "$log_dir" "$LOG_RETENTION_DAYS"
    done
    
    # Clean specific log patterns
    for log_dir in "${LOG_DIRS[@]}"; do
        for pattern in "*.log" "*.out"; do
            clean_pattern "$log_dir" "$pattern" "$LOG_RETENTION_DAYS"
        done
    done
    
    log "INFO" "Log cleanup complete"
}

clean_temp_files() {
    log "INFO" "Cleaning temporary files"
    
    for dir in "$RUNTIME_ROOT" "$AGENTS_DIR" "$RUNTIME_ROOT/scripts" "$RUNTIME_ROOT/tools"; do
        for pattern in "${TEMP_PATTERNS[@]}"; do
            clean_pattern "$dir" "$pattern" "0"
        done
    done
    
    log "INFO" "Temporary files cleanup complete"
}

clean_docker_artifacts() {
    log "INFO" "Cleaning Docker artifacts"
    
    # Docker images
    docker system prune -f 2>/dev/null && log "INFO" "Docker system prune complete" || true
    
    # Docker build cache
    docker builder prune -f 2>/dev/null && log "INFO" "Docker builder prune complete" || true
    
    log "INFO" "Docker cleanup complete"
}

clean_agent_artifacts() {
    log "INFO" "Cleaning agent artifacts"
    
    # Clean agent build artifacts
    find "$AGENTS_DIR" -name "Dockerfile" -o -name "*.tar" -o -name "*.tar.gz" 2>/dev/null | while read -r file; do
        if [[ "$file" != *"Dockerfile.agent"* ]]; then
            rm -f "$file"
        fi
    done
    
    log "INFO" "Agent artifacts cleanup complete"
}

clean_python_cache() {
    log "INFO" "Cleaning Python cache"
    
    # Python __pycache__
    find "$RUNTIME_ROOT" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
    find "$RUNTIME_ROOT" -type f -name "*.pyc" -delete 2>/dev/null
    
    # pip cache
    pip cache purge 2>/dev/null && log "INFO" "Pip cache purge complete" || true
    
    log "INFO" "Python cleanup complete"
}

# =============================================================================
# Main Cleanup Functions
# =============================================================================

# Full cleanup (all types)
full_cleanup() {
    log "INFO" "Starting full cleanup..."
    
    clean_logs
    clean_temp_files
    clean_caches
    clean_docker_artifacts
    clean_agent_artifacts
    clean_python_cache
    
    # Clean empty directories
    clean_empty_dirs "$RUNTIME_ROOT"
    
    log "INFO" "Full cleanup complete"
}

# Quick cleanup (logs and temp only)
quick_cleanup() {
    log "INFO" "Starting quick cleanup..."
    
    clean_logs
    clean_temp_files
    
    log "INFO" "Quick cleanup complete"
}

# Deep cleanup (aggressive, includes Docker prune)
deep_cleanup() {
    log "INFO" "Starting deep cleanup..."
    
    full_cleanup
    
    # Additional aggressive cleaning
    # Remove all untracked files (careful!)
    # git clean -fd
    
    log "INFO" "Deep cleanup complete"
}

# =============================================================================
# Auto-cleanup on agent operations
# =============================================================================

cleanup_agent_import() {
    local agent_id="$1"
    local agent_dir="$AGENTS_DIR/$agent_id"
    
    # Clean old import artifacts
    rm -f "$agent_dir/import.tmp" "$agent_dir/.import_lock" 2>/dev/null
    
    log "INFO" "Agent import cleanup complete for $agent_id"
}

cleanup_agent_delete() {
    local agent_id="$1"
    local agent_dir="$AGENTS_DIR/$agent_id"
    
    # Verify deletion
    if [[ -d "$agent_dir" ]]; then
        log "WARN" "Agent directory $agent_id still exists after cleanup"
        return 1
    fi
    
    # Clean runtime.log entries
    if [[ -f "$LOGS_DIR/runtime.log" ]]; then
        sed -i "/$agent_id/d" "$LOGS_DIR/runtime.log" 2>/dev/null
    fi
    
    # Clean agent logs
    rm -rf "$LOGS_DIR/${agent_id}.log" 2>/dev/null
    
    log "INFO" "Agent deletion cleanup complete for $agent_id"
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    local mode="${1:-full}"
    local verbosity="${2:-info}"
    
    case "$mode" in
        full)
            full_cleanup
            ;;
        quick)
            quick_cleanup
            ;;
        deep)
            deep_cleanup
            ;;
        logs)
            clean_logs
            ;;
        temp)
            clean_temp_files
            ;;
        docker)
            clean_docker_artifacts
            ;;
        py|python)
            clean_python_cache
            ;;
        agent)
            cleanup_agent_import "$3"
            ;;
        delete)
            cleanup_agent_delete "$3"
            ;;
        *)
            echo "Usage: $0 [full|quick|deep|logs|temp|docker|py|agent|delete] [verbose] [agent_id]"
            echo ""
            echo "Examples:"
            echo "  $0                    # Full cleanup"
            echo "  $0 quick               # Quick cleanup (logs + temp)"
            echo "  $0 deep               # Deep cleanup (all + Docker)"
            echo "  $0 logs               # Clean logs only"
            echo "  $0 delete <agent_id>  # Cleanup after deleting agent"
            exit 1
            ;;
    esac
}

main "$@"
