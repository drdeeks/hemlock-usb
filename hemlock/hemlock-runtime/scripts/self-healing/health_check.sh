#!/bin/bash
# =============================================================================
# Health Check Script for Enterprise Framework
# Comprehensive health monitoring and self-healing for the entire framework
# =============================================================================

set -uo pipefail

# Colors for consistent logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/helpers.sh"

# =============================================================================
# HEALTH CHECK RESULTS
# =============================================================================

HEALTH_ISSUES=0
HEALTH_WARNINGS=0
HEALTH_PASSES=0
HEALTH_REPORT=""

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; HEALTH_WARNINGS=$((HEALTH_WARNINGS + 1)); }
error() { echo -e "${RED}[FAIL]${NC} $1" >&2; HEALTH_ISSUES=$((HEALTH_ISSUES + 1)); }

pass() {
    HEALTH_PASSES=$((HEALTH_PASSES + 1))
    HEALTH_REPORT+="[PASS] $1\n"
    success "$1"
}

warn_health() {
    HEALTH_WARNINGS=$((HEALTH_WARNINGS + 1))
    HEALTH_REPORT+="[WARN] $1\n"
    warn "$1"
}

fail_health() {
    HEALTH_ISSUES=$((HEALTH_ISSUES + 1))
    HEALTH_REPORT+="[FAIL] $1\n"
    error "$1"
}

# =============================================================================
# HEALTH CHECK CONFIGURATION
# =============================================================================

# Directories to check
CHECK_DIRS=(
    "agents"
    "config"
    "scripts"
    "plugins"
    "skills"
    "lib"
    "tests"
    "logs"
    "docker"
    "docs"
    "data"
)

# Critical files to check
CRITICAL_FILES=(
    "runtime.sh"
    "scripts/backup-interactive.sh"
    "scripts/tool-inject-memory.sh"
    "lib/common.sh"
    "config/backup-config.yaml"
    "docker/docker-compose.yml"
    "docker/entrypoint.sh"
)

# Required scripts that should be executable
EXECUTABLE_SCRIPTS=(
    "runtime.sh"
    "scripts/backup-interactive.sh"
    "scripts/tool-inject-memory.sh"
    "scripts/create_crew.py"
    "scripts/memory.sh"
    "scripts/backup.sh"
    "scripts/restore.sh"
    "tests/validation/validate_structure.sh"
    "tests/validation/validate_permissions.sh"
    "tests/run_all.sh"
)

#.Services to check (if running)
SERVICES_TO_CHECK=(
    "docker"
    "git"
)

# =============================================================================
# CHECK FUNCTIONS
# =============================================================================

check_directory_structure() {
    log "Checking directory structure..."
    
    for dir in "${CHECK_DIRS[@]}"; do
        if [[ -d "$RUNTIME_ROOT/$dir" ]]; then
            pass "Directory $dir exists"
        else
            warn_health "Directory $dir is missing"
        fi
    done
}

check_critical_files() {
    log "Checking critical files..."
    
    for file in "${CRITICAL_FILES[@]}"; do
        if [[ -f "$RUNTIME_ROOT/$file" ]]; then
            pass "Critical file $file exists"
        else
            fail_health "Critical file $file is missing"
        fi
    done
}

check_executable_permissions() {
    log "Checking executable permissions..."
    
    for script in "${EXECUTABLE_SCRIPTS[@]}"; do
        local full_path="$RUNTIME_ROOT/$script"
        if [[ ! -f "$full_path" ]]; then
            warn_health "Script $script does not exist"
            continue
        fi
        
        if [[ -x "$full_path" ]]; then
            pass "Script $script is executable"
        else
            fail_health "Script $script is not executable (fixing...)"
            chmod 755 "$full_path" 2>/dev/null
            if [[ -x "$full_path" ]]; then
                pass "Fixed permissions for $script"
            else
                fail_health "Failed to fix permissions for $script"
            fi
        fi
    done
}

check_no_700_permissions() {
    log "Checking for forbidden 700 permissions..."
    
    local found_700=0
    while IFS= read -r -d '' file; do
        local perms
        perms=$(stat -c "%a" "$file" 2>/dev/null || echo "")
        if [[ "$perms" == "700" ]]; then
            found_700=1
            fail_health "File has forbidden 700 permissions: $file (fixing to 755...)"
            chmod 755 "$file" 2>/dev/null
        fi
    done < <(find "$RUNTIME_ROOT" -type f \( -perm 700 -o -perm 7000 \) ! -path "*/.git/*" ! -path "*/node_modules/*" -print0 2>/dev/null)
    
    if [[ $found_700 -eq 0 ]]; then
        pass "No files with 700 permissions found"
    fi
}

check_required_commands() {
    log "Checking required commands..."
    
    local commands=("bash" "grep" "find" "sed" "awk" "tar" "gzip" "openssl" "rsync" "docker" "python3" "git")
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" &>/dev/null; then
            pass "Command $cmd is available"
        else
            fail_health "Command $cmd is not available"
        fi
    done
}

check_docker_environment() {
    log "Checking Docker environment..."
    
    if ! command -v docker &>/dev/null; then
        warn_health "Docker is not installed"
        return
    fi
    
    if docker info &>/dev/null; then
        pass "Docker daemon is running"
    else
        fail_health "Docker daemon is not running"
    fi
}

check_disk_space() {
    log "Checking disk space..."
    
    local disk_info
    disk_info=$(df -h "$RUNTIME_ROOT" 2>/dev/null | tail -1)
    
    if [[ -z "$disk_info" ]]; then
        warn_health "Could not check disk space"
        return
    fi
    
    # Check if at least 10% free
    local use_percent
    use_percent=$(echo "$disk_info" | awk '{print $5}' | tr -d '%')
    
    if [[ ${use_percent:-100} -lt 90 ]]; then
        pass "Disk space is healthy (${use_percent}% used)"
    else
        fail_health "Disk space is low (${use_percent}% used)"
    fi
}

check_memory_usage() {
    log "Checking memory usage..."
    
    if command -v free &>/dev/null; then
        local mem_info
        mem_info=$(free -m 2>/dev/null | head -2 | tail -1)
        
        if [[ -n "$mem_info" ]]; then
            # Get memory usage percentage
            local total used
            total=$(echo "$mem_info" | awk '{print $2}')
            used=$(echo "$mem_info" | awk '{print $3}')
            
            if [[ $total -gt 0 ]]; then
                local usage=$((used * 100 / total))
                if [[ $usage -lt 80 ]]; then
                    pass "Memory usage is healthy (${usage}%)"
                else
                    warn_health "Memory usage is high (${usage}%)"
                fi
            fi
        fi
    fi
}

check_backup_config() {
    log "Checking backup configuration..."
    
    local backup_config="$CONFIG_DIR/backup-config.yaml"
    
    if [[ -f "$backup_config" ]]; then
        pass "Backup configuration exists"
        
        # Check if it's readable
        if [[ -r "$backup_config" ]]; then
            pass "Backup configuration is readable"
        else
            fail_health "Backup configuration is not readable"
        fi
    else
        warn_health "Backup configuration is missing"
    fi
}

check_git_status() {
    log "Checking git status..."
    
    if [[ -d "$RUNTIME_ROOT/.git" ]]; then
        if git -C "$RUNTIME_ROOT" status &>/dev/null 2>&1; then
            pass "Git repository is valid"
            
            # Check for uncommitted changes
            local status
            status=$(git -C "$RUNTIME_ROOT" status --porcelain 2>/dev/null | wc -l)
            if [[ $status -eq 0 ]]; then
                pass "Git working tree is clean"
            else
                warn_health "Git has uncommitted changes ($status files modified)"
            fi
        else
            fail_health "Git repository has errors"
        fi
    else
        warn_health "Not in a git repository"
    fi
}

check_agents_status() {
    log "Checking agents status..."
    
    local agents_dir="$AGENTS_DIR"
    if [[ ! -d "$agents_dir" ]]; then
        warn_health "Agents directory does not exist"
        return
    fi
    
    local agent_count=0
    local running_count=0
    
    for agent_dir in "$agents_dir"/*/; do
        if [[ -d "$agent_dir" ]]; then
            agent_count=$((agent_count + 1))
            local agent_name=$(basename "$agent_dir")
            
            # Check if agent has basic structure
            if [[ -f "$agent_dir/data/SOUL.md" || -f "$agent_dir/config.yaml" ]]; then
                pass "Agent $agent_name has valid structure"
                running_count=$((running_count + 1))
            else
                warn_health "Agent $agent_name has incomplete structure"
            fi
        fi
    done
    
    log "Found $agent_count agents, $running_count with valid structure"
}

check_crews_status() {
    log "Checking crews status..."
    
    local crews_dir="$CREWS_DIR"
    if [[ ! -d "$crews_dir" ]]; then
        warn_health "Crews directory does not exist"
        return
    fi
    
    local crew_count=0
    local valid_count=0
    
    for crew_dir in "$crews_dir"/*/; do
        if [[ -d "$crew_dir" ]]; then
            crew_count=$((crew_count + 1))
            local crew_name=$(basename "$crew_dir")
            
            # Check if crew has basic structure
            if [[ -f "$crew_dir/crew.json" ]]; then
                pass "Crew $crew_name has valid structure"
                valid_count=$((valid_count + 1))
            else
                warn_health "Crew $crew_name is missing crew.json"
            fi
        fi
    done
    
    log "Found $crew_count crews, $valid_count with valid structure"
}

# =============================================================================
# SELF-HEALING FUNCTIONS
# =============================================================================

attempt_self_healing() {
    log "=========================================="
    log "Attempting Self-Healing"
    log "=========================================="
    
    local healed=0
    
    # Check and fix directory structure
    for dir in "${CHECK_DIRS[@]}"; do
        if [[ ! -d "$RUNTIME_ROOT/$dir" ]]; then
            warn "Creating missing directory: $dir"
            mkdir -p "$RUNTIME_ROOT/$dir" 2>/dev/null
            if [[ -d "$RUNTIME_ROOT/$dir" ]]; then
                pass "Created directory $dir"
                healed=$((healed + 1))
            else
                fail_health "Failed to create directory $dir"
            fi
        fi
    done
    
    # Check and fix critical files (stubs)
    for file in "${CRITICAL_FILES[@]}"; do
        local full_path="$RUNTIME_ROOT/$file"
        case "$file" in
            *.yaml|*.yml)
                if [[ ! -f "$full_path" ]]; then
                    warn "Creating stub for $file"
                    echo "# $file - will be configured during setup" > "$full_path" 2>/dev/null
                    if [[ -f "$full_path" ]]; then
                        pass "Created stub for $file"
                        healed=$((healed + 1))
                    fi
                fi
                ;;
            *.sh)
                if [[ ! -f "$full_path" ]]; then
                    warn "Creating stub for $file"
                    echo "#!/bin/bash" > "$full_path" 2>/dev/null
                    echo "# $file - will be implemented" >> "$full_path" 2>/dev/null
                    chmod 755 "$full_path" 2>/dev/null
                    if [[ -f "$full_path" ]]; then
                        pass "Created stub for $file"
                        healed=$((healed + 1))
                    fi
                fi
                ;;
        esac
    done
    
    log "Self-healing attempted $healed fixes"
    return 0
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log "=========================================="
    log "Health Check - Enterprise Framework"
    log "=========================================="
    log "Runtime Root: $RUNTIME_ROOT"
    log ""
    
    # Run all checks
    check_directory_structure
    log ""
    
    check_critical_files
    log ""
    
    check_executable_permissions
    log ""
    
    check_no_700_permissions
    log ""
    
    check_required_commands
    log ""
    
    check_docker_environment
    log ""
    
    check_disk_space
    log ""
    
    check_memory_usage
    log ""
    
    check_backup_config
    log ""
    
    check_git_status
    log ""
    
    check_agents_status
    log ""
    
    check_crews_status
    log ""
    
    # Attempt self-healing if there are issues
    if [[ $HEALTH_ISSUES -gt 0 ]]; then
        warn "Found $HEALTH_ISSUES critical issues, attempting self-healing..."
        attempt_self_healing
    fi
    
    # Summary
    log ""
    log "=========================================="
    log "Health Check Summary"
    log "=========================================="
    log "Passes: $HEALTH_PASSES"
    log "Warnings: $HEALTH_WARNINGS"
    log "Failures: $HEALTH_ISSUES"
    log ""
    
    if [[ $HEALTH_ISSUES -eq 0 ]]; then
        success "Health check PASSED"
        exit 0
    else
        error "Health check FAILED with $HEALTH_ISSUES critical issues"
        exit 1
    fi
}

main
