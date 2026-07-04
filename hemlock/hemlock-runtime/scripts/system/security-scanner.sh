#!/bin/bash
# =============================================================================
# Hemlock Security Scanner
# 
# Comprehensive security scanning for Hemlock Enterprise Agent Framework.
# Scans for vulnerabilities, misconfigurations, and security risks.
# 
# Usage: ./security-scanner.sh [command] [options]
# =============================================================================

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/helpers.sh"

CACHE_DIR="${CACHE_DIR:-$RUNTIME_ROOT/.cache}"
MODELS_DIR="${MODELS_DIR:-$RUNTIME_ROOT/models}"

# Security files
SENSITIVE_FILES=(
    "$CACHE_DIR/hardware-scan.json"
    "$CACHE_DIR/hardware-scan-recommendations.json"
    "$CONFIG_DIR/model-config.yaml"
    "$RUNTIME_ROOT/.env"
    "$AGENTS_DIR/*/.env.enc"
    "$AGENTS_DIR/*/.secrets/*"
)

# Flags
DRY_RUN=false
VERBOSE=false
JSON=false
INTERACTIVE=false
FIX=false

# =============================================================================
# LOGGING
# =============================================================================

log() {
    echo -e "${BLUE}[SECURITY]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[FAIL]${NC} $1" >&2
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
${CYAN}Hemlock Security Scanner${NC}

Comprehensive security scanning for Hemlock Enterprise Agent Framework.
Detects vulnerabilities, misconfigurations, and security risks.

${BLUE}Usage:${NC}
  $0 <command> [options]

${BLUE}Commands:${NC}
  full            Run all security checks
  quick           Quick security scan
  files          Scan file permissions
  secrets        Scan for exposed secrets
  config         Scan configuration files
  network        Scan network configuration
  agents         Scan agent configurations
  audit          Generate security audit report
  fix            Attempt to fix security issues (EXPERIMENTAL)

${BLUE}Options:${NC}
  --dry-run      Show what would be scanned without running
  --verbose, -v  Verbose output
  --json         Output in JSON format
  --interactive  Interactive mode
  --fix          Attempt to fix issues found
  --help, -h     Show this help

${BLUE}Security Checks Performed:${NC}
  ✓ File and directory permissions
  ✓ Sensitive data exposure (secrets, API keys, tokens)
  ✓ Configuration file security
  ✓ Agent security settings
  ✓ Network configuration
  ✓ Environment variables
  ✓ Git repository security
  ✓ Encryption validation

${BLUE}Severity Levels:${NC}
  ${RED}CRITICAL${NC}   - Immediate action required
  ${RED}HAZARD${NC}    - High risk, should fix soon
  ${YELLOW}WARNING${NC}  - Medium risk, review recommended
  ${YELLOW}INFO${NC}     - Low risk, informational
  ${GREEN}PASS${NC}     - No issues found

${BLUE}Examples:${NC}
  $0 full                    # Run all security checks
  $0 quick                   # Quick scan
  $0 --interactive           # Interactive security review
  $0 --json                  # JSON output for CI
  $0 secrets --dry-run       # Check for secrets without scanning
  $0 audit                   # Generate full security audit
  $0 fix --dry-run           # Show fixes without applying

EOF
}

# =============================================================================
# SECURITY CHECK RESULT HANDLING
# =============================================================================

# Security issue severity levels
SEVERITYCritical=1
SEVERITYHigh=2
SEVERITYMedium=3
SEVERITYLow=4
SEVERITYInfo=5

# Track statistics
declare -A STATS=(
    ["total"]=0
    ["critical"]=0
    ["high"]=0
    ["medium"]=0
    ["low"]=0
    ["info"]=0
    ["pass"]=0
)

# Track findings
declare -a FINDINGS=()

# Record a finding
record_finding() {
    local severity="$1"
    local category="$2"
    local description="$3"
    local solution="${4:-}"
    local file="${5:-}"
    local line="${6:-}"
    
    STATS["total"]=$((STATS["total"] + 1))
    
    case "$severity" in
        "critical") STATS["critical"]=$((STATS["critical"] + 1)) ;;
        "high") STATS["high"]=$((STATS["high"] + 1)) ;;
        "medium") STATS["medium"]=$((STATS["medium"] + 1)) ;;
        "low") STATS["low"]=$((STATS["low"] + 1)) ;;
        "info") STATS["info"]=$((STATS["info"] + 1)) ;;
        "pass") STATS["pass"]=$((STATS["pass"] + 1)) ;;
    esac
    
    FINDINGS+=("${severity}:${category}:${description}:${solution}:${file}:${line}")
    
    if [[ "$JSON" == "false" ]]; then
        local color=""
        local symbol=""
        case "$severity" in
            "critical") color="$RED"; symbol="[CRITICAL]" ;;
            "high") color="$RED"; symbol="[HAZARD]" ;;
            "medium") color="$YELLOW"; symbol="[WARNING]" ;;
            "low") color="$YELLOW"; symbol="[INFO]" ;;
            "pass") color="$GREEN"; symbol="[PASS]" ;;
            "info") color="$CYAN"; symbol="[INFO]" ;;
        esac
        
        echo -e "  ${color}${symbol}${NC} ${category}: ${description}"
        if [[ -n "$solution" ]]; then
            echo -e "      Solution: ${solution}"
        fi
        if [[ -n "$file" ]]; then
            echo -e "      File: ${file}"
            if [[ -n "$line" ]]; then
                echo -e "      Line: ${line}"
            fi
        fi
    fi
    
    if [[ "$JSON" == "true" && "$severity" != "pass" ]]; then
        if [[ -n "${JSON_FINDINGS[*]:-}" ]]; then
            JSON_FINDINGS+=(",")
        fi
        JSON_FINDINGS+=("{\"severity\":\"$severity\",\"category\":\"$category\",\"description\":\"$description\",\"solution\":\"$solution\",\"file\":\"$file\",\"line\":\"$line\"}")
    fi
}

# Print summary
print_security_summary() {
    echo ""
    section "SECURITY SCAN SUMMARY"
    
    if [[ "$JSON" == "true" ]]; then
        echo "{"
        echo "  \"summary\": {"
        echo "    \"total_findings\": ${STATS[total]},"
        echo "    \"critical\": ${STATS[critical]},"
        echo "    \"high\": ${STATS[high]},"
        echo "    \"medium\": ${STATS[medium]},"
        echo "    \"low\": ${STATS[low]},"
        echo "    \"info\": ${STATS[info]},"
        echo "    \"pass\": ${STATS[pass]}"
        echo "  },"
        echo "  \"risk_score\": $(calculate_risk_score)"
        echo "}"
        
        if [[ -n "${JSON_FINDINGS[*]:-}" ]]; then
            echo ","
            echo "  \"findings\": ["
            echo "${JSON_FINDINGS[*]}"
            echo "  ]"
        fi
        echo ""
        return
    fi
    
    info "Total Findings: ${STATS[total]}"
    echo ""
    info "By Severity:"
    
    if [[ ${STATS[critical]} -gt 0 ]]; then
        error "  CRITICAL:  ${STATS[critical]} (Immediate action required)"
    fi
    if [[ ${STATS[high]} -gt 0 ]]; then
        warn "  HAZARD:    ${STATS[high]} (High risk)"
    fi
    if [[ ${STATS[medium]} -gt 0 ]]; then
        warn "  WARNING:   ${STATS[medium]} (Review recommended)"
    fi
    if [[ ${STATS[low]} -gt 0 ]]; then
        info "  INFO:      ${STATS[low]} (Low risk)"
    fi
    if [[ ${STATS[info]} -gt 0 ]]; then
        info "  INFO:      ${STATS[info]} (Informational)"
    fi
    if [[ ${STATS[pass]} -gt 0 ]]; then
        success "  PASS:      ${STATS[pass]} (No issues)"
    fi
    
    echo ""
    local risk_score=$(calculate_risk_score)
    local risk_level=$(get_risk_level "$risk_score")
    
    info "Risk Score: $risk_score/100 ($
    risk_level)"
    echo ""
    
    if [[ "$risk_score" -eq 0 ]]; then
        success "No security issues found!"
        return 0
    elif [[ "$risk_score" -le 30 ]]; then
        success "Low risk - System is secure"
        return 0
    elif [[ "$risk_score" -le 70 ]]; then
        warn "Medium risk - Review warnings"
        return 1
    else
        error "High risk - Immediate action required"
        return 1
    fi
}

# Calculate risk score (0-100)
calculate_risk_score() {
    local score=0
    
    # Critical issues: 20 points each
    score=$((score + STATS[critical] * 20))
    
    # High issues: 10 points each
    score=$((score + STATS[high] * 10))
    
    # Medium issues: 5 points each
    score=$((score + STATS[medium] * 5))
    
    # Low issues: 2 points each
    score=$((score + STATS[low] * 2))
    
    # Cap at 100
    if [[ $score -gt 100 ]]; then
        score=100
    fi
    
    echo $score
}

# Get risk level string
get_risk_level() {
    local score="$1"
    
    if [[ $score -eq 0 ]]; then
        echo "None"
    elif [[ $score -le 30 ]]; then
        echo "Low"
    elif [[ $score -le 60 ]]; then
        echo "Medium"
    elif [[ $score -le 80 ]]; then
        echo "High"
    else
        echo "Critical"
    fi
}

# =============================================================================
# SECURITY CHECKS
# =============================================================================

# Check file permissions
check_file_permissions() {
    section "FILE PERMISSION CHECKS"
    
    # Check sensitive files for loose permissions
    for file in "${SENSITIVE_FILES[@]}"; do
        # Expand glob patterns
        for f in $file; do
            if [[ -f "$f" ]]; then
                local perms=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%p' "$f" 2>/dev/null || echo "000")
                local filename=$(basename "$f")
                local dirname=$(dirname "$f")
                
                # Check if readable by world
                if [[ "$perms" == *"[4567]"* ]]; then
                    # Last digit (others) has read bit
                    local others_perm=${perms: -1}
                    if [[ $((others_perm & 4)) -ne 0 ]]; then
                        record_finding "medium" "File Permissions" \
                            "Sensitive file is world-readable: $f (perms: $perms)" \
                            "Fix permissions: chmod 600 '$f'" \
                            "$f"
                    fi
                fi
                
                # Check if writable by group/others
                if [[ "$perms" != "600" && "$perms" != "400" && "$perms" != "640" ]]; then
                    if [[ $filename == *".json" || $filename == *".yaml" || $filename == *".env" || $filename == *".enc" ]]; then
                        record_finding "low" "File Permissions" \
                            "Sensitive file has loose permissions: $f (perms: $perms)" \
                            "Recommended: chmod 600 '$f' (owner read/write only)" \
                            "$f"
                    fi
                fi
                
                # Check directory permissions
                local dir_perms=$(stat -c '%a' "$dirname" 2>/dev/null || echo "000")
                if [[ "$dir_perms" != "700" && "$dir_perms" != "750" ]]; then
                    record_finding "low" "Directory Permissions" \
                        "Sensitive directory has loose permissions: $dirname (perms: $dir_perms)" \
                        "Recommended: chmod 700 '$dirname'" \
                        "$dirname"
                fi
            fi
        done
    done
    
    # Check for world-writable directories
    find "$RUNTIME_ROOT" -type d -perm -0002 2>/dev/null | grep -v "/\.git/" | while read dir; do
        record_finding "medium" "World-Writable Directory" \
            "Directory is world-writable: $dir" \
            "Fix: chmod o-w '$dir'" \
            "$dir"
    done
    
    # Check for world-readable sensitive files
    find "$RUNTIME_ROOT" -type f \( -name "*secret*" -o -name "*key*" -o -name "*token*" -o -name "*password*" -o -name "*api*" -o -name "*credential*" \) 2>/dev/null | grep -v ".git/" | while read file; do
        local perms=$(stat -c '%a' "$file" 2>/dev/null || echo "000")
        if [[ "$perms" == *"[4567]"* ]]; then
            record_finding "high" "Sensitive File Exposure" \
                "Sensitive file is potentially exposed: $file" \
                "Verify file contents and fix permissions: chmod 600 '$file'" \
                "$file"
        fi
    done
    
    # Check for files without owner
    find "$RUNTIME_ROOT" -type f -nouser 2>/dev/null | while read file; do
        record_finding "medium" "Orphaned File" \
            "File has no owner: $file" \
            "Remove or assign ownership: chown \$(whoami):\$(whoami) '$file'" \
            "$file"
    done
    
    # Check for empty passwords in configs
    check_empty_passwords
}

# Check for empty/default passwords
check_empty_passwords() {
    local config_files=(
        "$RUNTIME_ROOT/.env"
        "$CONFIG_DIR/runtime.yaml"
        "$CONFIG_DIR/gateway.yaml"
        "$PERSISTENT_CONFIG"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            # Look for sensitive keys
            local sensitive_keys=(
                "password"
                "token"
                "secret"
                "key"
                "credential"
                "API_KEY"
                "AUTH_TOKEN"
                "ACCESS_TOKEN"
            )
            
            for key in "${sensitive_keys[@]}"; do
                if grep -i "${key}:" "$file" 2>/dev/null | grep -i -E "(''|\"\"|null|none|default)" >/dev/null 2>&1; then
                    record_finding "high" "Empty/Weak Credentials" \
                        "Default or empty $key found in $file" \
                        "Set a strong, unique value for $key" \
                        "$file"
                fi
            done
        fi
    done
}

# Check secrets management
check_secrets_management() {
    section "SECRETS MANAGEMENT CHECKS"
    
    # Check if secret tool exists
    if [[ -f "$RUNTIME_ROOT/tools/agent-toolkit/secret.sh" ]]; then
        record_finding "pass" "Secrets Tool" \
            "Secrets management tool is available"
    else
        record_finding "medium" "Secrets Tool" \
            "Secrets management tool not found" \
            "Tool is expected at: $RUNTIME_ROOT/tools/agent-toolkit/secret.sh"
    fi
    
    # Check for encrypted secrets
    local enc_files=$(find "$RUNTIME_ROOT" -name "*.enc" -type f 2>/dev/null | grep -v ".git/" | wc -l || echo "0")
    if [[ $enc_files -gt 0 ]]; then
        record_finding "pass" "Encrypted Secrets" \
            "Found $enc_files encrypted files (good security practice)"
    else
        record_finding "low" "Encrypted Secrets" \
            "No encrypted secrets found (may be OK if no sensitive data stored)" \
            "Consider encrypting sensitive data with tools/agent-toolkit/secret.sh"
    fi
    
    # Check for plaintext secrets in specific files
    local plaintext_secrets=0
    
    # Check agent .env files
    for agent_dir in "$AGENTS_DIR"/*/; do
        if [[ -f "$agent_dir/.env" ]]; then
            if grep -i -E "(api[_-]?key|secret|password|token|[(])[=:]\s*['\"]?[A-Za-z0-9]{32,}['\"]?" \
                "$agent_dir/.env" 2>/dev/null; then
                
                plaintext_secrets=$((plaintext_secrets + 1))
                record_finding "critical" "Plaintext Secrets" \
                    "Potential plaintext secret found in: $agent_dir/.env" \
                    "Encrypt with: tools/agent-toolkit/secret.sh --agent $(basename "$agent_dir") --action set" \
                    "$agent_dir/.env"
            fi
        fi
    done
    
    if [[ $plaintext_secrets -eq 0 ]]; then
        record_finding "pass" "No Plaintext Secrets" \
            "No obvious plaintext secrets found in .env files"
    fi
    
    # Check .gitignore for secrets
    if [[ -f "$RUNTIME_ROOT/.gitignore" ]]; then
        if grep -q "\.enc$" "$RUNTIME_ROOT/.gitignore" && \
           grep -q "secret" "$RUNTIME_ROOT/.gitignore" && \
           grep -q "token" "$RUNTIME_ROOT/.gitignore" && \
           grep -q "key" "$RUNTIME_ROOT/.gitignore"; then
            
            record_finding "pass" "Git Ignore" \
                "Secrets patterns are in .gitignore"
        else
            record_finding "medium" "Git Ignore" \
                ".gitignore may not be protecting all sensitive files" \
                "Add patterns: *.enc, *secret*, *token*, *key*, *.env"
                "$RUNTIME_ROOT/.gitignore"
        fi
    else
        record_finding "medium" "Git Ignore" \
            "No .gitignore file found" \
            "Create .gitignore to prevent committing sensitive files"
            "$RUNTIME_ROOT/.gitignore"
    fi
}

# Check configuration security
check_configuration_security() {
    section "CONFIGURATION SECURITY CHECKS"
    
    # Check runtime.yaml for security settings
    if [[ -f "$CONFIG_DIR/runtime.yaml" ]]; then
        # Check read-only mode
        if grep -q "read_only:\s*true" "$CONFIG_DIR/runtime.yaml" 2>/dev/null; then
            record_finding "pass" "Read-Only Mode" \
                "Read-only mode is enabled (security best practice)"
        else
            record_finding "low" "Read-Only Mode" \
                "Read-only mode is disabled" \
                "Enable in runtime.yaml: read_only: true"
                "$CONFIG_DIR/runtime.yaml"
        fi
        
        # Check cap_drop
        if grep -q "cap_drop:\s*true" "$CONFIG_DIR/runtime.yaml" 2>/dev/null; then
            record_finding "pass" "Capability Dropping" \
                "Capability dropping is enabled"
        else
            record_finding "low" "Capability Dropping" \
                "Capability dropping is disabled" \
                "Enable in runtime.yaml: cap_drop: true"
                "$CONFIG_DIR/runtime.yaml"
        fi
        
        # Check tmpfs
        if grep -q "tmpfs:\s*true" "$CONFIG_DIR/runtime.yaml" 2>/dev/null; then
            record_finding "pass" "TMPFS" \
                "TMPFS is enabled"
        else
            record_finding "low" "TMPFS" \
                "TMPFS is disabled" \
                "Enable in runtime.yaml: tmpfs: true"
                "$CONFIG_DIR/runtime.yaml"
        fi
    else
        record_finding "info" "Runtime Config" \
            "runtime.yaml not found - some security checks skipped"
            "$CONFIG_DIR/runtime.yaml"
    fi
    
    # Check for orphaned agent configuration files
    if [[ -d "$AGENTS_DIR" ]]; then
        for agent_dir in "$AGENTS_DIR"/*/; do
            if [[ ! -f "$agent_dir/agent.json" ]]; then
                record_finding "medium" "Orphaned Agent" \
                    "Agent directory without configuration: $agent_dir" \
                    "Remove unused agent directory or add configuration"
                    "$agent_dir"
            fi
        done
    fi
}

# Check agent security
check_agent_security() {
    section "AGENT SECURITY CHECKS"
    
    if [[ ! -d "$AGENTS_DIR" ]]; then
        record_finding "info" "Agents Directory" \
            "No agents directory - agent security checks skipped"
        return
    fi
    
    local agent_count=$(find "$AGENTS_DIR" -maxdepth 2 -type d 2>/dev/null | wc -l || echo "0")
    agent_count=$((agent_count - 1))
    
    if [[ $agent_count -eq 0 ]]; then
        record_finding "info" "No Agents" \
            "No agents configured - agent security checks skipped"
        return
    fi
    
    for agent_dir in "$AGENTS_DIR"/*/; do
        local agent_name=$(basename "$agent_dir")
        local agent_json="$agent_dir/agent.json"
        
        if [[ ! -f "$agent_json" ]]; then
            continue
        fi
        
        # Parse agent.json (simple parsing, not full JSON)
        while IFS= read -r line; do
            # Check for tools configuration
            if echo "$line" | grep -q "\"tools\""; then
                # Extract tools list
                local tools_line=$(echo "$line" | sed 's/.*\[\(.*\)\].*/\1/')
                
                if [[ "$tools_line" == *"code_execution"* || "$tools_line" == *"bash"* ]]; then
                    record_finding "high" "Dangerous Tools" \
                        "Agent '$agent_name' has dangerous tools (code_execution, bash)" \
                        "Remove or restrict dangerous tools in agent.json" \
                        "$agent_json"
                fi
                
                if [[ "$tools_line" != *"web_browse"* ]] && \
                   [[ ! "$line" =~ (code_execution|file_read|file_write|file_delete|bash) ]]; then
                    # Agent has no web_browse but also no dangerous tools
                    # This might be intentional
                    :
                fi
            fi
            
            # Check for active status
            if echo "$line" | grep -q "\"active\":\s*true"; then
                record_finding "info" "Active Agent" \
                    "Agent '$agent_name' is active" \
                    "" \
                    "$agent_json"
            fi
            
            # Check for enabled status
            if echo "$line" | grep -q "\"enabled\":\s*true"; then
                : # Agent is enabled, which is fine
            fi
            
            # Check for main/default status
            if echo "$line" | grep -q "\"is_default\":\s*true"; then
                record_finding "info" "Default Agent" \
                    "Agent '$agent_name' is default agent" \
                    "" \
                    "$agent_json"
            fi
            
            # Check for system agent
            if echo "$line" | grep -q "\"system_agent\":\s*true"; then
                # System agents should have restricted tools
                if echo "$line" | grep -E "(code_execution|file_read|file_write|file_delete|bash)" >/dev/null; then
                    record_finding "critical" "System Agent Security" \
                        "System agent '$agent_name' has unrestricted tools" \
                        "System agents should only have safe tools (web_browse)" \
                        "$agent_json"
                fi
            fi
            
            # Check for model path
            if echo "$line" | grep -q "\"model\":" || echo "$line" | grep -q "\"path\":"; then
                local model_path=$(echo "$line" | sed 's/.*: *"//' | sed 's/"//')
                if [[ "$model_path" != /* && "$model_path" != models/* ]]; then
                    record_finding "low" "Model Path" \
                        "Agent '$agent_name' has potentially incorrect model path: $model_path" \
                        "Consider using absolute paths or paths relative to RUNTIME_ROOT"
                        "$agent_json"
                fi
            fi
        done < "$agent_json"
    done
}

# Check network security
check_network_security() {
    section "NETWORK SECURITY CHECKS"
    
    # Check gateway configuration
    if [[ -f "$CONFIG_DIR/gateway.yaml" ]]; then
        # Check token
        if grep -q "token:" "$CONFIG_DIR/gateway.yaml" 2>/dev/null; then
            local token=$(grep "token:" "$CONFIG_DIR/gateway.yaml" | head -1 | sed 's/.*: *//' | xargs)
            
            if [[ "$token" == "change_this_to_a_secure_token" || "$token" == "" || "$token" == "null" ]]; then
                record_finding "critical" "Default Gateway Token" \
                    "Gateway is using default or empty token" \
                    "Set a strong token in gateway.yaml: token: <your-secure-token>" \
                    "$CONFIG_DIR/gateway.yaml"
            else
                record_finding "pass" "Gateway Token" \
                    "Gateway token is configured"
            fi
        fi
        
        # Check bind setting
        if grep -q "bind:" "$CONFIG_DIR/gateway.yaml" 2>/dev/null; then
            local bind=$(grep "bind:" "$CONFIG_DIR/gateway.yaml" | head -1 | sed 's/.*: *//' | xargs)
            
            if [[ "$bind" == "lan" ]]; then
                record_finding "info" "Gateway Bind" \
                    "Gateway is bound to LAN (accessible within local network)" \
                    "Consider 'localhost' for local-only access"
                    "$CONFIG_DIR/gateway.yaml"
            elif [[ "$bind" == "localhost" ]]; then
                record_finding "pass" "Gateway Bind" \
                    "Gateway is bound to localhost (local access only)"
            elif [[ "$bind" == "all" || "$bind" == "0.0.0.0" ]]; then
                record_finding "high" "Gateway Bind" \
                    "Gateway is bound to all interfaces (publicly accessible)" \
                    "This may expose your system. Consider 'localhost' or 'lan'" \
                    "$CONFIG_DIR/gateway.yaml"
            fi
        fi
    else
        record_finding "info" "Gateway Config" \
            "gateway.yaml not found - network checks skipped"
            "$CONFIG_DIR/gateway.yaml"
    fi
    
    # Check for open files
    local open_llama=$(lsof -p $$ 2>/dev/null | grep "llama\|model\|gguf" | wc -l || echo "0")
    if [[ $open_llama -gt 0 ]]; then
        record_finding "info" "Open Model Files" \
            "$open_llama model files are currently open by this process"
    fi
}

# Check environment security
check_environment_security() {
    section "ENVIRONMENT SECURITY CHECKS"
    
    # Check current user
    local current_user=$(whoami)
    if [[ "$current_user" == "root" ]]; then
        record_finding "high" "Root User" \
            "Running as root user (not recommended)" \
            "Run as non-root user for better security"
    else
        record_finding "pass" "Non-Root User" \
            "Running as non-root user: $current_user"
    fi
    
    # Check environment variables for secrets
    local env_secrets=0
    local sensitive_vars=(
        "API_KEY"
        "APIKEY"
        "SECRET"
        "TOKEN"
        "PASSWORD"
        "CREDENTIAL"
        "PRIVATE_KEY"
    )
    
    for var in "${sensitive_vars[@]}"; do
        if env | grep -i "^$var=" >/dev/null 2>&1; then
            env_secrets=$((env_secrets + 1))
            record_finding "medium" "Environment Secret" \
                "Potential secret in environment variable: $var" \
                "Remove from environment or use secure secret management" \
                ""
        fi
    done
    
    if [[ $env_secrets -eq 0 ]]; then
        record_finding "pass" "Environment Variables" \
            "No obvious secrets in environment variables"
    fi
    
    # Check umask
    local current_umask=$(umask)
    if [[ "$current_umask" == "0000" || "$current_umask" == "0002" ]]; then
        record_finding "low" "Umask" \
            "Current umask ($current_umask) allows world-readable files by default" \
            "Consider using umask 0077 or 0027 for better security"
    else
        record_finding "pass" "Umask" \
            "Umask is reasonably restrictive: $current_umask"
    fi
}

# Check git security
check_git_security() {
    section "GIT SECURITY CHECKS"
    
    if [[ ! -d "$RUNTIME_ROOT/.git" ]]; then
        record_finding "info" "Git Repository" \
            "Not a git repository - git security checks skipped"
        return
    fi
    
    # Check for secrets in git history
    local secret_patterns=(
        "api[_-]?key"
        "secret"
        "password"
        "token"
        "private[_-]?key"
        "[A-Za-z0-9]{32,}"
    )
    
    local secrets_in_git=0
    for pattern in "${secret_patterns[@]}"; do
        if git -C "$RUNTIME_ROOT" log -I -G"$pattern" --pretty=format:"%H" 2>/dev/null | head -1 >/dev/null 2>&1; then
            secrets_in_git=$((secrets_in_git + 1))
            record_finding "critical" "Git History" \
                "Potential secret found in git history matching: $pattern" \
                "REMOVE IMMEDIATELY: Use git filter-repo or BFG to purge from history" \
                "$RUNTIME_ROOT/.git"
        fi
    done
    
    if [[ $secrets_in_git -eq 0 ]]; then
        record_finding "pass" "Git History" \
            "No obvious secrets found in git history"
    fi
    
    # Check git config
    if git -C "$RUNTIME_ROOT" config --get user.email 2>/dev/null; then
        record_finding "pass" "Git Config" \
            "Git user is configured"
    else
        record_finding "low" "Git Config" \
            "Git user.email is not configured" \
            "Set git email: git config user.email 'your@email.com'"
    fi
}

# Check encryption
check_encryption() {
    section "ENCRYPTION CHECKS"
    
    # Check if encryption tool exists
    if [[ -f "$RUNTIME_ROOT/tools/agent-toolkit/secret.sh" ]]; then
        record_finding "pass" "Encryption Tool" \
            "Secrets encryption tool is available"
        
        # Check if there are .enc files (encrypted)
        local enc_count=$(find "$RUNTIME_ROOT" -name "*.enc" -type f 2>/dev/null | grep -v ".git/" | wc -l || echo "0")
        if [[ $enc_count -gt 0 ]]; then
            record_finding "pass" "Encrypted Files" \
                "$enc_count encrypted files found"
        else
            record_finding "low" "Encrypted Files" \
                "No encrypted files found" \
                "Consider encrypting sensitive data"
        fi
        
        # Verify encryption strength (AES-256-CBC)
        if grep -q "AES-256-CBC" "$RUNTIME_ROOT/tools/agent-toolkit/secret.sh" 2>/dev/null; then
            record_finding "pass" "Encryption Algorithm" \
                "Using AES-256-CBC encryption (strong)"
        else
            record_finding "medium" "Encryption Algorithm" \
                "Encryption algorithm not verified as AES-256-CBC" \
                "Verify encryption strength in secret.sh"
        fi
        
        # Verify key derivation (PBKDF2)
        if grep -q "PBKDF2\|pbkdf2" "$RUNTIME_ROOT/tools/agent-toolkit/secret.sh" 2>/dev/null; then
            record_finding "pass" "Key Derivation" \
                "Using PBKDF2 key derivation (strong)"
        else
            record_finding "medium" "Key Derivation" \
                "Key derivation method not verified as PBKDF2" \
                "Verify key derivation strength in secret.sh"
        fi
    else
        record_finding "medium" "Encryption" \
            "Encryption tool not found at $RUNTIME_ROOT/tools/agent-toolkit/secret.sh" \
            "Secrets may not be encrypted"
    fi
}

# =============================================================================
# REMEDIATION FUNCTIONS
# =============================================================================

fix_issue() {
    local issue="$1"
    local solution="$2"
    local file="$3"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Would fix: $issue"
        info "  Solution: $solution"
        return 0
    fi
    
    info "Fixing: $issue"
    
    # Parse solution and apply
    if echo "$solution" | grep -q "chmod"; then
        eval "$solution" && {
            success "Applied: $solution"
            return 0
        } || {
            error "Failed: $solution"
            return 1
        }
    elif echo "$solution" | grep -q "git filter-repo"; then
        warn "Git filter-repo requires manual execution"
        info "  Run: $solution"
        return 1
    elif echo "$solution" | grep -q "BFG"; then
        warn "BFG Repo-Cleaner requires manual execution"
        info "  Run: $solution"
        return 1
    else
        warn "Automatic fix not available for: $solution"
        return 1
    fi
}

# Attempt to fix all found issues
attempt_fixes() {
    section "ATTEMPTING SECURITY FIXES"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry-run mode: showing what would be fixed"
    else
        info "Applying security fixes..."
    fi
    
    local fixes_attempted=0
    local fixes_successful=0
    local fixes_for_review=0
    
    for finding in "${FINDINGS[@]}"; do
        local severity="${finding%%:*}"
        finding="${finding#*:}"
        local category="${finding%%:*}"
        finding="${finding#*:}"
        local description="${finding%%:*}"
        finding="${finding#*:}"
        local solution="${finding%%:*}"
        finding="${finding#*:}"
        local file="${finding%%:*}"
        local line="${finding#*:}"
        
        # Only attempt fixes for high, medium, and critical issues
        case "$severity" in
            "critical"|"high"|"medium")
                if [[ -n "$solution" ]]; then
                    fixes_attempted=$((fixes_attempted + 1))
                    fix_issue "$description" "$solution" "$file" && \
                        fixes_successful=$((fixes_successful + 1)) || \
                        fixes_for_review=$((fixes_for_review + 1))
                fi
                ;;
        esac
    done
    
    echo ""
    info "Fix Summary:"
    info "  Attempted: $fixes_attempted"
    info "  Successful: $fixes_successful"
    info "  For Review: $fixes_for_review"
    
    if [[ $fixes_successful -gt 0 ]]; then
        success "Some issues were fixed automatically"
    fi
}

# =============================================================================
# REPORT GENERATION
# =============================================================================

generate_audit_report() {
    section "GENERATING SECURITY AUDIT REPORT"
    
    local report_file="$LOGS_DIR/security-audit-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "$LOGS_DIR"
    
    info "Report will be saved to: $report_file"
    
    {
        echo "# Hemlock Security Audit Report"
        echo ""
        echo "**Generated**: $(date)"
        echo "**Host**: $(hostname)"
        echo "**User**: $(whoami)"
        echo "**Runtime Root**: $RUNTIME_ROOT"
        echo ""
        echo "## Executive Summary"
        echo ""
        
        local risk_score=$(calculate_risk_score)
        local risk_level=$(get_risk_level "$risk_score")
        
        echo "| Metric | Value |"
        echo "|--------|-------|"
        echo "| Risk Score | $risk_score/100 |"
        echo "| Risk Level | $risk_level |"
        echo "| Total Findings | ${STATS[total]} |"
        echo ""
        
        echo "### Severity Distribution"
        echo ""
        echo "| Severity | Count |"
        echo "|----------|-------|"
        echo "| Critical | ${STATS[critical]} |"
        echo "| High | ${STATS[high]} |"
        echo "| Medium | ${STATS[medium]} |"
        echo "| Low | ${STATS[low]} |"
        echo "| Info | ${STATS[info]} |"
        echo "| Pass | ${STATS[pass]} |"
        echo ""
        
        echo "## Detailed Findings"
        echo ""
        
        for finding in "${FINDINGS[@]}"; do
            local severity="${finding%%:*}"
            finding="${finding#*:}"
            local category="${finding%%:*}"
            finding="${finding#*:}"
            local description="${finding%%:*}"
            finding="${finding#*:}"
            local solution="${finding%%:*}"
            finding="${finding#*:}"
            local file="${finding%%:*}"
            local line="${finding#*:}"
            
            local severity_emoji=""
            case "$severity" in
                "critical") severity_emoji=":red_circle:" ;;
                "high") severity_emoji=":orange_circle:" ;;
                "medium") severity_emoji=":yellow_circle:" ;;
                "low") severity_emoji=":blue_circle:" ;;
                "info") severity_emoji=":white_circle:" ;;
                "pass") continue ;;
            esac
            
            echo "### ${severity_emoji} [${severity^^}] ${category}"
            echo ""
            echo "**Description:** ${description}"
            echo ""
            if [[ -n "$solution" ]]; then
                echo "**Solution:** ${solution}"
            fi
            if [[ -n "$file" ]]; then
                echo ""
                echo "**File:** \`${file}\`"
                if [[ -n "$line" ]]; then
                    echo "**Line:** ${line}"
                fi
            fi
            echo ""
        done
        
        echo "## Recommendations"
        echo ""
        
        if [[ ${STATS[critical]} -gt 0 ]]; then
            echo "1. **CRITICAL**: Address critical issues immediately"
            echo "   - Remove any exposed secrets from git"
            echo "   - Fix world-writable files"
            echo ""
        fi
        
        if [[ ${STATS[high]} -gt 0 ]]; then
            echo "2. **HIGH**: Fix high-risk issues"
            echo "   - Implement proper secrets management"
            echo "   - Restrict agent tool access"
            echo ""
        fi
        
        if [[ ${STATS[medium]} -gt 0 ]]; then
            echo "3. **MEDIUM**: Review medium-risk issues"
            echo "   - Check file permissions"
            echo "   - Review configuration security"
            echo ""
        fi
        
        if [[ ${STATS[low]} -gt 0 ]]; then
            echo "4. **LOW**: Consider addressing low-risk issues"
            echo "   - Implement security best practices"
            echo ""
        fi
        
        echo "5. **GENERAL**: security best practices"
        echo "   - Regular security audits"
        echo "   - Keep all software updated"
        echo "   - Use strong, unique passwords/tokens"
        echo "   - Limit access to sensitive operations"
        echo "   - Monitor for unusual activity"
        echo ""
        
        echo "## System Information"
        echo ""
        show_system_info | sed 's/^/  /'
        
        echo ""
        echo "---"
        echo "Report generated by Hemlock Security Scanner"
    } > "$report_file"
    
    if [[ -f "$report_file" ]]; then
        local report_size=$(stat -c '%s' "$report_file" 2>/dev/null || echo "0")
        success "Security audit report generated: $report_file ($report_size bytes)"
    else
        error "Failed to generate audit report"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local command="${1:-full}"
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
            --interactive)
                INTERACTIVE="true"
                shift
                ;;
            --fix)
                FIX="true"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Initialize JSON output
    if [[ "$JSON" == "true" ]]; then
        VERBOSE="false"
        echo "{"
        echo "  \"scan\": {"
        echo "    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "    \"host\": \"$(hostname 2>/dev/null || echo 'unknown')\","
        echo "    \"user\": \"$(whoami 2>/dev/null || echo 'unknown')\","
        echo "    \"type\": \"$command\""
        echo "  },"
        echo "  \"findings\": ["
        JSON_FINDINGS=()
    fi
    
    case "$command" in
        full)
            check_file_permissions
            check_secrets_management
            check_configuration_security
            check_agent_security
            check_network_security
            check_environment_security
            check_git_security
            check_encryption
            
            print_security_summary
            
            if [[ "$FIX" == "true" ]]; then
                attempt_fixes
            fi
            ;;
        quick)
            check_file_permissions
            check_secrets_management
            check_configuration_security
            print_security_summary
            ;;
        files)
            check_file_permissions
            print_security_summary
            ;;
        secrets)
            check_secrets_management
            print_security_summary
            ;;
        config)
            check_configuration_security
            print_security_summary
            ;;
        network)
            check_network_security
            print_security_summary
            ;;
        agents)
            check_agent_security
            print_security_summary
            ;;
        audit)
            check_file_permissions
            check_secrets_management
            check_configuration_security
            check_agent_security
            check_network_security
            check_environment_security
            check_git_security
            check_encryption
            print_security_summary
            generate_audit_report
            ;;
        fix)
            check_file_permissions
            check_secrets_management
            check_configuration_security
            check_agent_security
            check_network_security
            check_environment_security
            check_git_security
            check_encryption
            print_security_summary
            attempt_fixes
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
    
    # Finish JSON output
    if [[ "$JSON" == "true" ]]; then
        echo ""
        echo "  ]"
        echo "}"
    fi
    
    # Check if any critical issues found
    if [[ ${STATS[critical]} -gt 0 ]]; then
        return 2
    elif [[ ${STATS[high]} -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Run main
main "$@"
