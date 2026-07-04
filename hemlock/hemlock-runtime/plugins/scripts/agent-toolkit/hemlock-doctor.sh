#!/bin/bash
# =============================================================================
# Hemlock Doctor Service
# 
# Comprehensive system health check, diagnostics, and troubleshooting service.
# Provides detailed system information, health checks, and troubleshooting
# guidance for Hemlock Enterprise Agent Framework.
# 
# Usage: ./hemlock-doctor.sh [command] [options]
# ==============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(dirname "$SCRIPTS_DIR")"
CONFIG_DIR="$RUNTIME_ROOT/config"
CACHE_DIR="$RUNTIME_ROOT/.cache"
AGENTS_DIR="$RUNTIME_ROOT/agents"
MODELS_DIR="$RUNTIME_ROOT/models"
LOGS_DIR="$RUNTIME_ROOT/logs"

# Persistent files
FIRST_RUN_FLAG="$CACHE_DIR/.first_run_completed"
SCAN_RESULTS="$CACHE_DIR/hardware-scan.json"
RECOMMENDATIONS="$CACHE_DIR/hardware-scan-recommendations.json"
PERSISTENT_CONFIG="$CONFIG_DIR/model-config.yaml"

# Flags
DRY_RUN=false
VERBOSE=false
JSON=false

# =============================================================================
# LOGGING
# =============================================================================

log() {
    echo -e "${BLUE}[DOCTOR]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

section() {
    echo ""
    echo -e "${PURPLE}================================================================================${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}================================================================================${NC}"
}

# =============================================================================
# USAGE
# =============================================================================

usage() {
    cat <<EOF
${CYAN}Hemlock Doctor Service${NC}

Comprehensive system diagnostics, health checks, and troubleshooting for
Hemlock Enterprise Agent Framework.

${BLUE}Usage:${NC}
  $0 <command> [options]

${BLUE}Commands:${NC}
  check           Run all health checks
  status          Show system status
  diagnose        Interactive diagnosis
  info           Show system information
  services       Check running services
  dependencies   Check required dependencies
  configuration Checks configuration files
  models         Check model files and configurations
  agents         Check agent configurations
  security       Run security checks
  troubleshoot   Interactive troubleshooting assistant
  report         Generate diagnostic report
  fix            Attempt to fix common issues
  
${BLUE}Options:${NC}
  --dry-run      Show what would be checked without running
  --verbose, -v  Verbose output
  --json         Output in JSON format
  --help, -h     Show this help
  --category <c> Run specific category (status, services, dependencies, etc.)

${BLUE}Examples:${NC}
  $0 check                   # Run all health checks
  $0 status                  # Show system status
  $0 diagnose                # Interactive diagnosis
  $0 services                # Check running services
  $0 dependencies            # Check dependencies
  $0 --verbose --json        # JSON output with verbose logging
  $0 troubleshoot            # Interactive troubleshooting
  $0 report                  # Generate full diagnostic report
  $0 fix --dry-run           # Show fixes without applying

EOF
}

# =============================================================================
# HEALTH CHECK FUNCTIONS
# =============================================================================

# Check if a command exists
check_command() {
    local cmd="$1"
    local name="$2"
    
    if command -v "$cmd" &>/dev/null; then
        if [[ "$JSON" == "true" ]]; then
            echo "  \"$name\": { \"available\": true, \"path\": \"$(which $cmd 2>/dev/null || echo 'unknown')\" }"
        else
            success "$name: Available ($(which $cmd 2>/dev/null || echo 'unknown'))"
        fi
        return 0
    else
        if [[ "$JSON" == "true" ]]; then
            echo "  \"$name\": { \"available\": false, \"path\": null }"
        else
            warn "$name: NOT FOUND"
        fi
        return 1
    fi
}

# Check directory exists
check_dir() {
    local dir="$1"
    local name="$2"
    
    if [[ -d "$dir" ]]; then
        if [[ "$JSON" == "true" ]]; then
            echo "  \"$name\": { \"exists\": true, \"path\": \"$dir\" }"
        else
            success "$name: Directory exists ($dir)"
        fi
        return 0
    else
        if [[ "$JSON" == "true" ]]; then
            echo "  \"$name\": { \"exists\": false, \"path\": \"$dir\" }"
        else
            warn "$name: Directory NOT FOUND ($dir)"
        fi
        return 1
    fi
}

# Check file exists
check_file() {
    local file="$1"
    local name="$2"
    
    if [[ -f "$file" ]]; then
        local size=$(stat -c '%s' "$file" 2>/dev/null || stat -f '%z' "$file" 2>/dev/null || echo "0")
        if [[ "$JSON" == "true" ]]; then
            echo "  \"$name\": { \"exists\": true, \"path\": \"$file\", \"size\": $size }"
        else
            success "$name: File exists ($file, ${size} bytes)"
        fi
        return 0
    else
        if [[ "$JSON" == "true" ]]; then
            echo "  \"$name\": { \"exists\": false, \"path\": \"$file\", \"size\": 0 }"
        else
            warn "$name: File NOT FOUND ($file)"
        fi
        return 1
    fi
}

# Check file is executable
check_executable() {
    local file="$1"
    local name="$2"
    
    if [[ -x "$file" ]]; then
        if [[ "$JSON" == "true" ]]; then
            echo "  \"$name\": { \"executable\": true, \"path\": \"$file\" }"
        else
            success "$name: Executable ($file)"
        fi
        return 0
    else
        if [[ "$JSON" == "true" ]]; then
            echo "  \"$name\": { \"executable\": false, \"path\": \"$file\" }"
        else
            warn "$name: NOT executable ($file)"
        fi
        return 1
    fi
}

# =============================================================================
# SYSTEM INFORMATION
# =============================================================================

show_system_info() {
    log "Gathering system information..."
    
    if [[ "$JSON" == "true" ]]; then
        echo "{"
        echo "  \"system_info\": {"
    fi
    
    section "SYSTEM INFORMATION"
    
    # OS
    if [[ "$JSON" == "true" ]]; then
        echo "    \"os\": \"$(uname -s 2>/dev/null || echo 'unknown')\","
    else
        info "Operating System: $(uname -s) $(uname -r) $(uname -m)"
    fi
    
    # Kernel
    if [[ "$JSON" == "true" ]]; then
        echo "    \"kernel\": \"$(uname -r 2>/dev/null || echo 'unknown')\","
    else
        info "Kernel: $(uname -r)"
    fi
    
    # Architecture
    if [[ "$JSON" == "true" ]]; then
        echo "    \"architecture\": \"$(uname -m 2>/dev/null || echo 'unknown')\","
    else
        info "Architecture: $(uname -m)"
    fi
    
    # Hostname
    if [[ "$JSON" == "true" ]]; then
        echo "    \"hostname\": \"$(hostname 2>/dev/null || echo 'unknown')\","
    else
        info "Hostname: $(hostname)"
    fi
    
    # CPU Info
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | xargs)
        local cpu_cores=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo)
        local cpu_flags=$(grep -m1 "flags" /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | xargs)
        
        if [[ "$JSON" == "true" ]]; then
            echo "    \"cpu\": {"
            echo "      \"model\": \"$cpu_model\","
            echo "      \"cores\": $cpu_cores,"
            echo "      \"flags\": \"$cpu_flags\""
            echo "    },"
        else
            info "CPU: $cpu_model ($cpu_cores cores)"
            info "CPU Flags: $cpu_flags"
        fi
    fi
    
    # Memory
    if [[ "$JSON" == "true" ]]; then
        local total_mem=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
        local available_mem=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
        echo "    \"memory\": {"
        echo "      \"total_kb\": $total_mem,"
        echo "      \"available_kb\": $available_mem"
        echo "    },"
    else
        local total_mem_gb=$(( $(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0") / 1048576 ))
        local available_mem_gb=$(( $(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0") / 1048576 ))
        info "Memory: ${total_mem_gb}GB total, ${available_mem_gb}GB available"
    fi
    
    # Disk Space
    if [[ "$JSON" == "true" ]]; then
        local disk_usage=$(df -k "$RUNTIME_ROOT" 2>/dev/null | tail -1 | awk '{print $4}')
        local disk_total=$(df -k "$RUNTIME_ROOT" 2>/dev/null | tail -1 | awk '{print $2}')
        echo "    \"disk\": {"
        echo "      \"total_kb\": $disk_total,"
        echo "      \"available_kb\": $disk_usage"
        echo "    }"
    else
        local disk_usage_gb=$(( $(df -k "$RUNTIME_ROOT" 2>/dev/null | tail -1 | awk '{print $4}') / 1048576 ))
        local disk_total_gb=$(( $(df -k "$RUNTIME_ROOT" 2>/dev/null | tail -1 | awk '{print $2}') / 1048576 ))
        info "Disk: ${disk_usage_gb}GB available (${disk_total_gb}GB total)"
    fi
    
    if [[ "$JSON" == "true" ]]; then
        echo "  },"
    fi
    
    section "HEMLOCK CONFIGURATION"
    
    if [[ "$JSON" == "true" ]]; then
        echo "  \"hemlock\": {"
        echo "    \"runtime_root\": \"$RUNTIME_ROOT\","
        echo "    \"version\": \"$(get_version)\","
    else
        info "Runtime Root: $RUNTIME_ROOT"
        info "Hemlock Version: $(get_version)"
    fi
    
    # Check initialization status
    if [[ -f "$FIRST_RUN_FLAG" ]]; then
        if [[ "$JSON" == "true" ]]; then
            echo "    \"initialized\": true,"
        else
            info "Initialization Status: ✓ Initialized"
        fi
    else
        if [[ "$JSON" == "true" ]]; then
            echo "    \"initialized\": false,"
        else
            info "Initialization Status: ✗ Not initialized"
        fi
    fi
    
    if [[ "$JSON" == "true" ]]; then
        echo "    \"first_run_flag\": \"$FIRST_RUN_FLAG\""
        echo "  }"
        echo "}"
    fi
}

# Get Hemlock version
get_version() {
    if [[ -f "$RUNTIME_ROOT/VERSION" ]]; then
        cat "$RUNTIME_ROOT/VERSION"
    elif [[ -f "$RUNTIME_ROOT/.git/HEAD" ]]; then
        git -C "$RUNTIME_ROOT" describe --tags --always 2>/dev/null || git -C "$RUNTIME_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown"
    else
        echo "dev-$(date +%Y%m%d)"
    fi
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================

run_health_checks() {
    log "Running health checks..."
    section "HEALTH CHECKS"
    
    local checks_passed=0
    local checks_total=0
    
    if [[ "$JSON" == "true" ]]; then
        echo "{"
        echo "  \"health_checks\": {"
    fi
    
    # Check directory structure
    checks_total=$((checks_total + 1))
    log "Checking directory structure..."
    
    local dirs=(
        "$RUNTIME_ROOT"
        "$AGENTS_DIR"
        "$CONFIG_DIR"
        "$SCRIPTS_DIR"
        "$CACHE_DIR"
        "$MODELS_DIR"
        "$LOGS_DIR"
    )
    
    local dirs_passed=0
    for dir in "${dirs[@]}"; do
        if check_dir "$dir" "$(basename "$dir")" >/dev/null 2>&1; then
            dirs_passed=$((dirs_passed + 1))
        fi
    done
    
    local all_dirs_ok=true
    if [[ $dirs_passed -eq ${#dirs[@]} ]]; then
        if [[ "$JSON" == "false" ]]; then
            success "Directory Structure: All directories exist"
        fi
        checks_passed=$((checks_passed + 1))
    else
        if [[ "$JSON" == "false" ]]; then
            warn "Directory Structure: $(( ${#dirs[@]} - dirs_passed )) directories missing"
        fi
        checks_total=$((checks_total - 1))
    fi
    
    # Check critical files
    checks_total=$((checks_total + 1))
    log "Checking critical files..."
    
    local files=(
        "$SCRIPTS_DIR/system/hardware-scanner.sh"
        "$SCRIPTS_DIR/system/llama-build.sh"
        "$SCRIPTS_DIR/system/model-manager.sh"
        "$SCRIPTS_DIR/system/first-run.sh"
        "$RUNTIME_ROOT/runtime.sh"
    )
    
    local files_passed=0
    for file in "${files[@]}"; do
        if check_file "$file" "$(basename "$file")" >/dev/null 2>&1; then
            files_passed=$((files_passed + 1))
        fi
    done
    
    if [[ $files_passed -eq ${#files[@]} ]]; then
        if [[ "$JSON" == "false" ]]; then
            success "Critical Files: All critical files exist"
        fi
        checks_passed=$((checks_passed + 1))
    else
        if [[ "$JSON" == "false" ]]; then
            warn "Critical Files: $(( ${#files[@]} - files_passed )) files missing"
        fi
        checks_total=$((checks_total - 1))
    fi
    
    # Check dependencies
    checks_total=$((checks_total + 1))
    log "Checking required dependencies..."
    
    local deps=(
        "git:git"
        "make:make"
        "gcc:gcc"
        "cmake:cmake"
        "python3:python3"
        "jq:jq"
    )
    
    local deps_passed=0
    for dep in "${deps[@]}"; do
        local name="${dep%%:*}"
        local cmd="${dep##*:}"
        if command -v "$cmd" &>/dev/null; then
            deps_passed=$((deps_passed + 1))
        fi
    done
    
    if [[ $deps_passed -eq ${#deps[@]} ]]; then
        if [[ "$JSON" == "false" ]]; then
            success "Dependencies: All required dependencies found"
        fi
        checks_passed=$((checks_passed + 1))
    else
        if [[ "$JSON" == "false" ]]; then
            warn "Dependencies: $(( ${#deps[@]} - deps_passed )) dependencies missing"
        fi
        checks_total=$((checks_total - 1))
    fi
    
    # Check initialization
    checks_total=$((checks_total + 1))
    log "Checking initialization..."
    
    if [[ -f "$FIRST_RUN_FLAG" ]]; then
        if [[ "$JSON" == "false" ]]; then
            success "Initialization: System initialized"
        fi
        checks_passed=$((checks_passed + 1))
    else
        if [[ "$JSON" == "false" ]]; then
            warn "Initialization: System not initialized (run ./runtime.sh initialize)"
        fi
        checks_total=$((checks_total - 1))
    fi
    
    # Check default model
    checks_total=$((checks_total + 1))
    log "Checking default model..."
    
    if [[ -f "$MODELS_DIR/gguf/qwen3-0_6b-Q4_K_M.gguf" ]] || \
       [[ -f "$MODELS_DIR/gguf/qwen3-0_6b-Q4_K_M.gguf" ]]; then
        if [[ "$JSON" == "false" ]]; then
            success "Default Model: Qwen3-0.6B model found"
        fi
        checks_passed=$((checks_passed + 1))
    else
        if [[ "$JSON" == "false" ]]; then
            warn "Default Model: Qwen3-0.6B model not found"
        fi
        checks_total=$((checks_total - 1))
    fi
    
    # Check Llama.cpp
    checks_total=$((checks_total + 1))
    log "Checking Llama.cpp..."
    
    if [[ -f "$RUNTIME_ROOT/bin/llama-cli" ]] || command -v llama-cli &>/dev/null; then
        if [[ "$JSON" == "false" ]]; then
            success "Llama.cpp: Binary found"
        fi
        checks_passed=$((checks_passed + 1))
    else
        if [[ "$JSON" == "false" ]]; then
            warn "Llama.cpp: Binary not found"
        fi
        checks_total=$((checks_total - 1))
    fi
    
    # Check agents
    checks_total=$((checks_total + 1))
    log "Checking agents..."
    
    local agent_count=$(find "$AGENTS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l)
    if [[ $agent_count -gt 1 ]]; then
        local agents_with_config=0
        for agent_dir in "$AGENTS_DIR"/*/; do
            if [[ -f "$agent_dir/agent.json" ]]; then
                agents_with_config=$((agents_with_config + 1))
            fi
        done
        
        if [[ $agents_with_config -gt 0 ]]; then
            if [[ "$JSON" == "false" ]]; then
                success "Agents: $agents_with_config agents configured"
            fi
            checks_passed=$((checks_passed + 1))
        else
            if [[ "$JSON" == "false" ]]; then
                warn "Agents: No agents with valid configuration"
            fi
            checks_total=$((checks_total - 1))
        fi
    else
        if [[ "$JSON" == "false" ]]; then
            warn "Agents: No agents found"
        fi
        checks_total=$((checks_total - 1))
    fi
    
    # Calculate health score
    local health_score=0
    if [[ $checks_total -gt 0 ]]; then
        health_score=$(( (checks_passed * 100) / checks_total ))
    fi
    
    if [[ "$JSON" == "true" ]]; then
        echo "    \"score\": $health_score"
        echo "  },"
        echo "  \"passed\": $checks_passed,"
        echo "  \"failed\": $((checks_total - checks_passed))"
        echo "}"
    else
        echo ""
        info "Health Score: ${health_score}% ($checks_passed/$checks_total checks passed)"
        
        if [[ $health_score -ge 90 ]]; then
            success "System Health: Excellent"
        elif [[ $health_score -ge 70 ]]; then
            info "System Health: Good"
        elif [[ $health_score -ge 50 ]]; then
            warn "System Health: Fair"
        else
            error "System Health: Poor - Attention required"
        fi
    fi
    
    return $((checks_passed < checks_total ? 1 : 0))
}

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================

check_dependencies() {
    section "DEPENDENCY CHECKS"
    
    if [[ "$JSON" == "true" ]]; then
        echo "{"
        echo "  \"dependencies\": {"
    fi
    
    # Categorized dependencies
    declare -A categories=(
        ["Build Tools"]="git make cmake"
        ["Compilers"]="gcc g++ clang clang++"
        ["Python"]="python3 python3-pip python3-venv"
        ["Utilities"]="jq curl wget tar gzip"
        ["Optional"]="huggingface-cli git-lfs docker"
    )
    
    local total_deps=0
    local found_deps=0
    
    for category in "${!categories[@]}"; do
        if [[ "$JSON" == "false" ]]; then
            echo ""
            info "$category:"
        else
            echo "    \"$category\": {"
        fi
        
        for cmd in ${categories[$category]}; do
            total_deps=$((total_deps + 1))
            if command -v "$cmd" &>/dev/null; then
                found_deps=$((found_deps + 1))
                if [[ "$JSON" == "true" ]]; then
                    echo "      \"$cmd\": true"
                else
                    success "  $cmd: Found"
                fi
            else
                if [[ "$JSON" == "true" ]]; then
                    echo "      \"$cmd\": false"
                else
                    warn "  $cmd: NOT FOUND"
                fi
            fi
        done
        
        if [[ "$JSON" == "true" ]]; then
            echo "    },"
        fi
    done
    
    local deps_pct=0
    if [[ $total_deps -gt 0 ]]; then
        deps_pct=$(( (found_deps * 100) / total_deps ))
    fi
    
    if [[ "$JSON" == "true" ]]; then
        sed -i '$ s/,$//' "$file" 2>/dev/null || true
        echo "  },"
        echo "  \"summary\": {"
        echo "    \"total\": $total_deps,"
        echo "    \"found\": $found_deps,"
        echo "    \"percentage\": $deps_pct"
        echo "  }"
        echo "}"
    else
        echo ""
        info "Dependencies: $found_deps/$total_deps found ($deps_pct%)"
        
        if [[ $deps_pct -ge 90 ]]; then
            success "Dependency Status: Excellent"
        elif [[ $deps_pct -ge 70 ]]; then
            info "Dependency Status: Good"
        elif [[ $deps_pct -ge 50 ]]; then
            warn "Dependency Status: Fair"
        else
            error "Dependency Status: Poor - Many dependencies missing"
        fi
    fi
    
    return $((found_deps < total_deps ? 1 : 0))
}

# =============================================================================
# CONFIGURATION CHECKS
# =============================================================================

check_configuration() {
    section "CONFIGURATION CHECKS"
    
    if [[ "$JSON" == "true" ]]; then
        echo "{"
        echo "  \"configuration\": {"
    fi
    
    local configs=(
        "$CONFIG_DIR/runtime.yaml:runtime.yaml"
        "$CONFIG_DIR/gateway.yaml:gateway.yaml"
        "$PERSISTENT_CONFIG:model-config.yaml"
        "$RUNTIME_ROOT/.env:.env"
    )
    
    local found_configs=0
    local total_configs=${#configs[@]}
    
    for config in "${configs[@]}"; do
        local file="${config%%:*}"
        local name="${config##*:}"
        
        if check_file "$file" "$name" >/dev/null 2>&1; then
            found_configs=$((found_configs + 1))
            
            # Validate YAML files
            if [[ "$name" == *.yaml ]] && command -v jq &>/dev/null; then
                if jq empty "$file" 2>/dev/null; then
                    if [[ "$JSON" == "false" ]]; then
                        success "  $name: Valid YAML"
                    fi
                else
                    if [[ "$JSON" == "false" ]]; then
                        warn "  $name: Invalid YAML syntax"
                    fi
                fi
            fi
        fi
    done
    
    local configs_pct=0
    if [[ $total_configs -gt 0 ]]; then
        configs_pct=$(( (found_configs * 100) / total_configs ))
    fi
    
    if [[ "$JSON" == "true" ]]; then
        echo "    \"found\": $found_configs,"
        echo "    \"total\": $total_configs,"
        echo "    \"percentage\": $configs_pct"
        echo "  }"
        echo "}"
    else
        echo ""
        info "Configuration Files: $found_configs/$total_configs found ($configs_pct%)"
        
        if [[ $configs_pct -eq 100 ]]; then
            success "Configuration Status: All files present"
        elif [[ $configs_pct -ge 75 ]]; then
            info "Configuration Status: Most files present"
        else
            warn "Configuration Status: Some files missing"
        fi
    fi
    
    return $((found_configs < total_configs ? 1 : 0))
}

# =============================================================================
# MODEL CHECKS
# =============================================================================

check_models() {
    section "MODEL CHECKS"
    
    if [[ "$JSON" == "true" ]]; then
        echo "{"
        echo "  \"models\": {"
    fi
    
    # Check if models directory exists
    local has_models_dir=false
    if check_dir "$MODELS_DIR" "Models Directory" >/dev/null 2>&1; then
        has_models_dir=true
    fi
    
    local model_count=0
    local gguf_count=0
    local hf_count=0
    
    if [[ "$has_models_dir" == true ]]; then
        # Count GGUF models
        if [[ -d "$MODELS_DIR/gguf" ]]; then
            gguf_count=$(find "$MODELS_DIR/gguf" -name "*.gguf" -type f 2>/dev/null | wc -l || echo "0")
        fi
        
        # Count HuggingFace models
        if [[ -d "$MODELS_DIR/huggingface" ]]; then
            hf_count=$(find "$MODELS_DIR/huggingface" -maxdepth 2 -type d 2>/dev/null | wc -l || echo "0")
            hf_count=$((hf_count - 1))  # Subtract the directory itself
        fi
        
        model_count=$((gguf_count + hf_count))
    fi
    
    if [[ "$JSON" == "true" ]]; then
        echo "    \"models_directory\": $has_models_dir,"
        echo "    \"gguf_models\": $gguf_count,"
        echo "    \"huggingface_models\": $hf_count,"
        echo "    \"total_models\": $model_count"
    else
        info "Models Directory: $( [[ "$has_models_dir" == true ]] && echo "Found" || echo "NOT FOUND")"
        info "GGUF Models: $gguf_count"
        info "HuggingFace Models: $hf_count"
        info "Total Models: $model_count"
    fi
    
    # Check default model
    local default_model_found=false
    for pattern in "qwen3-0_6b-Q4_K_M.gguf" "qwen3-0_6b-Q4_K_M.gguf"; do
        if find "$MODELS_DIR" -name "$pattern" -type f 2>/dev/null; then
            default_model_found=true
            break
        fi
    done
    
    if [[ "$default_model_found" == true ]]; then
        if [[ "$JSON" == "true" ]]; then
            echo "    \"default_model\": true"
        else
            success "Default Model: Qwen3-0.6B found"
        fi
    else
        if [[ "$JSON" == "true" ]]; then
            echo "    \"default_model\": false"
        else
            warn "Default Model: Qwen3-0.6B NOT FOUND"
        fi
    fi
    
    if [[ "$JSON" == "true" ]]; then
        echo "  }"
        echo "}"
    fi
    
    return $((default_model_found == false ? 1 : 0))
}

# =============================================================================
# SECURITY CHECKS
# =============================================================================

check_security() {
    section "SECURITY CHECKS"
    
    if [[ "$JSON" == "true" ]]; then
        echo "{"
        echo "  \"security\": {"
    fi
    
    local security_passed=0
    local security_total=0
    
    # Check for secrets in git (should not be committed)
    security_total=$((security_total + 1))
    log "Checking for secrets in git..."
    
    if [[ -d "$RUNTIME_ROOT/.git" ]]; then
        # Check for common secret patterns
        local secret_patterns=(
            "api[_-]?key"
            "secret"
            "password"
            "token"
            "\.enc$"
            "private[_-]?key"
        )
        
        local secrets_found=0
        for pattern in "${secret_patterns[@]}"; do
            if git -C "$RUNTIME_ROOT" grep -l -i "$pattern" 2>/dev/null | grep -v "\.git" >/dev/null; then
                secrets_found=$((secrets_found + 1))
                warn "  Found potential secret: $pattern"
            fi
        done
        
        if [[ $secrets_found -eq 0 ]]; then
            if [[ "$JSON" == "false" ]]; then
                success "No secrets found in git"
            fi
            security_passed=$((security_passed + 1))
        else
            if [[ "$JSON" == "false" ]]; then
                error "Found $secrets_found potential secrets in git"
            fi
        fi
    else
        if [[ "$JSON" == "false" ]]; then
            warn "Not a git repository, cannot check for secrets"
        fi
        security_total=$((security_total - 1))
    fi
    
    # Check file permissions
    security_total=$((security_total + 1))
    log "Checking file permissions..."
    
    local perms_ok=true
    
    # Check sensitive files
    local sensitive_files=(
        "$CACHE_DIR/hardware-scan.json"
        "$SCAN_RESULTS"
        "$RECOMMENDATIONS"
    )
    
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            local perms=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%p' "$file" 2>/dev/null || echo "000")
            # Check if readable by others
            if [[ "$perms" == *"[2367]"* ]]; then
                warn "  $file has world-readable permissions: $perms"
                perms_ok=false
            fi
        fi
    done
    
    if [[ "$perms_ok" == true ]]; then
        if [[ "$JSON" == "false" ]]; then
            success "File permissions: OK"
        fi
        security_passed=$((security_passed + 1))
    else
        if [[ "$JSON" == "false" ]]; then
            warn "File permissions: Some files have loose permissions"
        fi
    fi
    
    # Check environment variables
    security_total=$((security_total + 1))
    log "Checking environment..."
    
    # Check if we're running as root
    if [[ "$(whoami)" == "root" ]]; then
        if [[ "$JSON" == "false" ]]; then
            warn "Running as root (not recommended for security)"
        fi
    else
        if [[ "$JSON" == "false" ]]; then
            success "Not running as root"
        fi
        security_passed=$((security_passed + 1))
    fi
    
    # Calculate security score
    local security_score=0
    if [[ $security_total -gt 0 ]]; then
        security_score=$(( (security_passed * 100) / security_total ))
    fi
    
    if [[ "$JSON" == "true" ]]; then
        echo "    \"score\": $security_score"
        echo "  }"
        echo "}"
    else
        echo ""
        info "Security Score: ${security_score}% ($security_passed/$security_total checks passed)"
        
        if [[ $security_score -ge 90 ]]; then
            success "Security Status: Excellent"
        elif [[ $security_score -ge 70 ]]; then
            info "Security Status: Good"
        elif [[ $security_score -ge 50 ]]; then
            warn "Security Status: Fair"
        else
            error "Security Status: Poor - Security review recommended"
        fi
    fi
    
    return $((security_passed < security_total ? 1 : 0))
}

# =============================================================================
# SERVICE CHECKS
# =============================================================================

check_services() {
    section "SERVICE CHECKS"
    
    if [[ "$JSON" == "true" ]]; then
        echo "{"
        echo "  \"services\": {"
    fi
    
    local services_ok=0
    local services_total=0
    
    # Check for running processes
    local processes=(
        "llama-cli:Llama.cpp CLI"
        "llama-server:Llama.cpp Server"
        "python3:Python"
    )
    
    for proc in "${processes[@]}"; do
        local cmd="${proc%%:*}"
        local name="${proc##*:}"
        services_total=$((services_total + 1))
        
        if pgrep -f "$cmd" &>/dev/null; then
            if [[ "$JSON" == "true" ]]; then
                echo "    \"$name\": true"
            else
                success "$name: Running"
            fi
            services_ok=$((services_ok + 1))
        else
            if [[ "$JSON" == "true" ]]; then
                echo "    \"$name\": false"
            else
                info "$name: Not running"
            fi
        fi
    done
    
    # Check for Docker containers
    if command -v docker &>/dev/null; then
        services_total=$((services_total + 1))
        local running_containers=$(docker ps 2>/dev/null | wc -l || echo "0")
        running_containers=$((running_containers - 1))  # Subtract header
        
        if [[ $running_containers -gt 0 ]]; then
            if [[ "$JSON" == "true" ]]; then
                echo "    \"Docker Containers\": { \"count\": $running_containers }"
            else
                success "Docker Containers: $running_containers running"
            fi
            services_ok=$((services_ok + 1))
        else
            if [[ "$JSON" == "false" ]]; then
                info "Docker Containers: None running"
            fi
        fi
    fi
    
    if [[ "$JSON" == "true" ]]; then
        echo "    \"summary\": {"
        echo "      \"running\": $services_ok,"
        echo "      \"total\": $services_total"
        echo "    }"
        echo "  }"
        echo "}"
    else
        echo ""
        info "Services: $services_ok/$services_total running"
    fi
    
    return $((services_ok < services_total ? 1 : 0))
}

# =============================================================================
# TROUBLESHOOTING ASSISTANT
# =============================================================================

interactive_troubleshoot() {
    section "INTERACTIVE TROUBLESHOOTING"
    info "Answer the following questions to diagnose issues"
    echo ""
    
    PS3="Select an issue to troubleshoot: "
    options=(
        "Cannot run initialization"
        "Hardware not detected correctly"
        "Llama.cpp build failing"
        "Model download/conversion failing"
        "Agent not working"
        "Memory/performance issues"
        "Permission errors"
        "Exit"
    )
    
    select opt in "${options[@]}"; do
        case "$opt" in
            "Cannot run initialization")
                troubleshoot_initialization
                ;;
            "Hardware not detected correctly")
                troubleshoot_hardware
                ;;
            "Llama.cpp build failing")
                troubleshoot_build
                ;;
            "Model download/conversion failing")
                troubleshoot_model
                ;;
            "Agent not working")
                troubleshoot_agent
                ;;
            "Memory/performance issues")
                troubleshoot_performance
                ;;
            "Permission errors")
                troubleshoot_permissions
                ;;
            "Exit")
                info "Exiting troubleshooting"
                break
                ;;
            *)
                info "Invalid option: $opt"
                ;;
        esac
    done
}

troubleshoot_initialization() {
    info "Troubleshooting: Cannot run initialization"
    echo ""
    
    info "Checking first-run flag..."
    if [[ -f "$FIRST_RUN_FLAG" ]]; then
        info "  First-run flag exists: $(cat "$FIRST_RUN_FLAG")"
        info "  Solution: Run with --force flag to re-initialize, or remove the flag first"
    else
        info "  First-run flag NOT found"
    fi
    
    echo ""
    info "Checking for initialization scripts..."
    for script in \
        "$SCRIPTS_DIR/system/first-run.sh" \
        "$SCRIPTS_DIR/system/hardware-scanner.sh" \
        "$SCRIPTS_DIR/system/llama-build.sh" \
        "$SCRIPTS_DIR/system/model-manager.sh"; do
        
        if [[ -f "$script" ]]; then
            info "  ✓ $(basename "$script") exists"
        else
            error "  ✗ $(basename "$script") NOT FOUND"
            info "    Solution: Ensure all system scripts are present"
        fi
    done
    
    echo ""
    info "Checking required directories..."
    for dir in "$CACHE_DIR" "$CONFIG_DIR" "$MODELS_DIR" "$AGENTS_DIR"; do
        if [[ -d "$dir" ]]; then
            info "  ✓ $(basename "$dir") exists"
        else
            warn "  ✗ $(basename "$dir") NOT FOUND"
            info "    Solution: Create directory or run ./runtime.sh setup"
        fi
    done
    
    echo ""
    info "Common solutions:"
    info "  1. Ensure all system scripts exist in $SCRIPTS_DIR/system/"
    info "  2. Ensure required dependencies are installed (git, make, cmake, gcc, jq)"
    info "  3. Check disk space with 'df -h'"
    info "  4. Check permissions with 'ls -la $SCRIPTS_DIR/system/'"
    info "  5. Run with verbose logging: ./runtime.sh initialize --verbose"
    info "  6. Remove $FIRST_RUN_FLAG and try again"
    
    echo ""
}

troubleshoot_hardware() {
    info "Troubleshooting: Hardware not detected correctly"
    echo ""
    
    info "Running hardware scan..."
    if [[ -f "$SCRIPTS_DIR/system/hardware-scanner.sh" ]]; then
        bash "$SCRIPTS_DIR/system/hardware-scanner.sh" --dry-run
    else
        error "Hardware scanner not found"
    fi
    
    echo ""
    info "Common issues:"
    info "  - On Linux: /proc/cpuinfo and /etc/os-release must be readable"
    info "  - On macOS: sysctl must be available"
    info "  - For NVIDIA: nvidia-smi must be installed"
    info "  - For AMD: rocminfo must be available"
    info "  - For Vulkan: vulkaninfo must be installed"
    
    echo ""
    info "Manual detection:"
    info "  OS: $(uname -s)"
    info "  Architecture: $(uname -m)"
    info "  CPU Cores: $(nproc 2>/dev/null || echo "unknown")"
    info "  Total Memory: $(free -h 2>/dev/null | head -2 | tail -1 | awk '{print $2}' || echo "unknown")"
    
    echo ""
}

troubleshoot_build() {
    info "Troubleshooting: Llama.cpp build failing"
    echo ""
    
    info "Checking build dependencies..."
    local deps=("git" "make" "cmake" "g++" "clang" "python3")
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &>/dev/null; then
            info "  ✓ $dep found"
        else
            warn "  ✗ $dep NOT FOUND"
            info "    Install: On Ubuntu/Debian: sudo apt-get install -y $dep"
        fi
    done
    
    echo ""
    info "Checking build directory..."
    local build_dir="$CACHE_DIR/llama.cpp"
    if [[ -d "$build_dir" ]]; then
        info "  ✓ Build directory exists: $build_dir"
        info "    Contents: $(ls "$build_dir" 2>/dev/null | head -5 | tr '\n' ' ')"
    else
        info "  ✗ Build directory NOT FOUND"
        info "    This will be created during build"
    fi
    
    echo ""
    info "Common build issues:"
    info "  1. Missing C++ compiler (g++ or clang)"
    info "  2. CMake version too old (need >= 3.10)"
    info "  3. Insufficient memory for build process"
    info "  4. Missing development libraries"
    info "  5. Git clone failed (network issues)"
    info "  6. CUDA/ROCm not properly installed"
    
    echo ""
    info "Solutions:"
    info "  1. Install build essentials:"
    info "     Ubuntu: sudo apt-get install -y build-essential cmake git"
    info "     macOS: brew install cmake git"
    info "  2. Check CMake version: cmake --version"
    info "  3. Free up memory: close other applications"
    info "  4. Try CPU-only build: ./scripts/system/llama-build.sh build-cpu"
    info "  5. Check build logs in $build_dir"
    
    echo ""
}

troubleshoot_model() {
    info "Troubleshooting: Model download/conversion failing"
    echo ""
    
    info "Checking model directory..."
    if [[ -d "$MODELS_DIR/gguf" ]]; then
        local gguf_files=$(find "$MODELS_DIR/gguf" -name "*.gguf" -type f 2>/dev/null | wc -l || echo "0")
        info "  GGUF models found: $gguf_files"
        if [[ $gguf_files -gt 0 ]]; then
            find "$MODELS_DIR/gguf" -name "*.gguf" -type f 2>/dev/null | while read file; do
                info "    - $(basename "$file") ($(stat -c '%s' "$file" 2>/dev/null | numfmt --to=iec || echo "unknown"))"
            done
        fi
    else
        info "  GGUF directory NOT FOUND"
    fi
    
    echo ""
    info "Checking HuggingFace models..."
    if [[ -d "$MODELS_DIR/huggingface" ]]; then
        local hf_dirs=$(find "$MODELS_DIR/huggingface" -maxdepth 2 -type d 2>/dev/null | wc -l || echo "0")
        hf_dirs=$((hf_dirs - 1))
        info "  HuggingFace model directories: $hf_dirs"
        if [[ $hf_dirs -gt 0 ]]; then
            find "$MODELS_DIR/huggingface" -maxdepth 2 -type d 2>/dev/null | grep -v "^$MODELS_DIR/huggingface$" | while read dir; do
                info "    - $(basename "$dir")"
            done
        fi
    else
        info "  HuggingFace directory NOT FOUND"
    fi
    
    echo ""
    info "Checking download tools..."
    local tools=("huggingface-cli" "git" "python3")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            info "  ✓ $tool available"
        else
            warn "  ✗ $tool NOT FOUND"
        fi
    done
    
    echo ""
    info "Common download issues:"
    info "  1. No internet connectivity"
    info "  2. HuggingFace Hub rate limiting"
    info "  3. Large file download timeout"
    info "  4. Git LFS not configured"
    info "  5. Insufficient disk space"
    
    echo ""
    info "Solutions:"
    info "  1. Check internet: ping -c 3 huggingface.co"
    info "  2. Install huggingface-cli: pip3 install -U huggingface-hub"
    info "  3. Configure Git LFS: git lfs install"
    info "  4. Increase timeout: export HF_HUB_DOWNLOAD_TIMEOUT=3600"
    info "  5. Download manually: https://huggingface.co/Qwen/Qwen3-0.6B"
    info "  6. Use --dry-run to test download without executing"
    
    echo ""
}

troubleshoot_agent() {
    info "Troubleshooting: Agent not working"
    echo ""
    
    info "Listing agents..."
    if [[ -d "$AGENTS_DIR" ]]; then
        local agent_count=$(find "$AGENTS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l || echo "0")
        agent_count=$((agent_count - 1))
        info "  Agents found: $agent_count"
        
        if [[ $agent_count -gt 0 ]]; then
            info "  Agent directories:"
            for agent_dir in "$AGENTS_DIR"/*/; do
                local agent_name=$(basename "$agent_dir")
                if [[ -f "$agent_dir/agent.json" ]]; then
                    info "    ✓ $agent_name (has config)"
                else
                    warn "    ✗ $agent_name (missing config)"
                fi
            done
        fi
    else
        info "  No agents directory found"
    fi
    
    echo ""
    info "Checking default/active agents..."
    check_dir "$AGENTS_DIR/helper" "Helper Agent"
    check_dir "$AGENTS_DIR/default" "Default Agent"
    
    echo ""
    info "Common agent issues:"
    info "  1. Agent configuration file (agent.json) missing"
    info "  2. Model path in configuration is incorrect"
    info "  3. Required memory files (SOUL.md, USER.md) missing"
    info "  4. Agent not marked as enabled/active"
    info "  5. Model file not found at configured path"
    
    echo ""
    info "Solutions:"
    info "  1. Verify agent.json exists and is valid JSON"
    info "  2. Check model path: 'model' field in agent.json"
    info "  3. Run memory injection: ./runtime.sh inject-all-memory"
    info "  4. Verify model file exists: ls -la models/gguf/"
    info "  5. Set agent as active: edit agent.json and set \"active\": true"
    
    echo ""
}

troubleshoot_performance() {
    info "Troubleshooting: Memory/performance issues"
    echo ""
    
    info "System Memory:"
    free -h 2>/dev/null | while read line; do
        info "  $line"
    done
    
    echo ""
    info "Disk Space:"
    df -h "$RUNTIME_ROOT" 2>/dev/null | while read line; do
        info "  $line"
    done
    
    echo ""
    info "Memory Usage by Process:"
    ps -eo pid,ppid,cmd,%mem,%cpu --sort=-%mem 2>/dev/null | head -10 | while read line; do
        info "  $line"
    done
    
    echo ""
    info "Largest Files in Hemlock:"
    find "$RUNTIME_ROOT" -type f -exec du -h {} \; 2>/dev/null | sort -rh | head -10
    
    echo ""
    info "Common performance issues:"
    info "  1. Insufficient RAM for model loading"
    info "  2. Insufficient disk space"
    info "  3. Memory leaks in Llama.cpp"
    info "  4. Too many concurrent processes"
    info "  5. Swap thrashing"
    
    echo ""
    info "Solutions:"
    info "  1. Check model size: Qwen3-0.6B needs ~400MB"
    info "  2. Free up memory: close other applications"
    info "  3. Add swap space: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
    info "  4. Use smaller model or lower quantization"
    info "  5. Reduce context size: --ctx-size 1024"
    info "  6. Limit threads: --threads 2"
    
    echo ""
}

troubleshoot_permissions() {
    info "Troubleshooting: Permission errors"
    echo ""
    
    info "Checking directory permissions..."
    local dirs=(
        "$RUNTIME_ROOT"
        "$CACHE_DIR"
        "$CONFIG_DIR"
        "$AGENTS_DIR"
        "$MODELS_DIR"
        "$SCRIPTS_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local perms=$(stat -c '%a' "$dir" 2>/dev/null || stat -f '%p' "$dir" 2>/dev/null || echo "unknown")
            info "  $dir: $perms"
            
            # Check if writable
            if [[ -w "$dir" ]]; then
                success "    [writable]"
            else
                error "    [NOT writable]"
            fi
        fi
    done
    
    echo ""
    info "Checking script permissions..."
    find "$SCRIPTS_DIR" -name "*.sh" -type f 2>/dev/null | while read script; do
        local perms=$(stat -c '%a' "$script" 2>/dev/null || echo "unknown")
        if [[ -x "$script" ]]; then
            success "  $(basename "$script"): $perms (executable)"
        else
            warn "  $(basename "$script"): $perms (NOT executable)"
        fi
    done
    
    echo ""
    info "Checking current user..."
    info "  User: $(whoami)"
    info "  UID: $(id -u)"
    info "  GID: $(id -g)"
    info "  Groups: $(groups)"
    
    echo ""
    info "Common permission issues:"
    info "  1. Scripts not executable"
    info "  2. User doesn't own Hemlock directory"
    info "  3. Parent directory not writable"
    info "  4. Running as non-sudo user"
    info "  5. Docker permissions"
    
    echo ""
    info "Solutions:"
    info "  1. Make scripts executable: chmod +x scripts/system/*.sh"
    info "  2. Take ownership: sudo chown -R \$(whoami):\$(whoami) $RUNTIME_ROOT"
    info "  3. Fix parent directory: chmod +w $RUNTIME_ROOT"
    info "  4. Run with sudo (not recommended for security)"
    info "  5. Add user to docker group: sudo usermod -aG docker \$(whoami)"
    
    echo ""
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

generate_report() {
    section "GENERATING DIAGNOSTIC REPORT"
    
    local report_file="$LOGS_DIR/diagnostic-report-$(date +%Y%m%d-%H%M%S).txt"
    mkdir -p "$LOGS_DIR"
    
    info "Report will be saved to: $report_file"
    info ""
    
    # Redirect all output to file
    {
        echo "Hemlock Diagnostic Report"
        echo "=========================="
        echo "Generated: $(date)"
        echo "Host: $(hostname)"
        echo "User: $(whoami)"
        echo ""
        
        echo "== SYSTEM INFORMATION =="
        show_system_info
        echo ""
        
        echo "== HEALTH CHECKS =="
        run_health_checks
        echo ""
        
        echo "== DEPENDENCY CHECKS =="
        check_dependencies
        echo ""
        
        echo "== CONFIGURATION CHECKS =="
        check_configuration
        echo ""
        
        echo "== MODEL CHECKS =="
        check_models
        echo ""
        
        echo "== SECURITY CHECKS =="
        check_security
        echo ""
        
        echo "== SERVICE CHECKS =="
        check_services
        echo ""
        
        echo "Report generated at: $(date)"
    } > "$report_file" 2>&1
    
    if [[ -f "$report_file" ]]; then
        local report_size=$(stat -c '%s' "$report_file" 2>/dev/null || echo "0")
        success "Report generated: $report_file ($report_size bytes)"
        info ""
        info "Share this file for troubleshooting assistance"
    else
        error "Failed to generate report"
    fi
}

# =============================================================================
# AUTOMATIC FIXES
# =============================================================================

attempt_fixes() {
    section "ATTEMPTING AUTOMATIC FIXES"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry-run mode: showing fixes without applying"
    else
        info "Applying fixes..."
    fi
    
    local fixes_applied=0
    local fixes_skipped=0
    
    # Fix 1: Make scripts executable
    info "Checking script permissions..."
    local scripts_found=0
    local scripts_fixed=0
    
    if [[ -d "$SCRIPTS_DIR/system" ]]; then
        while IFS= read -r script; do
            if [[ -n "$script" ]]; then
                scripts_found=$((scripts_found + 1))
                if [[ ! -x "$script" ]]; then
                    if [[ "$DRY_RUN" == "false" ]]; then
                        chmod +x "$script"
                        scripts_fixed=$((scripts_fixed + 1))
                        success "  Made executable: $(basename "$script")"
                    else
                        info "  Would make executable: $(basename "$script")"
                        scripts_fixed=$((scripts_fixed + 1))
                    fi
                fi
            fi
        done < <(find "$SCRIPTS_DIR" -name "*.sh" -type f 2>/dev/null)
    fi
    
    if [[ $scripts_fixed -gt 0 ]]; then
        fixes_applied=$((fixes_applied + 1))
    fi
    
    # Fix 2: Create required directories
    info "Checking required directories..."
    local dirs=(
        "$CACHE_DIR"
        "$CONFIG_DIR"
        "$AGENTS_DIR"
        "$MODELS_DIR/gguf"
        "$MODELS_DIR/huggingface"
        "$LOGS_DIR"
    )
    
    local dirs_fixed=0
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                mkdir -p "$dir"
                dirs_fixed=$((dirs_fixed + 1))
                success "  Created directory: $dir"
            else
                info "  Would create directory: $dir"
                dirs_fixed=$((dirs_fixed + 1))
            fi
        fi
    done
    
    if [[ $dirs_fixed -gt 0 ]]; then
        fixes_applied=$((fixes_applied + 1))
    fi
    
    # Fix 3: Install missing dependencies
    info "Checking dependencies..."
    local deps_to_install=()
    local deps=("git" "make" "cmake" "g++" "python3" "jq")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            deps_to_install+=("$dep")
        fi
    done
    
    if [[ ${#deps_to_install[@]} -gt 0 ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            info "  Installing missing dependencies: ${deps_to_install[*]}"
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                sudo apt-get update && sudo apt-get install -y "${deps_to_install[*]}" 2>&1 || {
                    warn "  Failed to install dependencies with apt"
                    fixes_skipped=$((fixes_skipped + 1))
                }
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                brew install "${deps_to_install[*]}" 2>&1 || {
                    warn "  Failed to install dependencies with brew"
                    fixes_skipped=$((fixes_skipped + 1))
                }
            else
                warn "  Unsupported OS for automatic dependency installation"
                fixes_skipped=$((fixes_skipped + 1))
            fi
        else
            info "  Would install: ${deps_to_install[*]}"
            fixes_applied=$((fixes_applied + 1))
        fi
    else
        success "  All dependencies are installed"
    fi
    
    echo ""
    info "Fix Summary:"
    info "  Applied: $fixes_applied"
    info "  Skipped: $fixes_skipped"
    
    if [[ $fixes_applied -gt 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
        success "Fixes applied successfully"
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "Dry-run: No changes made"
    else
        info "No fixes needed"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-status}"
    shift
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --verbose|-v)
                VERBOSE="true"
                shift
                ;;
            --json)
                JSON="true"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --category)
                if [[ -n "${2:-}" ]]; then
                    command="$2"
                    shift 2
                else
                    error "Category name required"
                    exit 1
                fi
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # If output is JSON, suppress certain output
    if [[ "$JSON" == "true" ]]; then
        VERBOSE="false"
    fi
    
    case "$command" in
        check)
            run_health_checks
            check_dependencies
            check_configuration
            check_models
            check_security
            check_services
            ;;
        status)
            show_system_info
            run_health_checks
            ;;
        diagnose)
            show_system_info
            run_health_checks
            check_dependencies
            check_models
            ;;
        info)
            show_system_info
            ;;
        services)
            check_services
            ;;
        dependencies)
            check_dependencies
            ;;
        configuration)
            check_configuration
            ;;
        models)
            check_models
            ;;
        security)
            check_security
            ;;
        troubleshoot)
            interactive_troubleshoot
            ;;
        report)
            generate_report
            ;;
        fix)
            attempt_fixes
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Run main
main "$@"
