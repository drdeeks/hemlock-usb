#!/bin/bash
# =============================================================================
# agent-import.sh — Universal agent importer
#
# Accepts ANY source type:
# - Directories (copies all files including hidden)
# - Archives: .tar.gz, .tgz, .tar, .zip, .bz2
# - Unknown formats (attempts auto-detection)
#
# Ensures workspace-template compliance, handles all secrets safely
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers.sh"

TEMPLATE_DIR="${AGENTS_DIR}/workspace-template"

SOURCE="" TARGET="" OVERWRITE=false QUIET=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source) SOURCE="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --overwrite|--force) OVERWRITE=true; shift ;;
        --quiet|-q) QUIET=true; shift ;;
        --non-interactive|-n) HEMLOCK_NONINTERACTIVE=1; SHIFT_PROMPTS=true; shift ;;
        -h|--help) echo "Usage: $0 <source> <agent_id>"; exit 0 ;;
        *) SOURCE="$1"; shift ;;
    esac
done

[[ -z "$SOURCE" || -z "$TARGET" ]] && { echo "Usage: $0 <source> <agent_id>"; exit 1; }
validate_agent_id "$TARGET" || exit 1

# ── Resolve source path ──────────────────────────────────────────────────────
# If the raw SOURCE doesn't exist, try IMPORTS_DIR staging area
if [[ ! -e "$SOURCE" ]]; then
    _basename="$(basename "$SOURCE")"
    if [[ -e "${IMPORTS_DIR:-/data/imports}/${_basename}" ]]; then
        echo "  Resolved: $SOURCE → ${IMPORTS_DIR:-/data/imports}/${_basename}"
        SOURCE="${IMPORTS_DIR:-/data/imports}/${_basename}"
    else
        echo "Error: Source not found: $SOURCE"
        echo "  Also checked: ${IMPORTS_DIR:-/data/imports}/${_basename}"
        echo ""
        echo "  To import from the host, copy the file to volumes/imports/ first:"
        echo "    cp /path/to/agent.zip volumes/imports/"
        echo "  Then use: $0 /data/imports/agent.zip <agent_id>"
        exit 1
    fi
fi

# Handle existing agent
if agent_exists "$TARGET"; then
    if [[ "$OVERWRITE" == true ]]; then
        echo "  Removing existing agent..."
        rm -rf "$AGENTS_DIR/$TARGET"
    else
        echo "Error: Agent $TARGET exists. Use --overwrite"; exit 1
    fi
fi

# Clean up partial/failed imports (empty dir or no agent.json)
if [[ -d "$AGENTS_DIR/$TARGET" ]] && ! agent_exists "$TARGET"; then
    echo "  Cleaning up incomplete agent directory..."
    rm -rf "$AGENTS_DIR/$TARGET"
fi

echo ""
echo "  Importing agent '$TARGET'..."
mkdir -p "$AGENTS_DIR/$TARGET"

# Clean up on failure
trap 'if ! agent_exists "$TARGET"; then echo "  Import failed, cleaning up..."; rm -rf "$AGENTS_DIR/$TARGET"; fi' EXIT

# Universal source handler
import_source() {
    local src="$1"
    local dest="$2"

    # Directory - copy everything including hidden files
    if [[ -d "$src" ]]; then
        echo "  Source: Directory"
        local file_count
        file_count=$(find "$src" -type f 2>/dev/null | wc -l)
        echo "  Copying $file_count files..."
        cp -ra "$src/." "$dest/"
        echo "  Copy complete."
        return 0
    fi

    # Archive files - detect and extract
    if [[ -f "$src" ]]; then
        local filesize
        filesize=$(du -h "$src" | cut -f1)
        case "$src" in
            *.tar.gz|*.tgz)
                echo "  Source: tar.gz archive ($filesize)"
                echo "  Extracting..."
                tar -xzf "$src" -C "$dest"
                echo "  Extraction complete."
                return 0
                ;;
            *.tar)
                echo "  Source: tar archive ($filesize)"
                echo "  Extracting..."
                tar -xf "$src" -C "$dest"
                echo "  Extraction complete."
                return 0
                ;;
            *.tar.bz2|*.tbz2)
                echo "  Source: tar.bz2 archive ($filesize)"
                echo "  Extracting..."
                tar -xjf "$src" -C "$dest"
                echo "  Extraction complete."
                return 0
                ;;
            *.zip)
                echo "  Source: zip archive ($filesize)"
                echo "  Extracting..."
                if command -v unzip &>/dev/null; then
                    unzip -q "$src" -d "$dest"
                else
                    echo "  Warning: unzip not available, trying tar"
                    tar -xf "$src" -C "$dest" 2>/dev/null || return 1
                fi
                echo "  Extraction complete."
                return 0
                ;;
            *)
                # Unknown format - try auto-detection
                echo "  Source: Unknown format ($filesize) — auto-detecting..."
                if tar -tf "$src" &>/dev/null; then
                    echo "  Detected: tar archive"
                    echo "  Extracting..."
                    tar -xf "$src" -C "$dest"
                    echo "  Extraction complete."
                    return 0
                elif unzip -t "$src" &>/dev/null 2>&1; then
                    echo "  Detected: zip archive"
                    echo "  Extracting..."
                    unzip -q "$src" -d "$dest"
                    echo "  Extraction complete."
                    return 0
                else
                    echo "  Warning: Could not detect archive type, copying as-is"
                    cp -a "$src" "$dest/"
                    return 0
                fi
                ;;
        esac
    fi

    echo "Error: Cannot access source: $src"
    return 1
}

# ── Detect interactive mode ─────────────────────────────────────────────────
is_interactive() {
    # Explicit non-interactive override
    if [[ "${HEMLOCK_NONINTERACTIVE:-}" == "1" || "${SKIP_PROMPTS:-}" == true ]]; then
        return 1
    fi
    # Must have a real terminal on stdin
    if [[ -t 0 ]] || [[ -c /dev/tty ]] && [[ -w /dev/tty ]]; then
        return 0
    fi
    # If stdin is piped but /dev/tty is a character device, we're in a terminal
    if [[ -c /dev/tty ]] && [[ -w /dev/tty ]]; then
        return 0
    fi
    return 1
}

# ── Read from terminal (works even when stdin is piped) ─────────────────────
# CL-017: Honor HEMLOCK_NONINTERACTIVE=1 / SHIFT_PROMPTS for headless flows.
read_tty() {
    [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" || "${SHIFT_PROMPTS:-}" == true ]] && return 1
    if [[ -t 0 ]]; then
        read "$@"
    elif [[ -c /dev/tty ]] && [[ -w /dev/tty ]] && tty -s </dev/tty 2>/dev/null; then
        read "$@" < /dev/tty
    else
        return 1
    fi
}

read_tty_rs() {
    [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" || "${SHIFT_PROMPTS:-}" == true ]] && return 1
    local var_name="$1"
    if [[ -t 0 ]]; then
        read -rs "$var_name"
    elif [[ -c /dev/tty ]] && [[ -w /dev/tty ]] && tty -s </dev/tty 2>/dev/null; then
        read -rs "$var_name" < /dev/tty
    else
        return 1
    fi
}

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Import the source
TEMP_EXTRACT=""
if [[ "$SOURCE" == *.zip ]] || [[ "$SOURCE" == *.tar.gz ]] || [[ "$SOURCE" == *.tgz ]] || [[ "$SOURCE" == *.tar ]] || [[ "$SOURCE" == *.tar.bz2 ]]; then
    # For archives, extract to temp first to handle nested structures
    echo "  Creating temporary workspace..."
    TEMP_EXTRACT=$(mktemp -d)
    if import_source "$SOURCE" "$TEMP_EXTRACT"; then
        # Check for empty archive
        FILE_COUNT=$(find "$TEMP_EXTRACT" -type f 2>/dev/null | wc -l)
        if [[ $FILE_COUNT -eq 0 ]]; then
            echo "  Error: Archive is empty"
            rm -rf "$TEMP_EXTRACT"
            exit 1
        fi

        # Remove __MACOSX before processing
        rm -rf "$TEMP_EXTRACT/__MACOSX" 2>/dev/null || true

        # Recursive flattening: find deepest directory containing agent markers
        echo "  Scanning archive structure..."
        FLATTEN_ROOT="$TEMP_EXTRACT"
        depth=0
        while true; do
            SUBDIRS=$(find "$FLATTEN_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            if [[ $SUBDIRS -eq 1 ]]; then
                SINGLE_DIR=$(find "$FLATTEN_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
                # Check if this directory contains agent markers
                # CL-018: accept either legacy agent.json OR new <id>.json OR SOUL.md as markers
                if [[ -f "$SINGLE_DIR/agent.json" ]] || compgen -G "$SINGLE_DIR/*.json" > /dev/null || [[ -f "$SINGLE_DIR/SOUL.md" ]]; then
                    FLATTEN_ROOT="$SINGLE_DIR"
                    depth=$((depth + 1))
                    break
                fi
                # Check if it has any files at all
                DIR_FILES=$(find "$SINGLE_DIR" -type f 2>/dev/null | wc -l)
                if [[ $DIR_FILES -gt 0 ]]; then
                    FLATTEN_ROOT="$SINGLE_DIR"
                    depth=$((depth + 1))
                else
                    break
                fi
            else
                break
            fi
        done
        if [[ $depth -gt 0 ]]; then
            echo "  Flattened $depth nested level(s)."
        fi

        # Copy flattened contents to target
        echo "  Importing files to agent directory..."
        if [[ -d "$FLATTEN_ROOT" ]]; then
            cp -ra "$FLATTEN_ROOT/." "$AGENTS_DIR/$TARGET/" 2>/dev/null || true
        fi
        rm -rf "$TEMP_EXTRACT"
        echo "  Files imported."
    else
        rm -rf "$TEMP_EXTRACT"
        echo "  Import failed."
        exit 1
    fi
else
    # Direct copy for directories
    if import_source "$SOURCE" "$AGENTS_DIR/$TARGET"; then
        echo "  Files imported."
    else
        echo "  Import failed."
        exit 1
    fi
fi

# Ensure workspace-template structure
echo ""
echo "  Ensuring workspace structure..."
for dir in memory knowledge tools workflows projects sessions .archive .scope .secrets logs media/images/agents media/images/misc media/files; do
    if [[ ! -d "$AGENTS_DIR/$TARGET/$dir" ]]; then
        mkdir -p "$AGENTS_DIR/$TARGET/$dir"
        echo "    Created: $dir/"
    fi
done

# Ensure required files
echo "  Checking required files..."
for file in SOUL.md USER.md AGENTS.md; do
    if [[ ! -f "$AGENTS_DIR/$TARGET/$file" ]]; then
        case "$file" in
            SOUL.md)
                cat > "$AGENTS_DIR/$TARGET/$file" <<EOF
# SOUL.md — $TARGET
**Identity:** $TARGET
**Purpose:** Imported agent
EOF
                echo "    Created: $file"
                ;;
            USER.md)
                cat > "$AGENTS_DIR/$TARGET/$file" <<EOF
# USER.md — $TARGET
**Owner:** User
EOF
                echo "    Created: $file"
                ;;
            AGENTS.md)
                cat > "$AGENTS_DIR/$TARGET/$file" <<EOF
# AGENTS.md — $TARGET
**Agent:** $TARGET
**Imported:** $(date -Iseconds)
EOF
                echo "    Created: $file"
                ;;
        esac
    else
        echo "    Verified: $file"
    fi
done

# CL-018: identity file is <TARGET>.json (per-agent isolation). Migrate any
# legacy agent.json or stale <old_id>.json that came in the import bundle.
TARGET_JSON="$AGENTS_DIR/$TARGET/${TARGET}.json"
# If the bundle brought a legacy or differently-named json, fold it forward
for stale in "$AGENTS_DIR/$TARGET/agent.json" $AGENTS_DIR/$TARGET/*.json; do
    [[ -f "$stale" ]] || continue
    [[ "$stale" == "$TARGET_JSON" ]] && continue
    # If TARGET_JSON doesn't exist yet, promote the first non-matching one
    if [[ ! -f "$TARGET_JSON" ]]; then
        mv "$stale" "$TARGET_JSON"
        echo "    Migrated identity file: $(basename "$stale") → $(basename "$TARGET_JSON")"
    else
        rm -f "$stale"
        echo "    Removed extra identity file: $(basename "$stale")"
    fi
done
# Always (re)write the target file with the correct agent_id, preserving any
# fields the bundle brought if jq/python is available.
if [[ -f "$TARGET_JSON" ]] && command -v python3 >/dev/null 2>&1; then
    python3 - <<PYEOF || true
import json
p = "$TARGET_JSON"
with open(p) as f:
    d = json.load(f)
d["agent_id"] = "$TARGET"
d["name"] = d.get("name", "$TARGET")
d["display_name"] = d.get("display_name", "$TARGET")
d["status"] = "active"
d["type"] = d.get("type", "imported")
with open(p, "w") as f:
    json.dump(d, f, indent=2)
PYEOF
else
    cat > "$TARGET_JSON" <<EOF
{
  "agent_id": "$TARGET",
  "name": "$TARGET",
  "display_name": "$TARGET",
  "status": "active",
  "type": "imported",
  "personality": "Helpful, efficient, and direct",
  "expertise": ["general assistance"],
  "communication_style": "Clear and concise",
  "avatar_emoji": "🤖",
  "created_at": "$(date -Iseconds)",
  "version": "1.0.0",
  "model": "ollama/qwen3:0.6b"
}
EOF
fi
echo "    Updated: ${TARGET}.json"

# Secure .secrets
mkdir -p "$AGENTS_DIR/$TARGET/.secrets"
chmod 755 "$AGENTS_DIR/$TARGET/.secrets"

# Copy tools if missing
echo "  Checking tools..."
for tool in enforce.sh inject-context.sh secret.sh memory-promote.sh memory-log.sh context-dump.sh rollback.sh jsonfmt.py; do
    if [[ ! -f "$AGENTS_DIR/$TARGET/tools/$tool" ]]; then
        if [[ -f "$TEMPLATE_DIR/tools/$tool" ]]; then
            cp "$TEMPLATE_DIR/tools/$tool" "$AGENTS_DIR/$TARGET/tools/"
            echo "    Added tool: $tool"
        elif [[ -f "$SCRIPT_DIR/$tool" ]]; then
            cp "$SCRIPT_DIR/$tool" "$AGENTS_DIR/$TARGET/tools/"
            echo "    Added tool: $tool"
        fi
    fi
done

# Set permissions (NEVER 700)
echo "  Setting permissions..."
echo "    Fixing directories..."
find "$AGENTS_DIR/$TARGET" -type d -exec chmod 755 {} + 2>/dev/null || true
echo "    Fixing files..."
find "$AGENTS_DIR/$TARGET" -type f -exec chmod 644 {} + 2>/dev/null || true

# Clean up Mac artifacts
echo "  Cleaning artifacts..."
echo "    Removing __MACOSX..."
rm -rf "$AGENTS_DIR/$TARGET/__MACOSX" 2>/dev/null || true
echo "    Removing .DS_Store..."
find "$AGENTS_DIR/$TARGET" -name ".DS_Store" -delete 2>/dev/null || true

# Run enforcement
if [[ -f "$AGENTS_DIR/$TARGET/tools/enforce.sh" ]]; then
    echo ""
    echo "  Running workspace enforcement..."
    bash "$AGENTS_DIR/$TARGET/tools/enforce.sh" "$AGENTS_DIR/$TARGET" || true
    echo "  Enforcement complete."
fi

echo ""
echo "  Agent '$TARGET' imported successfully."
echo "  Location: $AGENTS_DIR/$TARGET"
echo ""
echo "  Structure:"
ls -la "$AGENTS_DIR/$TARGET/" | grep "^d" | awk '{print "    " $9}'

# Status was set in the migration block above (line ~340). No-op here.
:

# Provision isolated Docker volume for the agent
echo ""
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    VOLUME_NAME="hemlock_agent_${TARGET}"
    if ! docker volume inspect "$VOLUME_NAME" &>/dev/null; then
        echo "  Creating Docker volume..."
        docker volume create --label "agent=$TARGET" --label "framework=hemlock" "$VOLUME_NAME" 2>/dev/null
        echo "  Volume created: $VOLUME_NAME"
    else
        echo "  Docker volume already exists: $VOLUME_NAME"
    fi
else
    echo "  Docker not available — volume provisioning skipped."
fi

# Register agent as active
register_agent_active "$TARGET"

# ── Interactive: Model Configuration ─────────────────────────────────────────
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
            read_tty_rs "  OpenAI API key: " api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key — add later"
            ;;
        3)
            provider_name="anthropic"; base_url="https://api.anthropic.com/v1"; model_name="claude-sonnet-4-20250514"
            echo ""
            read_tty_rs "  Anthropic API key: " api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key — add later"
            ;;
        4)
            provider_name="groq"; base_url="https://api.groq.com/v1"; model_name="llama-3.3-70b-versatile"
            echo ""
            echo -n "  Groq API key: "
            read_tty_rs api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key — add later"
            ;;
        5)
            provider_name="mistral"; base_url="https://api.mistral.ai/v1"; model_name="mistral-large-latest"
            echo ""
            echo -n "  Mistral API key: "
            read_tty_rs api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key — add later"
            ;;
        6)
            provider_name="openrouter"; base_url="https://openrouter.ai/api/v1"; model_name="openai/gpt-4o"
            echo ""
            echo -n "  OpenRouter API key: "
            read_tty_rs api_key; echo ""
            [[ -z "$api_key" ]] && warn "No API key — add later"
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

    local config_file="$AGENTS_DIR/$TARGET/config.yaml"
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

    sed -i "s|\"model\":.*|\"model\": \"${provider_name}/${model_name}\"|" "$AGENTS_DIR/$TARGET/agent.json"
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

    local env_file="$AGENTS_DIR/$TARGET/.env"
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
            echo "  3. Copy the bot token"
            echo ""
            read_tty_rs "  Bot Token: " telegram_token; echo ""
            [[ -z "$telegram_token" ]] && { warn "Cancelled."; return; }
            _set_env "TELEGRAM_BOT_TOKEN" "$telegram_token"
            echo ""
            read_tty -rp "  Allowed users (comma-separated IDs, or 'all'): " allowed_users
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
            echo "  2. Create application, go to 'Bot' section"
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
            echo "  2. Create app, install to workspace"
            echo "  3. Copy Bot User OAuth Token (xoxb-...)"
            echo ""
            read_tty_rs "  Bot Token: " slack_token; echo ""
            [[ -z "$slack_token" ]] && { warn "Cancelled."; return; }
            _set_env "SLACK_BOT_TOKEN" "$slack_token"
            success "Slack configured (token: $(_mask "$slack_token"))"
            ;;
        4)
            echo ""
            echo "  1. Go to https://developers.facebook.com/apps/"
            echo "  2. Create WhatsApp Business app"
            echo "  3. Get Phone Number ID and Access Token"
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

# ── Run interactive prompts if in interactive mode ───────────────────────────
if is_interactive; then
    _configure_model
    _configure_channel
    _prompt_restart_gateway
fi

echo ""
echo "  Import complete."

# Clear failure trap — we succeeded
trap - EXIT
