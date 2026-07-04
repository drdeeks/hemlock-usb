#!/bin/bash
# Security Hardening Script for OpenClaw Runtime

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/helpers.sh"

# Display header
display_header() {
    clear
    echo "============================================="
    echo " OpenClaw Runtime Security Hardening"
    echo "============================================="
    echo "Runtime Directory: $RUNTIME_DIR"
    echo "---------------------------------------------"
}

# Apply security hardening
apply_hardening() {
    display_header
    echo "🔧 Applying Security Hardening..."
    
    # 1. Harden runtime configuration
    echo "1. Hardening runtime configuration..."
    if [ -f "$RUNTIME_DIR/config/runtime.yaml" ]; then
        yq eval -i '.runtime.security.read_only = true' "$RUNTIME_DIR/config/runtime.yaml"
        yq eval -i '.runtime.security.cap_drop = true' "$RUNTIME_DIR/config/runtime.yaml"
        yq eval -i '.runtime.security.icc = false' "$RUNTIME_DIR/config/runtime.yaml"
        echo "✅ Updated runtime security configuration"
    else
        echo "⚠️  Runtime configuration file not found"
    fi
    
    # 2. Harden docker-compose.yml
    echo "2. Hardening Docker Compose configuration..."
    if [ -f "$RUNTIME_DIR/docker-compose.yml" ]; then
        # Create a temporary file
        local temp_file=$(mktemp)
        
        # Add security settings to all services
        awk '{
            print;
            if (/container_name:/) {
                print "    cap_drop:";
                print "      - ALL";
                print "    read_only: true";
                print "    tmpfs:";
                print "      - /tmp:size=64m";
            }
        }' "$RUNTIME_DIR/docker-compose.yml" > "$temp_file"
        
        # Ensure network has icc disabled
        if ! grep -q "com.docker.network.bridge.enable_icc:.*false" "$temp_file"; then
            awk '/agents_net:/ {
                print;
                print "    driver_opts:";
                print "      com.docker.network.bridge.enable_icc: \"false\"";
                next
            } {print}' "$temp_file" > "$RUNTIME_DIR/docker-compose.yml"
        else
            mv "$temp_file" "$RUNTIME_DIR/docker-compose.yml"
        fi
        
        echo "✅ Updated Docker Compose security settings"
    else
        echo "⚠️  Docker Compose file not found"
    fi
    
    # 3. Harden agent configurations
    echo "3. Hardening agent configurations..."
    if [ -d "$RUNTIME_DIR/agents" ]; then
        for agent_dir in "$RUNTIME_DIR/agents"/*; do
            if [ -d "$agent_dir" ]; then
                agent_id=$(basename "$agent_dir")
                config_file="$agent_dir/config.yaml"
                
                if [ -f "$config_file" ]; then
                    yq eval -i '.agent.security.read_only = true' "$config_file"
                    yq eval -i '.agent.security.cap_drop = true' "$config_file"
                    echo "✅ Updated security settings for agent $agent_id"
                fi
            fi
        done
    fi
    
    # 4. Set file permissions
    echo "4. Setting secure file permissions..."
    find "$RUNTIME_DIR" -type f -name "*.sh" -exec chmod 700 {} \;
    find "$RUNTIME_DIR" -type f -name "*.yaml" -exec chmod 600 {} \;
    find "$RUNTIME_DIR" -type f -name "*.yml" -exec chmod 600 {} \;
    chmod 700 "$RUNTIME_DIR/scripts/runtime.sh"
    echo "✅ Set secure file permissions"
    
    # 5. Create .dockerignore to prevent sensitive files from being copied
    echo "5. Creating .dockerignore file..."
    cat > "$RUNTIME_DIR/.dockerignore" <<EOL
# Security-sensitive files
*.env
*.secret
*.key
*.pem
*.enc
*.json
*.yaml
*.yml

# Development files
.git
.gitignore
README.md
*.md

# Logs and temporary files
*.log
*.tmp
*.swp

# Sensitive directories
secrets/
.secrets/
.secrets_*

# Node.js
node_modules/
npm-debug.log

# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
env/
venv/
.venv/
ENV/

# IDE
.idea/
.vscode/
*.sublime-workspace
*.sublime-project

# OS
.DS_Store
.DS_Store?
.Trashes
._*

# Docker
.dockerignore
docker-compose*.yml
Dockerfile*
EOL
    echo "✅ Created .dockerignore file"
    
    # 6. Check Docker daemon configuration
    echo "6. Checking Docker daemon configuration..."
    if [ -f /etc/docker/daemon.json ]; then
        echo "✅ Docker daemon configuration exists"
    else
        echo "⚠️  Docker daemon configuration not found"
        echo "   Consider creating /etc/docker/daemon.json with:"
        echo "   {"userns-remap": "default"}"
    fi
    
    echo -e "\n🔐 Security hardening applied successfully!"
}

# Check security status
check_security_status() {
    display_header
    echo "🔍 Checking Security Status..."
    
    local score=0
    local total=23
    local passed=0
    
    # 1. Check runtime configuration
    echo "1. Runtime Configuration:"
    if [ -f "$RUNTIME_DIR/config/runtime.yaml" ]; then
        local read_only=$(yq eval '.runtime.security.read_only' "$RUNTIME_DIR/config/runtime.yaml" 2>/dev/null || echo "false")
        local cap_drop=$(yq eval '.runtime.security.cap_drop' "$RUNTIME_DIR/config/runtime.yaml" 2>/dev/null || echo "false")
        local icc=$(yq eval '.runtime.security.icc' "$RUNTIME_DIR/config/runtime.yaml" 2>/dev/null || echo "true")
        
        if [ "$read_only" = "true" ]; then
            echo "   ✅ Read-only filesystem: enabled"
            passed=$((passed + 1))
        else
            echo "   ❌ Read-only filesystem: disabled"
        fi
        
        if [ "$cap_drop" = "true" ]; then
            echo "   ✅ Capability dropping: enabled"
            passed=$((passed + 1))
        else
            echo "   ❌ Capability dropping: disabled"
        fi
        
        if [ "$icc" = "false" ]; then
            echo "   ✅ Inter-container communication: disabled"
            passed=$((passed + 1))
        else
            echo "   ❌ Inter-container communication: enabled"
        fi
    else
        echo "   ❌ Runtime configuration file not found"
    fi
    
    # 2. Check Docker Compose configuration
    echo -e "\n2. Docker Compose Configuration:"
    if [ -f "$RUNTIME_DIR/docker-compose.yml" ]; then
        local has_cap_drop=$(grep -c "cap_drop:" "$RUNTIME_DIR/docker-compose.yml" || echo "0")
        local has_read_only=$(grep -c "read_only: true" "$RUNTIME_DIR/docker-compose.yml" || echo "0")
        local has_icc_disabled=$(grep -c "com.docker.network.bridge.enable_icc:.*false" "$RUNTIME_DIR/docker-compose.yml" || echo "0")
        
        if [ "$has_cap_drop" -gt 0 ]; then
            echo "   ✅ Capability dropping: enabled"
            passed=$((passed + 1))
        else
            echo "   ❌ Capability dropping: disabled"
        fi
        
        if [ "$has_read_only" -gt 0 ]; then
            echo "   ✅ Read-only filesystem: enabled"
            passed=$((passed + 1))
        else
            echo "   ❌ Read-only filesystem: disabled"
        fi
        
        if [ "$has_icc_disabled" -gt 0 ]; then
            echo "   ✅ Inter-container communication: disabled"
            passed=$((passed + 1))
        else
            echo "   ❌ Inter-container communication: enabled"
        fi
    else
        echo "   ❌ Docker Compose file not found"
    fi
    
    # 3. Check agent configurations
    echo -e "\n3. Agent Configurations:"
    if [ -d "$RUNTIME_DIR/agents" ]; then
        for agent_dir in "$RUNTIME_DIR/agents"/*; do
            if [ -d "$agent_dir" ]; then
                agent_id=$(basename "$agent_dir")
                config_file="$agent_dir/config.yaml"
                
                if [ -f "$config_file" ]; then
                    local agent_read_only=$(yq eval '.agent.security.read_only' "$config_file" 2>/dev/null || echo "false")
                    local agent_cap_drop=$(yq eval '.agent.security.cap_drop' "$config_file" 2>/dev/null || echo "false")
                    
                    echo "   Agent $agent_id:"
                    if [ "$agent_read_only" = "true" ]; then
                        echo "     ✅ Read-only filesystem: enabled"
                        passed=$((passed + 1))
                    else
                        echo "     ❌ Read-only filesystem: disabled"
                    fi
                    
                    if [ "$agent_cap_drop" = "true" ]; then
                        echo "     ✅ Capability dropping: enabled"
                        passed=$((passed + 1))
                    else
                        echo "     ❌ Capability dropping: disabled"
                    fi
                fi
            fi
        done
    else
        echo "   ⚠️  No agents directory found"
    fi
    
    # 4. Check file permissions
    echo -e "\n4. File Permissions:"
    local secure_scripts=$(find "$RUNTIME_DIR" -type f -name "*.sh" -perm 700 | wc -l)
    local total_scripts=$(find "$RUNTIME_DIR" -type f -name "*.sh" | wc -l)
    local secure_configs=$(find "$RUNTIME_DIR" -type f -name "*.yaml" -perm 600 | wc -l)
    local total_configs=$(find "$RUNTIME_DIR" -type f -name "*.yaml" | wc -l)
    
    if [ "$secure_scripts" -eq "$total_scripts" ] && [ "$total_scripts" -gt 0 ]; then
        echo "   ✅ Script permissions: secure (700)"
        passed=$((passed + 1))
    else
        echo "   ❌ Script permissions: insecure"
    fi
    
    if [ "$secure_configs" -eq "$total_configs" ] && [ "$total_configs" -gt 0 ]; then
        echo "   ✅ Config permissions: secure (600)"
        passed=$((passed + 1))
    else
        echo "   ❌ Config permissions: insecure"
    fi
    
    # 5. Check .dockerignore
    echo -e "\n5. Docker Security:"
    if [ -f "$RUNTIME_DIR/.dockerignore" ]; then
        echo "   ✅ .dockerignore file: exists"
        passed=$((passed + 1))
    else
        echo "   ❌ .dockerignore file: missing"
    fi
    
    # Calculate security score
    local score=$((passed * 100 / total))
    echo -e "\n🔐 Security Score: $score% ($passed/$total checks passed)"
    
    if [ "$score" -eq 100 ]; then
        echo "🔒 Security Status: Excellent"
    elif [ "$score" -ge 80 ]; then
        echo "🔒 Security Status: Good"
    elif [ "$score" -ge 60 ]; then
        echo "🔒 Security Status: Fair"
    else
        echo "🔒 Security Status: Poor - Needs improvement"
    fi
}

# Reset security settings
reset_security() {
    display_header
    echo "🔄 Resetting Security Settings to Defaults..."
    
    # Reset runtime configuration
    if [ -f "$RUNTIME_DIR/config/runtime.yaml" ]; then
        yq eval -i '.runtime.security.read_only = false' "$RUNTIME_DIR/config/runtime.yaml"
        yq eval -i '.runtime.security.cap_drop = false' "$RUNTIME_DIR/config/runtime.yaml"
        yq eval -i '.runtime.security.icc = true' "$RUNTIME_DIR/config/runtime.yaml"
        echo "✅ Reset runtime security configuration"
    fi
    
    # Reset Docker Compose configuration
    if [ -f "$RUNTIME_DIR/docker-compose.yml" ]; then
        # Create a temporary file
        local temp_file=$(mktemp)
        
        # Remove security settings
        awk '{
            if (/cap_drop:/ || /read_only:/ || /tmpfs:/) {
                skip=1;
            }
            if (!skip) {
                print;
            }
            if (/^$/) {
                skip=0;
            }
        }' "$RUNTIME_DIR/docker-compose.yml" > "$temp_file"
        
        # Remove icc setting from network
        awk '/com.docker.network.bridge.enable_icc:/ {skip=1} !skip {print}' "$temp_file" > "$RUNTIME_DIR/docker-compose.yml"
        
        echo "✅ Reset Docker Compose security settings"
    fi
    
    # Reset agent configurations
    if [ -d "$RUNTIME_DIR/agents" ]; then
        for agent_dir in "$RUNTIME_DIR/agents"/*; do
            if [ -d "$agent_dir" ]; then
                agent_id=$(basename "$agent_dir")
                config_file="$agent_dir/config.yaml"
                
                if [ -f "$config_file" ]; then
                    yq eval -i '.agent.security.read_only = false' "$config_file"
                    yq eval -i '.agent.security.cap_drop = false' "$config_file"
                    echo "✅ Reset security settings for agent $agent_id"
                fi
            fi
        done
    fi
    
    # Reset file permissions
    find "$RUNTIME_DIR" -type f -name "*.sh" -exec chmod 755 {} \;
    find "$RUNTIME_DIR" -type f -name "*.yaml" -exec chmod 644 {} \;
    find "$RUNTIME_DIR" -type f -name "*.yml" -exec chmod 644 {} \;
    echo "✅ Reset file permissions"
    
    # Remove .dockerignore
    if [ -f "$RUNTIME_DIR/.dockerignore" ]; then
        rm "$RUNTIME_DIR/.dockerignore"
        echo "✅ Removed .dockerignore file"
    fi
    
    echo -e "\n🔄 Security settings reset to defaults"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --apply)
            apply_hardening
            exit 0 ;;
        --check)
            check_security_status
            exit 0 ;;
        --reset)
            reset_security
            exit 0 ;;
        *)
            echo "Usage: $0 [--apply|--check|--reset]"
            exit 1 ;;
    esac
done

# Default: show menu
while true; do
    display_header
    echo "OpenClaw Runtime Security Hardening"
    echo "---------------------------------------------"
    echo "1. Apply Security Hardening"
    echo "2. Check Security Status"
    echo "3. Reset Security Settings"
    echo "4. Exit"
    echo "---------------------------------------------"
    
    read -rp "Select option [1-4]: " choice
    case $choice in
        1) apply_hardening ;;
        2) check_security_status ;;
        3) reset_security ;;
        4) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
    
    echo -e "\nPress any key to continue..."
    read -n 1 -s
done