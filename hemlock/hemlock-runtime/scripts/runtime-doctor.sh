#!/bin/bash
# Hermes Doctor - Runtime Validation and Auto-Fix Tool

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/helpers.sh"

# Global variables
WARNINGS=0
ERRORS=0
FIXED=0
INTERACTIVE=false
FULL_VALIDATION=false
DOCKER_CHECK=false
CONFIG_CHECK=false
AUTO_FIX=false

# Display header
display_header() {
    clear
    echo "============================================="
    echo " Hermes Doctor - Runtime Validation Tool"
    echo "============================================="
    echo "Runtime Directory: $RUNTIME_DIR"
    echo "---------------------------------------------"
}

# Check Docker environment
check_docker_environment() {
    display_header
    echo "🔍 Checking Docker Environment..."
    
    if ! check_docker; then
        echo "❌ Docker is not running or not installed"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    if ! check_docker_compose; then
        echo "❌ Docker Compose is not installed"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    echo "✅ Docker is running"
    echo "✅ Docker Compose is available"
    
    # Check Docker version
    docker_version=$(docker --version)
    docker_compose_version=$(docker-compose --version)
    
    echo "Docker: $docker_version"
    echo "Docker Compose: $docker_compose_version"
    
    # Check for common issues
    if ! docker system info &> /dev/null; then
        echo "❌ Cannot connect to Docker daemon"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
    
    echo "✅ Docker daemon is accessible"
    return 0
}

# Check runtime structure
check_runtime_structure() {
    display_header
    echo "🔍 Checking Runtime Structure..."
    
    # Check required directories
    local required_dirs=("agents" "config" "logs" "scripts")
    local missing_dirs=()
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$RUNTIME_DIR/$dir" ]; then
            missing_dirs+=("$dir")
            ERRORS=$((ERRORS + 1))
        fi
    done
    
    if [ ${#missing_dirs[@]} -gt 0 ]; then
        echo "❌ Missing directories: ${missing_dirs[*]}"
        if [ "$AUTO_FIX" = true ]; then
            echo "🔧 Creating missing directories..."
            for dir in "${missing_dirs[@]}"; do
                mkdir -p "$RUNTIME_DIR/$dir"
                echo "✅ Created directory: $dir"
                FIXED=$((FIXED + 1))
            done
        fi
    else
        echo "✅ All required directories exist"
    fi
    
    # Check required files
    local required_files=("docker-compose.yml" "config/runtime.yaml")
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$RUNTIME_DIR/$file" ]; then
            missing_files+=("$file")
            ERRORS=$((ERRORS + 1))
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        echo "❌ Missing files: ${missing_files[*]}"
        if [ "$AUTO_FIX" = true ]; then
            echo "🔧 Creating default configuration files..."
            if [ ! -f "$RUNTIME_DIR/docker-compose.yml" ]; then
                cat > "$RUNTIME_DIR/docker-compose.yml" <<EOL
version: "3.9"

services:
  openclaw-gateway:
    image: openclaw/gateway:latest
    container_name: openclaw-gateway
    ports:
      - "18789:18789"
    volumes:
      - ~/.openclaw:/root/.openclaw
    networks:
      - agents_net
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost:18789/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  agents_net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"
EOL
                echo "✅ Created default docker-compose.yml"
                FIXED=$((FIXED + 1))
            fi
            
            if [ ! -f "$RUNTIME_DIR/config/runtime.yaml" ]; then
                mkdir -p "$RUNTIME_DIR/config"
                cat > "$RUNTIME_DIR/config/runtime.yaml" <<EOL
# OpenClaw Runtime Configuration
runtime:
  gateway:
    port: 18789
    token: "$(generate_random_token)"
  agents:
    default_model: "ollama/qwen3:0.6b"
    default_network: "agents_net"
  security:
    read_only: true
    cap_drop: true
    icc: false
EOL
                echo "✅ Created default runtime.yaml"
                FIXED=$((FIXED + 1))
            fi
        fi
    else
        echo "✅ All required files exist"
    fi
    
    return 0
}

# Validate YAML configurations
validate_configurations() {
    display_header
    echo "🔍 Validating YAML Configurations..."
    
    local config_files=(
        "$RUNTIME_DIR/config/runtime.yaml"
        "$RUNTIME_DIR/docker-compose.yml"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            if validate_yaml "$file"; then
                echo "✅ Valid YAML: $file"
            else
                echo "❌ Invalid YAML: $file"
                ERRORS=$((ERRORS + 1))
            fi
        else
            echo "⚠️  Skipping missing file: $file"
            WARNINGS=$((WARNINGS + 1))
        fi
    done
    
    # Check agent configurations
    if [ -d "$RUNTIME_DIR/agents" ]; then
        for agent_dir in "$RUNTIME_DIR/agents"/*; do
            if [ -d "$agent_dir" ]; then
                agent_id=$(basename "$agent_dir")
                config_file="$agent_dir/config.yaml"
                
                if [ -f "$config_file" ]; then
                    if validate_yaml "$config_file"; then
                        echo "✅ Valid agent config: $agent_id"
                    else
                        echo "❌ Invalid agent config: $agent_id"
                        ERRORS=$((ERRORS + 1))
                    fi
                else
                    echo "⚠️  Missing config for agent: $agent_id"
                    WARNINGS=$((WARNINGS + 1))
                fi
            fi
        done
    fi
    
    return 0
}

# Check security settings
check_security() {
    display_header
    echo "🔍 Checking Security Settings..."
    
    # Check runtime config for security settings
    if [ -f "$RUNTIME_DIR/config/runtime.yaml" ]; then
        local read_only=$(yq eval '.runtime.security.read_only' "$RUNTIME_DIR/config/runtime.yaml" 2>/dev/null || echo "true")
        local cap_drop=$(yq eval '.runtime.security.cap_drop' "$RUNTIME_DIR/config/runtime.yaml" 2>/dev/null || echo "true")
        local icc=$(yq eval '.runtime.security.icc' "$RUNTIME_DIR/config/runtime.yaml" 2>/dev/null || echo "false")
        
        if [ "$read_only" != "true" ]; then
            echo "⚠️  Read-only filesystem not enabled in config"
            WARNINGS=$((WARNINGS + 1))
            if [ "$AUTO_FIX" = true ]; then
                yq eval -i '.runtime.security.read_only = true' "$RUNTIME_DIR/config/runtime.yaml"
                echo "🔧 Enabled read-only filesystem in config"
                FIXED=$((FIXED + 1))
            fi
        else
            echo "✅ Read-only filesystem enabled in config"
        fi
        
        if [ "$cap_drop" != "true" ]; then
            echo "⚠️  Capability dropping not enabled in config"
            WARNINGS=$((WARNINGS + 1))
            if [ "$AUTO_FIX" = true ]; then
                yq eval -i '.runtime.security.cap_drop = true' "$RUNTIME_DIR/config/runtime.yaml"
                echo "🔧 Enabled capability dropping in config"
                FIXED=$((FIXED + 1))
            fi
        else
            echo "✅ Capability dropping enabled in config"
        fi
        
        if [ "$icc" != "false" ]; then
            echo "⚠️  Inter-container communication not disabled in config"
            WARNINGS=$((WARNINGS + 1))
            if [ "$AUTO_FIX" = true ]; then
                yq eval -i '.runtime.security.icc = false' "$RUNTIME_DIR/config/runtime.yaml"
                echo "🔧 Disabled inter-container communication in config"
                FIXED=$((FIXED + 1))
            fi
        else
            echo "✅ Inter-container communication disabled in config"
        fi
    fi
    
    # Check docker-compose.yml for security settings
    if [ -f "$RUNTIME_DIR/docker-compose.yml" ]; then
        # Check if network has icc disabled
        if ! grep -q "com.docker.network.bridge.enable_icc:.*false" "$RUNTIME_DIR/docker-compose.yml"; then
            echo "⚠️  Inter-container communication not disabled in docker-compose.yml"
            WARNINGS=$((WARNINGS + 1))
            if [ "$AUTO_FIX" = true ]; then
                # Create a temporary file
                local temp_file=$(mktemp)
                
                # Add icc: false to the network
                awk '/agents_net:/ {
                    print;
                    print "    driver_opts:";
                    print "      com.docker.network.bridge.enable_icc: \"false\"";
                    next
                } {print}' "$RUNTIME_DIR/docker-compose.yml" > "$temp_file"
                
                mv "$temp_file" "$RUNTIME_DIR/docker-compose.yml"
                echo "🔧 Disabled inter-container communication in docker-compose.yml"
                FIXED=$((FIXED + 1))
            fi
        else
            echo "✅ Inter-container communication disabled in docker-compose.yml"
        fi
    fi
    
    # Check agent security settings
    if [ -d "$RUNTIME_DIR/agents" ]; then
        for agent_dir in "$RUNTIME_DIR/agents"/*; do
            if [ -d "$agent_dir" ]; then
                agent_id=$(basename "$agent_dir")
                config_file="$agent_dir/config.yaml"
                
                if [ -f "$config_file" ]; then
                    local agent_read_only=$(yq eval '.agent.security.read_only' "$config_file" 2>/dev/null || echo "true")
                    local agent_cap_drop=$(yq eval '.agent.security.cap_drop' "$config_file" 2>/dev/null || echo "true")
                    
                    if [ "$agent_read_only" != "true" ]; then
                        echo "⚠️  Agent $agent_id: Read-only filesystem not enabled"
                        WARNINGS=$((WARNINGS + 1))
                        if [ "$AUTO_FIX" = true ]; then
                            yq eval -i '.agent.security.read_only = true' "$config_file"
                            echo "🔧 Enabled read-only filesystem for agent $agent_id"
                            FIXED=$((FIXED + 1))
                        fi
                    fi
                    
                    if [ "$agent_cap_drop" != "true" ]; then
                        echo "⚠️  Agent $agent_id: Capability dropping not enabled"
                        WARNINGS=$((WARNINGS + 1))
                        if [ "$AUTO_FIX" = true ]; then
                            yq eval -i '.agent.security.cap_drop = true' "$config_file"
                            echo "🔧 Enabled capability dropping for agent $agent_id"
                            FIXED=$((FIXED + 1))
                        fi
                    fi
                fi
            fi
        done
    fi
    
    return 0
}

# Check health status
check_health() {
    display_header
    echo "🔍 Checking System Health..."
    
    # Check Docker containers
    echo "Docker Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "No containers running"
    
    # Check disk usage
    echo -e "\nDisk Usage:"
    df -h "$RUNTIME_DIR"
    
    # Check memory usage
    echo -e "\nMemory Usage:"
    free -h
    
    # Check runtime logs for errors
    echo -e "\nRecent Runtime Errors:"
    grep -i "error\|fail\|warn" "$RUNTIME_DIR/logs/runtime.log" | tail -n 10 || echo "No recent errors"
    
    return 0
}

# Interactive validation
interactive_validation() {
    INTERACTIVE=true
    
    while true; do
        display_header
        echo "Hermes Doctor - Interactive Mode"
        echo "---------------------------------------------"
        echo "1. Check Docker Environment"
        echo "2. Check Runtime Structure"
        echo "3. Validate Configurations"
        echo "4. Check Security Settings"
        echo "5. Check System Health"
        echo "6. Run Full Validation"
        echo "7. Apply Auto-Fixes"
        echo "8. Exit"
        echo "---------------------------------------------"
        
        read -rp "Select option [1-8]: " choice
        case $choice in
            1) check_docker_environment ;;
            2) check_runtime_structure ;;
            3) validate_configurations ;;
            4) check_security ;;
            5) check_health ;;
            6) run_full_validation ;;
            7) apply_auto_fixes ;;
            8) exit 0 ;;
            *) echo "Invalid option"; sleep 1 ;;
        esac
        
        echo -e "\nPress any key to continue..."
        read -n 1 -s
    done
}

# Apply auto-fixes
apply_auto_fixes() {
    AUTO_FIX=true
    display_header
    echo "🔧 Applying Auto-Fixes..."
    
    check_runtime_structure
    validate_configurations
    check_security
    
    echo -e "\n🔧 Applied $FIXED auto-fixes"
    AUTO_FIX=false
}

# Run full validation
run_full_validation() {
    FULL_VALIDATION=true
    display_header
    echo "🔍 Running Full Validation..."
    
    check_docker_environment
    check_runtime_structure
    validate_configurations
    check_security
    check_health
    
    display_summary
    FULL_VALIDATION=false
}

# Display summary
display_summary() {
    echo -e "\n============================================="
    echo " Validation Summary"
    echo "============================================="
    echo "✅ Checks passed: $((23 - ERRORS - WARNINGS))"
    echo "⚠️  Warnings: $WARNINGS"
    echo "❌ Errors: $ERRORS"
    echo "🔧 Auto-fixed: $FIXED"
    echo "---------------------------------------------"
    
    if [ $ERRORS -gt 0 ]; then
        echo "❌ Validation failed with $ERRORS errors"
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        echo "⚠️  Validation completed with $WARNINGS warnings"
    else
        echo "✅ All validation checks passed!"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            FULL_VALIDATION=true
            shift ;;
        --interactive)
            INTERACTIVE=true
            shift ;;
        --docker)
            DOCKER_CHECK=true
            shift ;;
        --config)
            CONFIG_CHECK=true
            shift ;;
        --fix)
            AUTO_FIX=true
            shift ;;
        *)
            echo "Unknown option: $1"
            exit 1 ;;
    esac
done

# Main execution
if [ "$INTERACTIVE" = true ]; then
    interactive_validation
elif [ "$FULL_VALIDATION" = true ]; then
    run_full_validation
elif [ "$DOCKER_CHECK" = true ]; then
    check_docker_environment
display_summary
elif [ "$CONFIG_CHECK" = true ]; then
    validate_configurations
display_summary
else
    # Default: run full validation
    run_full_validation
fi