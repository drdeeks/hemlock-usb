#!/usr/bin/env bash
# =============================================================================
# auth-login.sh — Provider and Model Selection
# 
# Interactive tool for configuring AI provider and model credentials.
# Stores configuration in agent's config.yaml and .env file.
# =============================================================================

set -euo pipefail

WS="${1:-$HERMES_HOME}"

if [ -z "$WS" ] || [ ! -d "$WS" ]; then
    echo "ERROR: Workspace not found: $WS"
    echo "Set \$HERMES_HOME or pass path as argument."
    exit 1
fi

CONFIG_FILE="$WS/config.yaml"
ENV_FILE="$WS/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

read_tty() {
    if [ -t 0 ]; then
        read "$@"
    elif [ -c /dev/tty ] && [ -w /dev/tty ]; then
        read "$@" < /dev/tty
    else
        return 1
    fi
}

read_tty_rs() {
    local var_name="$1"
    if [ -t 0 ]; then
        read -rs "$var_name"
    elif [ -c /dev/tty ] && [ -w /dev/tty ]; then
        read -rs "$var_name" < /dev/tty
    else
        return 1
    fi
}

# Provider configurations
declare -A PROVIDER_BASE_URL=(
    [ollama]="http://localhost:11434/v1"
    [openai]="https://api.openai.com/v1"
    [anthropic]="https://api.anthropic.com/v1"
    [groq]="https://api.groq.com/v1"
    [mistral]="https://api.mistral.ai/v1"
    [openrouter]="https://openrouter.ai/api/v1"
)

declare -A PROVIDER_DEFAULT_MODEL=(
    [ollama]="qwen3:0.6b"
    [openai]="gpt-4o"
    [anthropic]="claude-sonnet-4-20250514"
    [groq]="llama-3.3-70b-versatile"
    [mistral]="mistral-large-latest"
    [openrouter]="openai/gpt-4o"
)

declare -A PROVIDER_ENV_VAR=(
    [ollama]=""
    [openai]="OPENAI_API_KEY"
    [anthropic]="ANTHROPIC_API_KEY"
    [groq]="GROQ_API_KEY"
    [mistral]="MISTRAL_API_KEY"
    [openrouter]="OPENROUTER_API_KEY"
)

show_menu() {
    echo ""
    echo -e "  ${BOLD}${CYAN}━━━ Configure AI Provider ━━━${NC}"
    echo ""
    echo "    [1] Ollama (local)          - ${PROVIDER_BASE_URL[ollama]}"
    echo "    [2] OpenAI                  - ${PROVIDER_BASE_URL[openai]}"
    echo "    [3] Anthropic               - ${PROVIDER_BASE_URL[anthropic]}"
    echo "    [4] Groq                    - ${PROVIDER_BASE_URL[groq]}"
    echo "    [5] Mistral AI              - ${PROVIDER_BASE_URL[mistral]}"
    echo "    [6] OpenRouter              - ${PROVIDER_BASE_URL[openrouter]}"
    echo "    [7] Custom provider"
    echo "    [8] View current config"
    echo "    [9] Exit"
    echo ""
}

get_current_config() {
    local provider="" model="" base_url=""
    if [ -f "$CONFIG_FILE" ]; then
        provider=$(grep -E '^\s*provider:' "$CONFIG_FILE" | head -1 | sed 's/.*provider:\s*//' | tr -d '"' | xargs)
        model=$(grep -E '^\s*default:' "$CONFIG_FILE" | head -1 | sed 's/.*default:\s*//' | tr -d '"' | xargs)
        base_url=$(grep -E '^\s*base_url:' "$CONFIG_FILE" | head -1 | sed 's/.*base_url:\s*//' | tr -d '"' | xargs)
    fi
    echo "${provider:-unknown} ${model:-unknown} ${base_url:-unknown}"
}

update_config_yaml() {
    local provider="$1" model="$2" base_url="$3" api_key="$4"
    
    # Create backup
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    
    if [ -n "$api_key" ]; then
        cat > "$CONFIG_FILE" <<EOF
model:
  default: ${provider}/${model}
  provider: ${provider}
  base_url: ${base_url}
  api_key: ${api_key}

tools:
  profile: coding

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
EOF
    else
        cat > "$CONFIG_FILE" <<EOF
model:
  default: ${provider}/${model}
  provider: ${provider}
  base_url: ${base_url}

tools:
  profile: coding

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
EOF
    fi
    
    # Update .env with API key if provided
    if [ -n "$api_key" ] && [ -n "${PROVIDER_ENV_VAR[$provider]}" ]; then
        local env_var="${PROVIDER_ENV_VAR[$provider]}"
        if [ -f "$ENV_FILE" ] && grep -q "^${env_var}=" "$ENV_FILE"; then
            sed -i "s|^${env_var}=.*|${env_var}=${api_key}|" "$ENV_FILE"
        else
            echo "${env_var}=${api_key}" >> "$ENV_FILE"
        fi
    fi
}

# Main
main() {
    echo -e "  ${BOLD}${BLUE}━━━ AI Provider Configuration ━━━${NC}"
    echo "  Workspace: $WS"
    
    local current
    current=$(get_current_config)
    echo "  Current: $current"
    echo ""
    
    while true; do
        show_menu
        read_tty -rp "  Choice [9]: " choice
        choice="${choice:-9}"
        
        case "$choice" in
            1|2|3|4|5|6)
                local providers=(ollama openai anthropic groq mistral openrouter)
                local provider="${providers[$((choice-1))]}"
                local base_url="${PROVIDER_BASE_URL[$provider]}"
                local default_model="${PROVIDER_DEFAULT_MODEL[$provider]}"
                local env_var="${PROVIDER_ENV_VAR[$provider]}"
                local model="" api_key=""
                
                echo ""
                read_tty -rp "  Model name [${default_model}]: " model
                model="${model:-$default_model}"
                
                if [ -n "$env_var" ]; then
                    echo ""
                    echo -n "  ${env_var} (press Enter to skip): "
                    read_tty_rs api_key
                    echo ""
                    [ -z "$api_key" ] && warn "No API key provided — you can add it later in .env or config.yaml"
                fi
                
                update_config_yaml "$provider" "$model" "$base_url" "$api_key"
                success "Provider configured: ${provider}/${model}"
                ;;
            7)
                echo ""
                read_tty -rp "  Provider name: " provider
                read_tty -rp "  Model name: " model
                read_tty -rp "  Base URL: " base_url
                echo -n "  API key (optional): "
                read_tty_rs api_key
                echo ""
                [ -z "$provider" ] || [ -z "$model" ] || [ -z "$base_url" ] && { warn "Missing required fields"; continue; }
                update_config_yaml "$provider" "$model" "$base_url" "$api_key"
                success "Custom provider configured: ${provider}/${model}"
                ;;
            8)
                current=$(get_current_config)
                echo "  Current config: $current"
                if [ -f "$CONFIG_FILE" ]; then
                    echo "  ---"
                    cat "$CONFIG_FILE" | sed 's/^/  /'
                fi
                ;;
            9)
                echo "  Exiting..."
                exit 0
                ;;
            *)
                warn "Invalid choice. Enter a number between 1 and 9."
                ;;
        esac
    done
}

main "$@"