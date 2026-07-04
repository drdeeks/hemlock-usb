#!/bin/bash
# =============================================================================
# agent-create.sh — Create new agent with interactive configuration
#
# Bare minimum dirs: projects/, tools/, .secrets/, .archive/, memory/, cron/, logs/
# Files: agent.json, SOUL.md, USER.md, MEMORY.md, IDENTITY.md, HEARTBEAT.md,
#        TOOLS.md, config.yaml
# Tools: enforce.sh, inject-context.sh, secret.sh, memory-log.sh, memory-promote.sh, jsonfmt.py
# Docs:  AGENTS.md (operating standard), TOOLS.md (tool registry; TOOLS-GUIDE.md consolidated in)
#
# Interactive flow:
#   1. Agent ID + name
#   2. Model/provider selection + API keys
#   3. Communication channel selection + tokens
#   4. Gateway restart prompt
#
# Non-interactive mode: pass --id, --model, --name, --provider, --api-key, --channel
#
# Usage: ./agent-create.sh [--id <id>] [--model <model>] [--name <name>]
#        ./agent-create.sh [--id <id>] --provider <provider> --api-key <key>
#        ./agent-create.sh  (interactive)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers.sh"

TEMPLATE_DIR="${AGENTS_DIR}/workspace-template"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── Detect interactive mode ─────────────────────────────────────────────────
is_interactive() {
    # Explicit non-interactive override
    if [[ "${HEMLOCK_NONINTERACTIVE:-}" == "1" || "${SKIP_PROMPTS:-}" == true ]]; then
        return 1
    fi
    # Must have a real terminal on stdin
    if [[ -t 0 ]]; then
        return 0
    fi
    # If stdin is piped but /dev/tty is a character device, we're in a terminal
    if [[ -c /dev/tty ]] && [[ -w /dev/tty ]]; then
        return 0
    fi
    return 1
}

# ── Read from terminal (works even when stdin is piped) ─────────────────────
# CL-017: Honor HEMLOCK_NONINTERACTIVE=1 / SKIP_PROMPTS=true to force return 1
# in docker exec, CI, and headless menu flows where /dev/tty exists as a
# character device but is NOT the caller's controlling terminal (so `read`
# from it would hang or error).
read_tty() {
    [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" || "${SKIP_PROMPTS:-}" == true ]] && return 1
    if [[ -t 0 ]]; then
        read "$@"
    elif [[ -c /dev/tty ]] && [[ -w /dev/tty ]] && tty -s </dev/tty 2>/dev/null; then
        read "$@" < /dev/tty
    else
        return 1
    fi
}

read_tty_rs() {
    [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" || "${SKIP_PROMPTS:-}" == true ]] && return 1
    local var_name="$1"
    if [[ -t 0 ]]; then
        read -rs "$var_name"
    elif [[ -c /dev/tty ]] && [[ -w /dev/tty ]] && tty -s </dev/tty 2>/dev/null; then
        read -rs "$var_name" < /dev/tty
    else
        return 1
    fi
}

# ── Defaults (non-interactive) ───────────────────────────────────────────────
AGENT_ID=""
MODEL=""
NAME=""
PROVIDER=""
API_KEY=""
BASE_URL=""
CHANNEL=""
CHANNEL_TOKEN=""
SKIP_PROMPTS=false

# ── Parse arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        --id) AGENT_ID="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --provider) PROVIDER="$2"; shift 2 ;;
        --api-key) API_KEY="$2"; shift 2 ;;
        --base-url) BASE_URL="$2"; shift 2 ;;
        --channel) CHANNEL="$2"; shift 2 ;;
        --channel-token) CHANNEL_TOKEN="$2"; shift 2 ;;
        --skip-prompts) SKIP_PROMPTS=true; shift ;;
        --non-interactive|-n) HEMLOCK_NONINTERACTIVE=1; SKIP_PROMPTS=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Interactive: collect agent ID ────────────────────────────────────────────
if is_interactive && [[ -z "$AGENT_ID" ]]; then
    echo ""
    echo -e "  ${BOLD}${BLUE}━━━ Create New Agent ━━━${NC}"
    echo ""
    read_tty -rp "  Agent ID (e.g., my-agent): " AGENT_ID
    [[ -z "$AGENT_ID" ]] && { echo "  Cancelled."; exit 0; }
    read_tty -rp "  Display name [${AGENT_ID}]: " NAME
    [[ -z "$NAME" ]] && NAME="$AGENT_ID"
else
    [[ -z "$NAME" ]] && NAME="$AGENT_ID"
fi

# ── Validate ─────────────────────────────────────────────────────────────────
[[ -z "$AGENT_ID" ]] && { echo "Error: Agent ID required"; exit 1; }
validate_agent_id "$AGENT_ID" || exit 1
agent_exists "$AGENT_ID" && { echo "Error: Agent $AGENT_ID exists"; exit 1; }

TIMESTAMP="$(date -Iseconds)"

# ── Check template ───────────────────────────────────────────────────────────
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "Error: workspace-template not found at $TEMPLATE_DIR"
    exit 1
fi

echo ""
echo -e "  ${BOLD}Creating agent: ${CYAN}${AGENT_ID}${NC}"
echo ""

# ── Copy template ────────────────────────────────────────────────────────────
cp -ra "$TEMPLATE_DIR/." "$AGENTS_DIR/$AGENT_ID/"

# Replace placeholders
find "$AGENTS_DIR/$AGENT_ID" -type f -exec sed -i \
    -e "s/<agent-id>/$AGENT_ID/g" \
    -e "s/<display-name>/$NAME/g" \
    -e "s/<created-at>/$TIMESTAMP/g" \
    {} +

# ── Write core files ─────────────────────────────────────────────────────────
# CL-018: per-agent isolation — file is named after the agent id, NOT a
# generic "agent.json". This prevents mixed/defaulted-out identity files
# when multiple agent workspaces sit next to each other on disk.
cat > "$AGENTS_DIR/$AGENT_ID/${AGENT_ID}.json" <<EOF
{
  "agent_id": "$AGENT_ID",
  "name": "$NAME",
  "display_name": "$NAME",
  "status": "active",
  "type": "active",
  "personality": "Helpful, efficient, and direct",
  "expertise": ["general assistance"],
  "communication_style": "Clear and concise",
  "avatar_emoji": "🤖",
  "created_at": "$TIMESTAMP",
  "version": "1.0.0",
  "model": "${MODEL:-ollama/qwen3:0.6b}",
  "builderCode": {
    "code": "bc_default",
    "hex": "0x62635f64656661756c74",
    "owner": "0x0000000000000000000000000000000000000000",
    "hardwired": true,
    "enforced": true
  }
}
EOF

cat > "$AGENTS_DIR/$AGENT_ID/SOUL.md" <<EOF
# SOUL.md — $AGENT_ID

**Identity:** $AGENT_ID
**Name:** $NAME
**Purpose:** General purpose assistant
**Model:** ${MODEL:-ollama/qwen3:0.6b}
**Created:** $TIMESTAMP

## Core Principles
- Move forward. When you screw up, fix it and keep going.
- Think like a COO, not an EA. Own outcomes, not tasks.
- Be genuine. Not performing cleverness. Just present and honest.
EOF

cat > "$AGENTS_DIR/$AGENT_ID/USER.md" <<EOF
# USER.md — $AGENT_ID

**Owner:** User
**Preferences:** Direct and efficient communication
**Working Style:** Async-first, deep work blocks
**Current Focus:** To be determined

## Communication
- Get to the point quickly
- Lay out tradeoffs clearly
- Ask for clarification when uncertain
EOF

cat > "$AGENTS_DIR/$AGENT_ID/MEMORY.md" <<EOF
# MEMORY.md — $AGENT_ID

**Purpose:** Curated wisdom, lessons learned, decisions made

---

## Lessons

*Lessons will be added as you learn them.*

---

## Decisions

*Major decisions and why they were made.*

---

## Patterns

*Recurring situations and how to handle them.*

---

**Created:** $TIMESTAMP
EOF

# TOOLS.md and AGENTS.md are seeded verbatim from workspace-template via the
# cp -ra above (consolidated, versioned, path-agnostic). TOOLS.md is the agent's
# LIVING tool registry — it grows as the agent builds its own helpers, so we do
# NOT regenerate/overwrite it here. AGENTS.md is the global operating standard.

# ── Copy tools ───────────────────────────────────────────────────────────────
for tool in enforce.sh inject-context.sh secret.sh memory-log.sh memory-promote.sh context-dump.sh rollback.sh jsonfmt.py; do
    if [[ ! -f "$AGENTS_DIR/$AGENT_ID/tools/$tool" ]]; then
        if [[ -f "$TEMPLATE_DIR/tools/$tool" ]]; then
            cp "$TEMPLATE_DIR/tools/$tool" "$AGENTS_DIR/$AGENT_ID/tools/"
        elif [[ -f "$SCRIPT_DIR/$tool" ]]; then
            cp "$SCRIPT_DIR/$tool" "$AGENTS_DIR/$AGENT_ID/tools/"
        fi
    fi
done

# ── Permissions ──────────────────────────────────────────────────────────────
chmod 755 "$AGENTS_DIR/$AGENT_ID/.secrets" 2>/dev/null || true
find "$AGENTS_DIR/$AGENT_ID" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$AGENTS_DIR/$AGENT_ID" -type f -exec chmod 644 {} \; 2>/dev/null || true

# ── Enforcement ──────────────────────────────────────────────────────────────
if [[ -f "$AGENTS_DIR/$AGENT_ID/tools/enforce.sh" ]]; then
    bash "$AGENTS_DIR/$AGENT_ID/tools/enforce.sh" "$AGENTS_DIR/$AGENT_ID" 2>/dev/null || true
fi

# ── Provision Docker volume ─────────────────────────────────────────────────
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    VOLUME_NAME="hemlock_agent_${AGENT_ID}"
    if ! docker volume inspect "$VOLUME_NAME" &>/dev/null; then
        docker volume create --label "agent=$AGENT_ID" --label "framework=hemlock" "$VOLUME_NAME" 2>/dev/null
    fi
fi

# ── Register agent as active ─────────────────────────────────────────────────
register_agent_active "$AGENT_ID"

# ── Interactive: Model/Provider Configuration ────────────────────────────────
_configure_model() {
    echo ""
    echo -e "  ${BOLD}${BLUE}━━━ Configure AI Model ━━━${NC}"
    echo ""
    echo "    [1] Ollama (local)          - http://localhost:11434/v1"
    echo "    [2] OpenAI                  - https://api.openai.com/v1"
    echo "    [3] Anthropic               - https://api.anthropic.com/v1"
    echo "    [4] Groq                    - https://api.groq.com/v1"
    echo "    [5] Mistral AI              - https://api.mistral.ai/v1"
    echo "    [6] OpenRouter              - https://openrouter.ai/api/v1"
    echo "    [7] Custom provider"
    echo "    [8] Skip (use default: ollama/qwen3:0.6b)"
    echo ""

    local choice=""
    read_tty -rp "  Choice [8]: " choice
    [[ -z "$choice" ]] && choice="8"

    local model_name="" provider_name="" base_url="" api_key=""

    case "$choice" in
        1) provider_name="ollama"; base_url="http://localhost:11434/v1"; model_name="qwen3" ;;
        2)
            provider_name="openai"; base_url="https://api.openai.com/v1"; model_name="gpt-4o"
            echo ""
            echo -n "  OpenAI API key: "
            read_tty_rs api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key provided — you can add it later"
            ;;
        3)
            provider_name="anthropic"; base_url="https://api.anthropic.com/v1"; model_name="claude-sonnet-4-20250514"
            echo ""
            echo -n "  Anthropic API key: "
            read_tty_rs api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key provided — you can add it later"
            ;;
        4)
            provider_name="groq"; base_url="https://api.groq.com/v1"; model_name="llama-3.3-70b-versatile"
            echo ""
            echo -n "  Groq API key: "
            read_tty_rs api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key provided — you can add it later"
            ;;
        5)
            provider_name="mistral"; base_url="https://api.mistral.ai/v1"; model_name="mistral-large-latest"
            echo ""
            echo -n "  Mistral API key: "
            read_tty_rs api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key provided — you can add it later"
            ;;
        6)
            provider_name="openrouter"; base_url="https://openrouter.ai/api/v1"; model_name="openai/gpt-4o"
            echo ""
            echo -n "  OpenRouter API key: "
            read_tty_rs api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key provided — you can add it later"
            ;;
        7)
            echo ""
            read_tty -rp "  Provider name: " provider_name
            read_tty -rp "  Model name: " model_name
            read_tty -rp "  Base URL: " base_url
            echo -n "  API key (optional): "
            read_tty_rs api_key; echo ""
            [[ -z "$provider_name" || -z "$model_name" || -z "$base_url" ]] && { warn "Missing fields — skipping"; return; }
            ;;
        *) echo "  Using default model."; return ;;
    esac

    # Write config.yaml — REQUIRED by Hermes runtime (run_agent.py, memory_manager,
    # credential_pool, auxiliary_client, context_engine, skill_commands all read
    # this file). Also write .env for secrets + per-agent env overrides.
    local config_file="$AGENTS_DIR/$AGENT_ID/config.yaml"
    local env_file="$AGENTS_DIR/$AGENT_ID/.env"
    mkdir -p "$(dirname "$env_file")"
    {
        echo "AGENT_ID=${AGENT_ID}"
        echo "AGENT_MODEL=${provider_name}/${model_name}"
        echo "AGENT_PROVIDER=${provider_name}"
        echo "AGENT_BASE_URL=${base_url}"
        [[ -n "$api_key" ]] && echo "AGENT_API_KEY=${api_key}"
    } > "$env_file"
    chmod 600 "$env_file" 2>/dev/null || true
    if [[ -n "$api_key" ]]; then
        cat > "$config_file" <<EOF
model:
  default: ${provider_name}/${model_name}
  provider: ${provider_name}
  base_url: ${base_url}
  api_key: ${api_key}

tools:
  profile: coding
  terminal:
    enabled: true
    shell: /bin/bash
    timeout: 30
    max_output: 4000
  skill_downloads:
    enabled: true
    registry: /skills/skills
    auto_install: false

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
  auto_discover: true

channels:
  telegram:
    enabled: false
  discord:
    enabled: false
  slack:
    enabled: false

group_chat:
  enabled: true
  protocol: a2a
  broadcast: true
  max_agents: 10
EOF
    else
        cat > "$config_file" <<EOF
model:
  default: ${provider_name}/${model_name}
  provider: ${provider_name}
  base_url: ${base_url}

tools:
  profile: coding
  terminal:
    enabled: true
    shell: /bin/bash
    timeout: 30
    max_output: 4000
  skill_downloads:
    enabled: true
    registry: /skills/skills
    auto_install: false

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
  auto_discover: true

channels:
  telegram:
    enabled: false
  discord:
    enabled: false
  slack:
    enabled: false

group_chat:
  enabled: true
  protocol: a2a
  broadcast: true
  max_agents: 10
EOF
    fi

    # Update per-agent <id>.json (CL-018: filename = ${AGENT_ID}.json, not agent.json)
    sed -i "s|\"model\":.*|\"model\": \"${provider_name}/${model_name}\"|" "$AGENTS_DIR/$AGENT_ID/${AGENT_ID}.json"
    sed -i "s|**Model:**.*|**Model:** ${provider_name}/${model_name}|" "$AGENTS_DIR/$AGENT_ID/SOUL.md"

    success "Model configured: ${provider_name}/${model_name}"
}

# ── Interactive: Channel Configuration ───────────────────────────────────────
_configure_channel() {
    echo ""
    echo -e "  ${BOLD}${BLUE}━━━ Configure Communication Channel ━━━${NC}"
    echo ""
    echo "    [1] Telegram        - BotFather token required"
    echo "    [2] Discord         - Bot token required"
    echo "    [3] Slack           - Bot token required"
    echo "    [4] WhatsApp        - Access token + phone number ID"
    echo "    [5] Skip (configure later)"
    echo ""

    local choice=""
    read_tty -rp "  Choice [5]: " choice
    [[ -z "$choice" ]] && choice="5"

    local env_file="$AGENTS_DIR/$AGENT_ID/.env"
    mkdir -p "$(dirname "$env_file")"

    _set_env() {
        local key="$1" value="$2"
        if grep -q "^${key}=" "$env_file" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$env_file"
        else
            echo "${key}=${value}" >> "$env_file"
        fi
    }

    _mask() {
        local v="$1" len=${#1}
        if [[ $len -le 4 ]]; then echo "****"
        else echo "****${v: -4}"; fi
    }

    case "$choice" in
        1)
            echo ""
            echo "  1. Open @BotFather on Telegram"
            echo "  2. Send /newbot and follow instructions"
            echo "  3. Copy the bot token (format: 123456:ABC-DEF...)"
            echo ""
            read_tty_rs "  Bot Token: " telegram_token; echo ""
            [[ -z "$telegram_token" ]] && { warn "Cancelled."; return; }
            _set_env "TELEGRAM_BOT_TOKEN" "$telegram_token"
            echo ""
            read_tty -rp "  Allowed users (comma-separated IDs, or 'all' for open): " allowed_users
            if [[ "$allowed_users" == "all" || -z "$allowed_users" ]]; then
                _set_env "TELEGRAM_ALLOW_ALL_USERS" "true"
                success "Open access enabled"
            else
                _set_env "TELEGRAM_ALLOWED_USERS" "$allowed_users"
                success "Allowlist configured"
            fi
            success "Telegram configured (token: $(_mask "$telegram_token"))"
            ;;
        2)
            echo ""
            echo "  1. Go to https://discord.com/developers/applications"
            echo "  2. Create an application and go to 'Bot' section"
            echo "  3. Copy the bot token"
            echo ""
            read_tty_rs "  Bot Token: " discord_token; echo ""
            [[ -z "$discord_token" ]] && { warn "Cancelled."; return; }
            _set_env "DISCORD_BOT_TOKEN" "$discord_token"
            success "Discord configured (token: $(_mask "$discord_token"))"
            ;;
        3)
            echo ""
            echo "  1. Go to https://api.slack.com/apps"
            echo "  2. Create an app and install to workspace"
            echo "  3. Copy the Bot User OAuth Token (xoxb-...)"
            echo ""
            read_tty_rs "  Bot Token: " slack_token; echo ""
            [[ -z "$slack_token" ]] && { warn "Cancelled."; return; }
            _set_env "SLACK_BOT_TOKEN" "$slack_token"
            success "Slack configured (token: $(_mask "$slack_token"))"
            ;;
        4)
            echo ""
            echo "  1. Go to https://developers.facebook.com/apps/"
            echo "  2. Create a WhatsApp Business app"
            echo "  3. Get your Phone Number ID and Access Token"
            echo ""
            read_tty_rs "  Access Token: " wa_token; echo ""
            [[ -z "$wa_token" ]] && { warn "Cancelled."; return; }
            read_tty -rp "  Phone Number ID: " wa_phone_id
            _set_env "WHATSAPP_ACCESS_TOKEN" "$wa_token"
            [[ -n "$wa_phone_id" ]] && _set_env "WHATSAPP_PHONE_NUMBER_ID" "$wa_phone_id"
            success "WhatsApp configured"
            ;;
        *) echo "  Channel configuration skipped." ;;
    esac
}

# ── Interactive: Gateway Restart Prompt ──────────────────────────────────────
_prompt_restart_gateway() {
    echo ""
    read_tty -rp "  Restart gateway to apply changes? [y/N]: " do_restart
    if [[ "$do_restart" =~ ^[Yy]$ ]]; then
        if command -v docker &>/dev/null; then
            local container_name=""
            for name in hemlock_runtime hemlock_agent hermes_framework hemlock_framework gateway_framework; do
                if docker ps -q -f name="$name" 2>/dev/null | grep -q .; then
                    container_name="$name"
                    break
                fi
            done
            if [[ -n "$container_name" ]]; then
                docker restart "$container_name" 2>&1
                success "Gateway restart initiated"
                echo "  Wait ~10 seconds for it to come back up."
            else
                warn "No running gateway container found"
                echo "  Start with: docker compose -f docker-compose.runtime.yml up -d"
            fi
        else
            warn "Docker not available"
        fi
    fi
}

# ── Non-interactive: apply provided config ───────────────────────────────────
# Infer provider from model string if not explicitly set (e.g. "ollama/qwen3" → provider "ollama")
if [[ -z "$PROVIDER" && -n "$MODEL" ]]; then
    case "$MODEL" in
        ollama/*)   PROVIDER="ollama";   BASE_URL="${BASE_URL:-http://localhost:11434/v1}" ;;
        openai/*)   PROVIDER="openai";   BASE_URL="${BASE_URL:-https://api.openai.com/v1}" ;;
        anthropic/*) PROVIDER="anthropic"; BASE_URL="${BASE_URL:-https://api.anthropic.com/v1}" ;;
        groq/*)     PROVIDER="groq";     BASE_URL="${BASE_URL:-https://api.groq.com/v1}" ;;
        mistral/*)  PROVIDER="mistral";  BASE_URL="${BASE_URL:-https://api.mistral.ai/v1}" ;;
        openrouter/*) PROVIDER="openrouter"; BASE_URL="${BASE_URL:-https://openrouter.ai/api/v1}" ;;
        nous/*)     PROVIDER="nous";     BASE_URL="${BASE_URL:-http://localhost:11434/v1}" ;;
        */*)        PROVIDER="${MODEL%%/*}"; BASE_URL="${BASE_URL:-http://localhost:11434/v1}" ;;
        *)          PROVIDER="ollama";   BASE_URL="${BASE_URL:-http://localhost:11434/v1}" ;;
    esac
fi

if [[ "$SKIP_PROMPTS" == true ]] || ! is_interactive; then
    if [[ -n "$PROVIDER" && -n "$MODEL" ]]; then
        cat > "$AGENTS_DIR/$AGENT_ID/config.yaml" <<EOF
model:
  default: ${MODEL}
  provider: ${PROVIDER}
  base_url: ${BASE_URL:-http://localhost:11434/v1}
$( [[ -n "$API_KEY" ]] && echo "  api_key: ${API_KEY}" )

tools:
  profile: coding

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
EOF
    fi
    if [[ -n "$CHANNEL" && -n "$CHANNEL_TOKEN" ]]; then
        local env_file="$AGENTS_DIR/$AGENT_ID/.env"
        mkdir -p "$(dirname "$env_file")"
        case "$CHANNEL" in
            telegram|tg) echo "TELEGRAM_BOT_TOKEN=$CHANNEL_TOKEN" >> "$env_file" ;;
            discord|dc) echo "DISCORD_BOT_TOKEN=$CHANNEL_TOKEN" >> "$env_file" ;;
            slack|sl) echo "SLACK_BOT_TOKEN=$CHANNEL_TOKEN" >> "$env_file" ;;
            whatsapp|wa) echo "WHATSAPP_ACCESS_TOKEN=$CHANNEL_TOKEN" >> "$env_file" ;;
        esac
    fi
else
    # ── Interactive: run configuration prompts ───────────────────────────────
    _configure_model
    _configure_channel
    _prompt_restart_gateway
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GREEN}✓ Agent ${AGENT_ID} created successfully${NC}"
echo "    Location: $AGENTS_DIR/$AGENT_ID"
echo ""
echo "    Structure:"
ls -la "$AGENTS_DIR/$AGENT_ID/" | head -20
