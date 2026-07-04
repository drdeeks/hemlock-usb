#!/bin/bash
# =============================================================================
# Agent Workspace Enforcement
# Integrates the workspace enforcement protocol into the runtime
# =============================================================================

set +euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTOCOLS_DIR="${RUNTIME_ROOT}/protocols"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

log() { echo -e "${BLUE}[----]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)) || true; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)) || true; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)) || true; }

# =============================================================================
# Enforcement Rules
# =============================================================================

# Directory renames
declare -A DIR_RENAMES=(
    ["memories"]="memory"
    ["cache"]="media"
    ["archives"]=".archive"
)

# Forbidden directories
FORBIDDEN_DIRS=(
    "cron" "docs" "platforms" "state" "sandboxes" "hooks" "audio_cache" "image_cache" "pairing" "profiles" "whatsapp" "checkpoints"
)

# Required files
REQUIRED_FILES=(
    "SOUL.md" "USER.md" "AGENTS.md" "agent.json" "config.yaml"
)

# =============================================================================
# Enforcement Functions
# =============================================================================

enforce_directory_renames() {
    local workspace="$1"
    
    for old_dir in "${!DIR_RENAMES[@]}"; do
        local new_dir="${DIR_RENAMES[$old_dir]}"
        if [[ -d "${workspace}/${old_dir}" ]]; then
            if [[ -d "${workspace}/${new_dir}" ]]; then
                warn "Both ${old_dir}/ and ${new_dir}/ exist"
                log "  Merging ${old_dir}/ into ${new_dir}/"
                mv -n "${workspace}/${old_dir}"/* "${workspace}/${new_dir}/" 2>/dev/null || true
                rmdir "${workspace}/${old_dir}" 2>/dev/null || true
            else
                log "Renaming ${old_dir}/ → ${new_dir}/"
                mv "${workspace}/${old_dir}" "${workspace}/${new_dir}"
            fi
        fi
    done
}

enforce_forbidden_dirs() {
    local workspace="$1"
    
    for dir in "${FORBIDDEN_DIRS[@]}"; do
        if [[ -d "${workspace}/${dir}" ]]; then
            log "Archiving forbidden directory: ${dir}/"
            tar -czf "${workspace}/.archive/${dir}-$(date +%Y%m%d).tar.gz" -C "${workspace}" "${dir}"
            rm -rf "${workspace}/${dir}"
        fi
    done
}

enforce_required_files() {
    local workspace="$1"

    for file in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "${workspace}/${file}" ]]; then
            warn "Missing required file: ${file}"
            touch "${workspace}/${file}"
            echo "# Auto-created by enforce.sh" > "${workspace}/${file}"
        fi
    done
}

enforce_permissions() {
    local workspace="$1"
    
    # Fix chmod 700/600 violations — NEVER 700, NEVER 600
    find "${workspace}" -type d -perm 700 -exec chmod 755 {} \;
    find "${workspace}" -type f \( -perm 700 -o -perm 600 \) -exec chmod 644 {} \;
    
    # Fix root ownership
    find "${workspace}" -user root -exec chown 1000:1000 {} \;
}

enforce_secrets() {
    local workspace="$1"
    
    # Ensure .secrets exists
    mkdir -p "${workspace}/.secrets"
    chmod 755 "${workspace}/.secrets"
    
    # Ensure secrets are encrypted
    if [[ -f "${workspace}/.secrets/secrets.json" ]]; then
        pass "Secrets file exists"
    else
        warn "No secrets file found"
        touch "${workspace}/.secrets/secrets.json"
        chmod 644 "${workspace}/.secrets/secrets.json"
    fi
}

enforce_tools() {
    local workspace="$1"
    
    # Ensure tools directory exists
    mkdir -p "${workspace}/tools"
    
    # Create required tools
    for tool in "secret.sh" "memory-log.sh" "memory-promote.sh" "jsonfmt.py"; do
        if [[ ! -f "${workspace}/tools/${tool}" ]]; then
            warn "Missing tool: ${tool}"
            touch "${workspace}/tools/${tool}"
            chmod 755 "${workspace}/tools/${tool}"
        fi
    done
}

enforce_memory() {
    local workspace="$1"
    
    # Ensure memory directory exists
    mkdir -p "${workspace}/memory"
    
    # Ensure today's memory file exists
    local today="$(date +%Y-%m-%d)"
    local memory_file="${workspace}/memory/${today}.md"
    
    if [[ ! -f "$memory_file" ]]; then
        log "Creating today's memory file"
        echo "# Memory — ${today}" > "$memory_file"
        echo "" >> "$memory_file"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    local workspace="${RUNTIME_ROOT}/agents"
    local fix="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            -f|--fix) fix="true"; shift ;;
            *) workspace="$1"; shift ;;
        esac
    done
    
    # Validate workspace
    if [[ ! -d "$workspace" ]]; then
        error "Workspace not found: $workspace"
        exit 1
    fi
    
    log "Enforcing workspace rules in: $workspace"
    
    # Create archive directory
    mkdir -p "${workspace}/.archive"
    
    # Run enforcement
    enforce_directory_renames "$workspace"
    enforce_forbidden_dirs "$workspace"
    enforce_required_files "$workspace"
    enforce_permissions "$workspace"
    enforce_secrets "$workspace"
    enforce_tools "$workspace"
    enforce_memory "$workspace"
    
    # Summary
    echo ""
    echo "=== Summary ==="
    echo -e "  ${GREEN}Passed:${NC}  $PASS"
    echo -e "  ${RED}Failed:${NC}  $FAIL"
    echo -e "  ${YELLOW}Warnings:${NC} $WARN"
    echo ""
    
    if [[ $FAIL -eq 0 ]]; then
        echo -e "${GREEN}✓ Workspace enforcement complete!${NC}"
        return 0
    else
        echo -e "${RED}✗ Workspace enforcement failed${NC}"
        return 1
    fi
}

main "$@"