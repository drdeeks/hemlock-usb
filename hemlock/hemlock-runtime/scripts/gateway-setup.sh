#!/bin/bash
# =============================================================================
# gateway-setup.sh — Per-agent gateway platform configuration
#
# Usage:
#   bash gateway-setup.sh [platform] [agent_id]
#   bash gateway-setup.sh telegram aton
#   bash gateway-setup.sh discord
#
# Platforms: telegram, discord, slack, whatsapp
#
# When agent_id is provided, writes platform config to agent's workspace .env.
# HERMES_MANAGED=false ensures gateway chmod is disabled (set in entrypoint.sh).
# Each agent is a separate Hermes profile with isolated platform configs.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Get agent workspace .env path
_get_agent_env() {
    local agent_id="${1:-}"
    if [[ -n "$agent_id" ]] && [[ -d "$AGENTS_DIR/$agent_id" ]]; then
        echo "$AGENTS_DIR/$agent_id/.env"
    elif [[ -f /.dockerenv ]]; then
        # Inside container without agent_id - use runtime default
        echo "/runtime/.env"
    else
        # Fallback
        echo "$RUNTIME_ROOT/runtime/.env"
    fi
}

# Get runtime .env path (shared gateway config)
_get_hermes_env() {
    local hermes_home="${HERMES_HOME:-$RUNTIME_ROOT/runtime}"
    echo "$hermes_home/.env"
}

# Display config path (user-friendly)
_show_config_path() {
    local agent_id="${1:-}"
    if [[ -n "$agent_id" ]]; then
        echo "agent workspace ($agent_id/.env)"
    else
        echo "gateway config"
    fi
}

# Write env var to agent workspace .env (idempotent)
_set_agent_env_var() {
    local agent_id="$1" key="$2" value="$3"
    local env_file
    env_file=$(_get_agent_env "$agent_id")
    mkdir -p "$(dirname "$env_file")"
    if grep -q "^${key}=" "$env_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
        echo "${key}=${value}" >> "$env_file"
    fi
}

# Write env var to runtime .env (idempotent) - DEPRECATED
_set_env_var() {
    local key="$1" value="$2"
    local env_file
    env_file=$(_get_hermes_env)
    mkdir -p "$(dirname "$env_file")"
    if grep -q "^${key}=" "$env_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
    else
        echo "${key}=${value}" >> "$env_file"
    fi
}

_mask_value() {
    local value="$1"
    local len=${#value}
    if [[ $len -le 4 ]]; then
        echo "****"
    else
        echo "****${value: -4}"
    fi
}

_colors() {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
}
_colors

setup_telegram() {
    local agent_id="${AGENT_ID:-}"
    echo ""
    echo -e "  ${BOLD}${BLUE}Telegram Setup${NC}"
    echo "  1. Open @BotFather on Telegram"
    echo "  2. Send /newbot and follow instructions"
    echo "  3. Copy the bot token (format: 123456:ABC-DEF...)"
    echo ""
    echo -en "  Bot Token: "
    read -rs telegram_token
    echo ""
    if [[ -z "$telegram_token" ]]; then
        echo -e "  ${YELLOW}Cancelled.${NC}"
        return 1
    fi
    if [[ -n "$agent_id" ]]; then
        _set_agent_env_var "$agent_id" "TELEGRAM_BOT_TOKEN" "$telegram_token"
    else
        _set_env_var "TELEGRAM_BOT_TOKEN" "$telegram_token"
    fi
    echo ""
    echo -en "  Allowed users (comma-separated user IDs, or 'all' for open access): "
    read -r allowed_users
    if [[ -n "$allowed_users" ]]; then
        if [[ "$allowed_users" == "all" ]]; then
            if [[ -n "$agent_id" ]]; then
                _set_agent_env_var "$agent_id" "TELEGRAM_ALLOW_ALL_USERS" "true"
            else
                _set_env_var "TELEGRAM_ALLOW_ALL_USERS" "true"
            fi
            echo -e "  ${GREEN}✓ Open access enabled${NC}"
        else
            if [[ -n "$agent_id" ]]; then
                _set_agent_env_var "$agent_id" "TELEGRAM_ALLOWED_USERS" "$allowed_users"
            else
                _set_env_var "TELEGRAM_ALLOWED_USERS" "$allowed_users"
            fi
            echo -e "  ${GREEN}✓ Allowlist configured${NC}"
        fi
    else
        # Default to open access if not specified
        if [[ -n "$agent_id" ]]; then
            _set_agent_env_var "$agent_id" "TELEGRAM_ALLOW_ALL_USERS" "true"
        else
            _set_env_var "TELEGRAM_ALLOW_ALL_USERS" "true"
        fi
        echo -e "  ${GREEN}✓ Open access enabled (default)${NC}"
    fi
    echo ""
    echo -e "  ${GREEN}✓ Telegram configured${NC}"
    echo "  Token: $(_mask_value "$telegram_token")"
    echo "  Config written to: $(_show_config_path "$agent_id")"
    
    # If agent_id provided, update agent's channel_directory.json
    if [[ -n "$agent_id" ]]; then
        local agent_dir="${HERMES_HOME:-$RUNTIME_ROOT/runtime}"
        if [[ -f "$agent_dir/channel_directory.json" ]]; then
            echo "  Updating channel directory for agent: $agent_id"
        fi
    fi
}

setup_discord() {
    local agent_id="${AGENT_ID:-}"
    echo ""
    echo -e "  ${BOLD}${BLUE}Discord Setup${NC}"
    echo "  1. Go to https://discord.com/developers/applications"
    echo "  2. Create an application and go to 'Bot' section"
    echo "  3. Copy the bot token"
    echo ""
    echo -en "  Bot Token: "
    read -rs discord_token
    echo ""
    if [[ -z "$discord_token" ]]; then
        echo -e "  ${YELLOW}Cancelled.${NC}"
        return 1
    fi
    if [[ -n "$agent_id" ]]; then
        _set_agent_env_var "$agent_id" "DISCORD_BOT_TOKEN" "$discord_token"
    else
        _set_env_var "DISCORD_BOT_TOKEN" "$discord_token"
    fi
    echo ""
    echo -e "  ${GREEN}✓ Discord configured${NC}"
    echo "  Token: $(_mask_value "$discord_token")"
    echo "  Config written to: $(_show_config_path "$agent_id")"
}

setup_slack() {
    local agent_id="${AGENT_ID:-}"
    echo ""
    echo -e "  ${BOLD}${BLUE}Slack Setup${NC}"
    echo "  1. Go to https://api.slack.com/apps"
    echo "  2. Create an app and install to workspace"
    echo "  3. Copy the Bot User OAuth Token (xoxb-...)"
    echo ""
    echo -en "  Bot Token: "
    read -rs slack_token
    echo ""
    if [[ -z "$slack_token" ]]; then
        echo -e "  ${YELLOW}Cancelled.${NC}"
        return 1
    fi
    if [[ -n "$agent_id" ]]; then
        _set_agent_env_var "$agent_id" "SLACK_BOT_TOKEN" "$slack_token"
    else
        _set_env_var "SLACK_BOT_TOKEN" "$slack_token"
    fi
    echo ""
    echo -e "  ${GREEN}✓ Slack configured${NC}"
    echo "  Token: $(_mask_value "$slack_token")"
    echo "  Config written to: $(_show_config_path "$agent_id")"
}

setup_whatsapp() {
    local agent_id="${AGENT_ID:-}"
    echo ""
    echo -e "  ${BOLD}${BLUE}WhatsApp Setup${NC}"
    echo "  1. Go to https://developers.facebook.com/apps/"
    echo "  2. Create a WhatsApp Business app"
    echo "  3. Get your Phone Number ID and Access Token"
    echo ""
    echo -en "  Access Token: "
    read -rs wa_token
    echo ""
    if [[ -z "$wa_token" ]]; then
        echo -e "  ${YELLOW}Cancelled.${NC}"
        return 1
    fi
    echo -en "  Phone Number ID: "
    read -r wa_phone_id
    echo ""
    if [[ -n "$agent_id" ]]; then
        _set_agent_env_var "$agent_id" "WHATSAPP_ACCESS_TOKEN" "$wa_token"
        if [[ -n "$wa_phone_id" ]]; then
            _set_agent_env_var "$agent_id" "WHATSAPP_PHONE_NUMBER_ID" "$wa_phone_id"
        fi
    else
        _set_env_var "WHATSAPP_ACCESS_TOKEN" "$wa_token"
        if [[ -n "$wa_phone_id" ]]; then
            _set_env_var "WHATSAPP_PHONE_NUMBER_ID" "$wa_phone_id"
        fi
    fi
    echo ""
    echo -e "  ${GREEN}✓ WhatsApp configured${NC}"
    echo "  Token: $(_mask_value "$wa_token")"
    echo "  Config written to: $(_show_config_path "$agent_id")"
}

# Main
PLATFORM="${1:-}"
AGENT_ID="${2:-}"

if [[ -n "$PLATFORM" ]]; then
    case "$PLATFORM" in
        telegram|tg|t) setup_telegram ;;
        discord|dc|d) setup_discord ;;
        slack|sl|s) setup_slack ;;
        whatsapp|wa|w) setup_whatsapp ;;
        *) echo "Unknown platform: $PLATFORM. Use: telegram, discord, slack, whatsapp"; exit 1 ;;
    esac
else
    echo -e "  ${BOLD}${BLUE}Gateway Setup — Communication Channels${NC}"
    echo "  Configure a messaging platform. Tokens are stored in the runtime .env."
    echo "  The gateway picks up changes on restart."
    echo ""
    echo "    [1] Telegram"
    echo "    [2] Discord"
    echo "    [3] Slack"
    echo "    [4] WhatsApp"
    echo "    [5] Cancel"
    echo ""
    read -rp "  Platform: " plat 2>/dev/null || plat="5"

    case "$plat" in
        1) setup_telegram ;;
        2) setup_discord ;;
        3) setup_slack ;;
        4) setup_whatsapp ;;
        *) echo "  Cancelled." ;;
    esac
fi

# Offer restart
echo ""
echo -n "  Restart gateway to apply changes? [y/N]: "
read -r do_restart 2>/dev/null || do_restart="n"
if [[ "$do_restart" =~ ^[Yy]$ ]]; then
    echo "  Restarting gateway container..."
    if command -v docker &>/dev/null; then
        # Try common container names
        container_name=""
        for name in hermes_framework hemlock_framework gateway_framework; do
            if docker ps -q -f name="$name" 2>/dev/null | grep -q .; then
                container_name="$name"
                break
            fi
        done
        
        if [[ -n "$container_name" ]]; then
            docker restart "$container_name" 2>&1
            echo -e "  ${GREEN}✓ Gateway restart initiated${NC}"
            echo "  Wait ~10 seconds for it to come back up."
        else
            echo -e "  ${YELLOW}⚠ Gateway container not found${NC}"
            echo "  Try: docker ps -a | grep framework"
        fi
    else
        echo -e "  ${RED}✗ Docker not available${NC}"
    fi
fi

echo ""
read -n 1 -s -r -p "  Press any key to continue..."
echo ""
