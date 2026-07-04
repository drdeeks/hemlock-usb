#!/bin/bash
# =============================================================================
# Common Functions Library for Enterprise Framework
# Shared utilities for error handling, logging, validation, and self-healing
# =============================================================================

set -uo pipefail

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Runtime root - can be overridden via environment
# Try multiple methods to determine RUNTIME_ROOT, with environment variable taking precedence
if [[ -z "${RUNTIME_ROOT:-}" ]]; then
    # Method 1: Check if we can find a marker file (runtime.sh in parent directory)
    search_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [[ "$search_dir" != "/" && ! -f "$search_dir/runtime.sh" ]]; do
        search_dir="$(dirname "$search_dir")"
    done
    if [[ -f "$search_dir/runtime.sh" ]]; then
        RUNTIME_ROOT="$search_dir"
    else
        # Method 2: Go up from script location
        RUNTIME_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        # Method 3: Check if this is a git repo root
        if [[ -d "$RUNTIME_ROOT/.git" ]]; then
            RUNTIME_ROOT="$(git -C "$RUNTIME_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$RUNTIME_ROOT")"
        fi
    fi
fi
SCRIPTS_DIR="$RUNTIME_ROOT/scripts"
AGENTS_DIR="$RUNTIME_ROOT/agents"
CREWS_DIR="$RUNTIME_ROOT/crews"
CONFIG_DIR="$RUNTIME_ROOT/config"
PLUGINS_DIR="$RUNTIME_ROOT/plugins"
SKILLS_DIR="$RUNTIME_ROOT/skills"
LOGS_DIR="$RUNTIME_ROOT/logs"
TESTS_DIR="$RUNTIME_ROOT/tests"
TOOLS_DIR="$RUNTIME_ROOT/tools"

# Colors for consistent logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Error tracking
ERROR_COUNT=0
WARNING_COUNT=0

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[INFO]${NC} ${FUNCNAME[1]:-main}: $*"
}

success() {
    echo -e "${GREEN}[PASS]${NC} ${FUNCNAME[1]:-main}: $*"
}

warn() {
    WARNING_COUNT=$((WARNING_COUNT + 1))
    echo -e "${YELLOW}[WARN]${NC} ${FUNCNAME[1]:-main}: $*" >&2
}

error() {
    ERROR_COUNT=$((ERROR_COUNT + 1))
    echo -e "${RED}[FAIL]${NC} ${FUNCNAME[1]:-main}: $*" >&2
}

fatal() {
    error "$*"
    exit 1
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} ${FUNCNAME[1]:-main}: $*"
    fi
}

# =============================================================================
# ERROR HANDLING & SELF-HEALING
# =============================================================================

# Track if we're in a retry
RETRY_DEPTH=0
MAX_RETRIES=3
RETRY_DELAY=1

# Generic retry mechanism with fallback
retry_with_fallback() {
    local func="$1"
    local fallback_func="$2"
    local max_retries="${3:-$MAX_RETRIES}"
    local delay="${4:-$RETRY_DELAY}"
    shift 4
    local args=("$@")
    
    local attempt=0
    local success=false
    
    while [[ $attempt -lt $max_retries ]]; do
        debug "Attempt $((attempt + 1))/$max_retries for $func"
        
        if "$func" "${args[@]}" 2>/dev/null; then
            success=true
            break
        fi
        
        attempt=$((attempt + 1))
        warn "Attempt $attempt failed for $func, retrying in $delay seconds..."
        sleep $delay
        delay=$((delay * 2))  # Exponential backoff
    done
    
    if [[ "$success" == false ]] && [[ -n "$fallback_func" ]]; then
        debug "Trying fallback: $fallback_func"
        if "$fallback_func" "${args[@]}" 2>/dev/null; then
            warn "Function failed but fallback succeeded: $func -> $fallback_func"
            return 0
        fi
    fi
    
    if [[ "$success" == false ]]; then
        error "All $max_retries attempts failed for $func, no working fallback"
        return 1
    fi
    
    return 0
}

# Safe command execution with error handling
safe_exec() {
    local cmd="$*"
    debug "Executing: $cmd"
    
    if ! eval "$cmd" 2>/dev/null; then
        warn "Command failed: $cmd"
        return 1
    fi
    return 0
}

# Validate command exists before using
require_command() {
    local cmd="$1"
    local purpose="$2"
    
    if ! command -v "$cmd" &>/dev/null; then
        error "Required command '$cmd' not found ($purpose)"
        return 1
    fi
    return 0
}

# Validate directory exists and is writable
require_writable_dir() {
    local dir="$1"
    local purpose="$2"
    
    if [[ ! -d "$dir" ]]; then
        error "Directory does not exist: $dir ($purpose)"
        return 1
    fi
    
    if [[ ! -w "$dir" ]]; then
        error "Directory not writable: $dir ($purpose)"
        return 1
    fi
    
    return 0
}

# Validate file exists and is readable
require_readable_file() {
    local file="$1"
    local purpose="$2"
    
    if [[ ! -f "$file" ]]; then
        error "File does not exist: $file ($purpose)"
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        error "File not readable: $file ($purpose)"
        return 1
    fi
    
    return 0
}

# =============================================================================
# FILE SYSTEM UTILITIES
# =============================================================================

# Create directory with fallback
safe_mkdir() {
    local dir="$1"
    
    if mkdir -p "$dir" 2>/dev/null; then
        debug "Created directory: $dir"
        return 0
    fi
    
    warn "mkdir failed for $dir, trying alternative approaches..."
    
    # Fallback approaches
    local parent=$(dirname "$dir")
    if [[ ! -d "$parent" ]]; then
        safe_mkdir "$parent" || return 1
    fi
    
    if mkdir "$dir" 2>/dev/null; then
        return 0
    fi
    
    # Try with sudo if running as non-root
    if command -v sudo &>/dev/null && [[ $EUID -ne 0 ]]; then
        sudo mkdir -p "$dir" 2>/dev/null && sudo chown $(whoami) "$dir" 2>/dev/null
        return $?
    fi
    
    error "Failed to create directory: $dir"
    return 1
}

# Write file with atomic operation (write to temp, then mv)
atomic_write() {
    local file="$1"
    local content="$2"
    local tmp_file="${file}.tmp.$$"
    
    # Write to temp file
    echo "$content" > "$tmp_file" 2>/dev/null || return 1
    
    # Validate temp file
    if [[ ! -f "$tmp_file" ]] || [[ ! -s "$tmp_file" ]]; then
        rm -f "$tmp_file" 2>/dev/null
        return 1
    fi
    
    # Atomic move
    if mv "$tmp_file" "$file" 2>/dev/null; then
        debug " atomically wrote: $file"
        return 0
    fi
    
    # Fallback: try cp + rm
    cp "$tmp_file" "$file" 2>/dev/null && rm -f "$tmp_file" 2>/dev/null && return 0
    
    rm -f "$tmp_file" 2>/dev/null
    error "Failed to write file: $file"
    return 1
}

# =============================================================================
# PERMISSION UTILITIES
# =============================================================================

# Set permissions with validation
safe_chmod() {
    local path="$1"
    local perms="$2"
    
    if chmod "$perms" "$path" 2>/dev/null; then
        debug "Set permissions $perms on $path"
        return 0
    fi
    
    # Fallback: try with sudo
    if command -v sudo &>/dev/null && [[ $EUID -ne 0 ]]; then
        sudo chmod "$perms" "$path" 2>/dev/null && return 0
    fi
    
    warn "Failed to set permissions $perms on $path"
    return 1
}

# Validate permission is not too restrictive (no 700)
validate_permission() {
    local path="$1"
    
    if [[ ! -e "$path" ]]; then
        warn "Path does not exist: $path"
        return 1
    fi
    
    local perms
    perms=$(stat -c "%a" "$path" 2>/dev/null || stat -f "%OLp" "$path" 2>/dev/null)
    
    if [[ "$perms" == "700" ]]; then
        error "Permission 700 found on $path - this breaks isolation"
        return 1
    fi
    
    return 0
}

# Scan for and fix problematic permissions
fix_permissions() {
    local root_dir="${1:-$RUNTIME_ROOT}"
    local fixed=0
    local total=0
    
    log "Scanning for problematic permissions in $root_dir..."
    
    while IFS= read -r -d '' file; do
        total=$((total + 1))
        local perms
        perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%OLp" "$file" 2>/dev/null)
        
        if [[ "$perms" == "700" ]]; then
            debug "Fixing permission on $file"
            safe_chmod "$file" "755" && fixed=$((fixed + 1))
        fi
    done < <(find "$root_dir" -type f -perm 700 -print0 2>/dev/null)
    
    while IFS= read -r -d '' dir; do
        total=$((total + 1))
        local perms
        perms=$(stat -c "%a" "$dir" 2>/dev/null || stat -f "%OLp" "$dir" 2>/dev/null)
        
        if [[ "$perms" == "700" ]]; then
            debug "Fixing permission on directory $dir"
            safe_chmod "$dir" "755" && fixed=$((fixed + 1))
        fi
    done < <(find "$root_dir" -type d -perm 700 -print0 2>/dev/null)
    
    if [[ $fixed -gt 0 ]]; then
        success "Fixed $fixed problematic permissions out of $total checked"
    else
        success "No problematic permissions found ($total checked)"
    fi
    
    return 0
}

# =============================================================================
# VALIDATION UTILITIES
# =============================================================================

# Validate required files exist
validate_required_files() {
    local base_dir="$1"
    shift
    local required_files=("$@")
    local missing=0
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$base_dir/$file" ]]; then
            error "Missing required file: $base_dir/$file"
            missing=$((missing + 1))
        fi
    done
    
    [[ $missing -eq 0 ]] && return 0 || return 1
}

# Validate required directories exist
validate_required_dirs() {
    local base_dir="$1"
    shift
    local required_dirs=("$@")
    local missing=0
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$base_dir/$dir" ]]; then
            error "Missing required directory: $base_dir/$dir"
            missing=$((missing + 1))
        fi
    done
    
    [[ $missing -eq 0 ]] && return 0 || return 1
}

# =============================================================================
# SELF-HEALING UTILITIES
# =============================================================================

# Heal common issues
heal_issue() {
    local issue_type="$1"
    local context="$2"
    
    case "$issue_type" in
        "permission_denied")
            debug "Healing permission denied for $context"
            safe_chmod "$context" "755" && return 0
            ;;
        "missing_directory")
            debug "Healing missing directory: $context"
            safe_mkdir "$context" && return 0
            ;;
        "missing_file")
            debug "Cannot heal missing file: $context (recreate manually)"
            return 1
            ;;
        "command_not_found")
            debug "Cannot heal missing command: $context"
            return 1
            ;;
        *)
            debug "Unknown issue type: $issue_type for $context"
            return 1
            ;;
    esac
    
    return 1
}

# Automatic healing wrapper
with_self_healing() {
    local func="$1"
    shift
    local args=("$@")
    
    # Try to execute normally
    if "$func" "${args[@]}"; then
        return 0
    fi
    
    # Self-healing attempt
    local exit_code=$?
    warn "$func failed with exit code $exit_code, attempting self-heal..."
    
    # Determine issue type from error
    case $exit_code in
        126) heal_issue "command_not_found" "$func" && "$func" "${args[@]}" && return 0 ;;
        127) heal_issue "command_not_found" "$func" && "$func" "${args[@]}" && return 0 ;;
        *)
            # Try generic retry
            retry_with_fallback "$func" "" "$MAX_RETRIES" "$RETRY_DELAY" "${args[@]}" && return 0
            ;;
    esac
    
    error "Self-healing failed for $func"
    return $exit_code
}

# =============================================================================
# ENVIRONMENT DETECTION
# =============================================================================

detect_environment() {
    # Detect if running in container
    if [[ -f /.dockerenv ]]; then
        export ENVIRONMENT="docker"
    elif grep -qs 'docker' /proc/1/cgroup 2>/dev/null; then
        export ENVIRONMENT="docker"
    elif [[ -d /run/.containerenv ]]; then
        export ENVIRONMENT="podman"
    else
        export ENVIRONMENT="host"
    fi
    
    # Detect if root
    if [[ $EUID -eq 0 ]]; then
        export IS_ROOT="true"
    else
        export IS_ROOT="false"
    fi
    
    # Set runtime root if not already set
    if [[ -z "$RUNTIME_ROOT" ]]; then
        if [[ -f /etc/runtime-root ]]; then
            RUNTIME_ROOT=$(cat /etc/runtime-root)
        elif [[ -d /app && -f /app/agent.json ]]; then
            RUNTIME_ROOT=/app
        else
            RUNTIME_ROOT=$(pwd)
        fi
        export RUNTIME_ROOT
    fi
    
    log "Environment: $ENVIRONMENT, Root: $IS_ROOT, Runtime: $RUNTIME_ROOT"
}

# =============================================================================
# CLEANUP HOOKS
# =============================================================================

# Register cleanup hooks
CLEANUP_HOOKS=()

register_cleanup() {
    local hook="$1"
    CLEANUP_HOOKS+=("$hook")
}

run_cleanup() {
    local exit_code=$?
    
    # Run cleanup hooks in reverse order
    for ((i=${#CLEANUP_HOOKS[@]}-1; i>=0; i--)); do
        debug "Running cleanup hook: ${CLEANUP_HOOKS[$i]}"
        eval "${CLEANUP_HOOKS[$i]}" 2>/dev/null || warn "Cleanup hook failed: ${CLEANUP_HOOKS[$i]}"
    done
    
    exit $exit_code
}

# Trap exit for cleanup
trap run_cleanup EXIT

# =============================================================================
# Main initialization
# =============================================================================

# Detect environment on library load
detect_environment

# Export common variables
export RUNTIME_ROOT SCRIPTS_DIR AGENTS_DIR CREWS_DIR CONFIG_DIR PLUGINS_DIR SKILLS_DIR LOGS_DIR TESTS_DIR TOOLS_DIR

export RED GREEN YELLOW BLUE MAGENTA CYAN NC

export ERROR_COUNT WARNING_COUNT

log "Common library initialized"
