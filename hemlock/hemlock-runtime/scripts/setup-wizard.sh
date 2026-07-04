#!/bin/bash
# =============================================================================
# Hemlock Enterprise Agent Framework — Interactive Setup Wizard
#
# Guides the user through:
#   1. Provider & model selection (Ollama local, OpenAI, Anthropic, Groq, …)
#   2. Gateway / runtime configuration
#   3. Creating or configuring agents
#   4. Creating or configuring crews
#
# Usage:  bash scripts/setup-wizard.sh [--agent | --crew | --provider | --all]
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

mkdir -p "$CONFIG_DIR" "$AGENTS_DIR"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';  BOLD='\033[1m';  NC='\033[0m'

# ── helpers ───────────────────────────────────────────────────────────────────
hr()      { printf '%*s\n' 70 '' | tr ' ' '─'; }
title()   { echo; echo -e "${BOLD}${CYAN}$*${NC}"; hr; }
ok()      { echo -e "  ${GREEN}✓${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $*"; }
err()     { echo -e "  ${RED}✗${NC}  $*"; }
info()    { echo -e "  ${BLUE}→${NC}  $*"; }
blank()   { echo; }

ask() {
    local prompt="$1" default="${2:-}" var_name="$3"
    local full_prompt
    if [[ -n "$default" ]]; then
        full_prompt="${BOLD}$prompt${NC} [${CYAN}$default${NC}]: "
    else
        full_prompt="${BOLD}$prompt${NC}: "
    fi
    while true; do
        echo -en "  $full_prompt"
        read -r reply
        reply="${reply:-$default}"
        if [[ -n "$reply" ]]; then
            printf -v "$var_name" '%s' "$reply"
            return 0
        fi
        warn "A value is required."
    done
}

ask_yn() {
    local prompt="$1" default="${2:-y}"
    local tag="[Y/n]"; [[ "${default,,}" == "n" ]] && tag="[y/N]"
    echo -en "  ${BOLD}$prompt${NC} $tag: "
    read -r reply
    reply="${reply:-$default}"
    [[ "${reply,,}" =~ ^y ]]
}

ask_choice() {
    local prompt="$1"; shift
    local options=("$@")
    echo -e "  ${BOLD}$prompt${NC}"
    local i=1
    for opt in "${options[@]}"; do
        printf "    %2d)  %s\n" "$i" "$opt"
        (( i++ ))
    done
    while true; do
        echo -en "  ${BOLD}Choice${NC}: "
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            CHOICE_RESULT="${options[$((choice-1))]}"
            return 0
        fi
        warn "Enter a number between 1 and ${#options[@]}."
    done
}

write_yaml_kv() {
    local file="$1" key="$2" value="$3"
    if grep -q "^  $key:" "$file" 2>/dev/null; then
        sed -i "s|^  $key:.*|  $key: \"$value\"|" "$file"
    fi
}

# ── Ollama helpers ────────────────────────────────────────────────────────────
OLLAMA_AVAILABLE=false
check_ollama() {
    if command -v ollama &>/dev/null && ollama list &>/dev/null 2>&1; then
        OLLAMA_AVAILABLE=true
    fi
}

ollama_model_pulled() {
    local tag="$1"
    ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$tag"
}

# ── Provider catalogue ────────────────────────────────────────────────────────
declare -A PROVIDER_LABELS=(
    [ollama]="Ollama (local — no API key needed)"
    [openai]="OpenAI (GPT-4o, GPT-4, GPT-3.5)"
    [anthropic]="Anthropic (Claude 3.5, Claude 3)"
    [groq]="Groq (fast inference — LLaMA, Mixtral)"
    [together]="Together AI (open-source models)"
    [mistral]="Mistral AI (Mistral Large, Devstral)"
    [custom]="Custom / self-hosted (any OpenAI-compatible endpoint)"
)

declare -A PROVIDER_MODELS=(
    [ollama]="qwen3:0.6b qwen3:1.7b qwen3:4b qwen3:8b qwen2.5:7b llama3.2:3b llama3.1:8b mistral:7b phi4:14b gemma3:4b"
    [openai]="gpt-4o gpt-4o-mini gpt-4-turbo gpt-4 gpt-3.5-turbo"
    [anthropic]="claude-3-5-sonnet-20241022 claude-3-5-haiku-20241022 claude-3-opus-20240229 claude-3-sonnet-20240229"
    [groq]="llama-3.3-70b-versatile llama-3.1-70b-versatile mixtral-8x7b-32768 gemma2-9b-it"
    [together]="meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo mistralai/Mixtral-8x22B-Instruct-v0.1"
    [mistral]="mistral-large-latest mistral-medium-latest mistral/devstral-2512 codestral-latest"
    [custom]=""
)

declare -A PROVIDER_ENV_VAR=(
    [ollama]=""
    [openai]="OPENAI_API_KEY"
    [anthropic]="ANTHROPIC_API_KEY"
    [groq]="GROQ_API_KEY"
    [together]="TOGETHER_API_KEY"
    [mistral]="MISTRAL_API_KEY"
    [custom]="CUSTOM_API_KEY"
)

# =============================================================================
# SECTION 1 — Welcome
# =============================================================================
show_welcome() {
    clear
    echo
    echo -e "${BOLD}${BLUE}"
    cat <<'BANNER'
  ██╗  ██╗███████╗███╗   ███╗██╗      ██████╗  ██████╗██╗  ██╗
  ██║  ██║██╔════╝████╗ ████║██║     ██╔═══██╗██╔════╝██║ ██╔╝
  ███████║█████╗  ██╔████╔██║██║     ██║   ██║██║     █████╔╝
  ██╔══██║██╔══╝  ██║╚██╔╝██║██║     ██║   ██║██║     ██╔═██╗
  ██║  ██║███████╗██║ ╚═╝ ██║███████╗╚██████╔╝╚██████╗██║  ██╗
  ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚══════╝ ╚═════╝  ╚═════╝╚═╝  ╚═╝
BANNER
    echo -e "${NC}"
    echo -e "  ${BOLD}Enterprise Agent Framework — Interactive Setup Wizard${NC}"
    echo -e "  $(date '+%Y-%m-%d %H:%M')"
    hr
    echo
    echo "  This wizard will guide you through:"
    echo "    1. Choosing a model provider (local Ollama or cloud APIs)"
    echo "    2. Selecting and verifying your model"
    echo "    3. Configuring the runtime gateway"
    echo "    4. Creating agents and/or crews"
    echo
    echo -e "  ${YELLOW}Tip:${NC} Press Enter to accept the value shown in [brackets]."
    echo -e "  ${YELLOW}Tip:${NC} Run with ${CYAN}--provider${NC}, ${CYAN}--agent${NC}, or ${CYAN}--crew${NC} to jump to a section."
    blank
}

# =============================================================================
# SECTION 2 — Provider & Model
# =============================================================================
section_provider() {
    title "STEP 1 — Model Provider"

    check_ollama

    echo "  Available providers:"
    blank

    local provider_list=(
        "ollama"
        "openai"
        "anthropic"
        "groq"
        "together"
        "mistral"
        "custom"
    )

    local i=1
    for p in "${provider_list[@]}"; do
        local label="${PROVIDER_LABELS[$p]}"
        local tag=""
        [[ "$p" == "ollama" ]] && {
            if $OLLAMA_AVAILABLE; then
                tag="${GREEN}(detected)${NC}"
            else
                tag="${YELLOW}(not found — will guide install)${NC}"
            fi
        }
        printf "    %2d)  %-50s %b\n" "$i" "$label" "$tag"
        (( i++ ))
    done

    blank
    while true; do
        echo -en "  ${BOLD}Choose provider${NC}: "
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#provider_list[@]} )); then
            SELECTED_PROVIDER="${provider_list[$((choice-1))]}"
            break
        fi
        warn "Enter a number between 1 and ${#provider_list[@]}."
    done

    blank
    ok "Selected provider: ${BOLD}$SELECTED_PROVIDER${NC}"

    # ── Ollama local setup ────────────────────────────────────────────────────
    if [[ "$SELECTED_PROVIDER" == "ollama" ]]; then
        blank
        if ! $OLLAMA_AVAILABLE; then
            warn "Ollama is not installed or not running on this system."
            echo
            echo "  To install Ollama:"
            echo -e "    ${CYAN}curl -fsSL https://ollama.com/install.sh | sh${NC}"
            echo
            echo "  Then start the Ollama service:"
            echo -e "    ${CYAN}ollama serve${NC}   (or use the desktop app)"
            echo
            if ask_yn "Open the Ollama install page in your browser?"; then
                xdg-open "https://ollama.com/download" 2>/dev/null || \
                open "https://ollama.com/download" 2>/dev/null || true
            fi
            blank
            info "Once Ollama is running, re-run this wizard or continue to set config values."
        fi

        blank
        echo "  Available Ollama models (recommended):"
        blank
        echo "    ── Lightweight (runs on CPU / low RAM) ──────────────────────────"
        echo "     1)  qwen3:0.6b           ~0.6 GB  ← DEFAULT (fast, very low RAM)"
        echo "     2)  qwen3:1.7b           ~1.7 GB  ← good quality / low RAM"
        echo "     3)  qwen2.5:0.5b         ~0.5 GB"
        echo "     4)  llama3.2:1b          ~1.3 GB"
        echo "    ── Mid-range (4-8 GB VRAM / RAM) ────────────────────────────────"
        echo "     5)  qwen3:4b             ~4 GB"
        echo "     6)  qwen3:8b             ~8 GB"
        echo "     7)  llama3.2:3b          ~3.2 GB"
        echo "     8)  llama3.1:8b          ~8 GB"
        echo "     9)  mistral:7b           ~7 GB"
        echo "    ── Large (12+ GB VRAM) ───────────────────────────────────────────"
        echo "    10)  llama3.1:70b         ~70 GB"
        echo "    11)  phi4:14b             ~14 GB"
        echo "    12)  qwen3:14b            ~14 GB"
        echo "    13)  Enter model manually"
        blank

        local model_map=(
            "qwen3:0.6b" "qwen3:1.7b" "qwen2.5:0.5b" "llama3.2:1b"
            "qwen3:4b"   "qwen3:8b"   "llama3.2:3b"   "llama3.1:8b"
            "mistral:7b" "llama3.1:70b" "phi4:14b"     "qwen3:14b"
        )

        while true; do
            echo -en "  ${BOLD}Choose model${NC} [1]: "
            read -r mchoice
            mchoice="${mchoice:-1}"
            if [[ "$mchoice" == "13" ]]; then
                ask "Enter Ollama model tag (e.g. qwen3:4b)" "qwen3:0.6b" SELECTED_MODEL
                break
            elif [[ "$mchoice" =~ ^[0-9]+$ ]] && (( mchoice >= 1 && mchoice <= 12 )); then
                SELECTED_MODEL="${model_map[$((mchoice-1))]}"
                break
            fi
            warn "Enter 1-13."
        done

        SELECTED_MODEL_FULL="ollama/$SELECTED_MODEL"

        blank
        ok "Selected model: ${BOLD}$SELECTED_MODEL_FULL${NC}"

        if $OLLAMA_AVAILABLE; then
            blank
            if ollama_model_pulled "$SELECTED_MODEL"; then
                ok "Model ${BOLD}$SELECTED_MODEL${NC} is already pulled locally."
            else
                if ask_yn "Pull model ${BOLD}$SELECTED_MODEL${NC} now? (requires ~$(echo "$SELECTED_MODEL" | grep -oP '\d+(\.\d+)?(?=[bB])' || echo '?') GB)"; then
                    blank
                    info "Running: ollama pull $SELECTED_MODEL"
                    ollama pull "$SELECTED_MODEL" && ok "Model pulled successfully." || warn "Pull failed — you can run 'ollama pull $SELECTED_MODEL' manually."
                else
                    warn "Remember to pull the model before running agents:  ollama pull $SELECTED_MODEL"
                fi
            fi
        fi

    # ── Cloud provider setup ──────────────────────────────────────────────────
    else
        local env_var="${PROVIDER_ENV_VAR[$SELECTED_PROVIDER]}"
        blank

        if [[ -n "$env_var" ]]; then
            local current_val="${!env_var:-}"
            if [[ -n "$current_val" ]]; then
                ok "${env_var} is already set in environment."
            else
                warn "${env_var} is not set."
                echo
                echo "  You can set it by adding to your .env file:"
                echo -e "    ${CYAN}echo '${env_var}=sk-...' >> .env${NC}"
                echo
                echo "  Or export it in your shell before running agents:"
                echo -e "    ${CYAN}export ${env_var}=sk-...${NC}"
                echo
                echo -en "  ${BOLD}Enter your ${env_var}${NC} (or press Enter to skip): "
                read -rs api_key_input
                echo
                if [[ -n "$api_key_input" ]]; then
                    # Write to .env file (append or create)
                    local env_file="$RUNTIME_ROOT/.env"
                    if grep -q "^${env_var}=" "$env_file" 2>/dev/null; then
                        sed -i "s|^${env_var}=.*|${env_var}=${api_key_input}|" "$env_file"
                    else
                        echo "${env_var}=${api_key_input}" >> "$env_file"
                    fi
                    ok "Saved ${env_var} to .env"
                fi
            fi
        fi

        blank
        local models_str="${PROVIDER_MODELS[$SELECTED_PROVIDER]}"
        read -ra model_opts <<< "$models_str"

        if [[ ${#model_opts[@]} -eq 0 ]]; then
            ask "Enter model name/path" "" BARE_MODEL
        else
            echo "  Available models for ${BOLD}$SELECTED_PROVIDER${NC}:"
            blank
            local mi=1
            for m in "${model_opts[@]}"; do
                printf "    %2d)  %s\n" "$mi" "$m"
                (( mi++ ))
            done
            local last_opt=$mi
            printf "    %2d)  Enter manually\n" "$last_opt"
            blank
            while true; do
                echo -en "  ${BOLD}Choose model${NC} [1]: "
                read -r mchoice
                mchoice="${mchoice:-1}"
                if [[ "$mchoice" == "$last_opt" ]]; then
                    ask "Enter model name" "" BARE_MODEL
                    break
                elif [[ "$mchoice" =~ ^[0-9]+$ ]] && (( mchoice >= 1 && mchoice < last_opt )); then
                    BARE_MODEL="${model_opts[$((mchoice-1))]}"
                    break
                fi
                warn "Enter 1-${last_opt}."
            done
        fi

        SELECTED_MODEL="$BARE_MODEL"
        SELECTED_MODEL_FULL="${SELECTED_PROVIDER}/${BARE_MODEL}"
        ok "Selected model: ${BOLD}$SELECTED_MODEL_FULL${NC}"
    fi

    # ── Persist chosen model to runtime config ────────────────────────────────
    blank
    info "Writing provider config to ${CONFIG_DIR}/runtime.yaml …"
    _save_provider_config
    ok "Provider configuration saved."
    blank
    read -rp "  Press Enter to continue …"
}

_save_provider_config() {
    local runtime_yaml="$CONFIG_DIR/runtime.yaml"

    if [[ ! -f "$runtime_yaml" ]]; then
        cat > "$runtime_yaml" <<EOF
runtime:
  gateway:
    port: 18789
    token: "change_this_to_a_secure_token"
    bind: "lan"
  agents:
    default_model: "ollama/qwen3:0.6b"
    default_provider: "ollama"
    default_network: "agents_net"
  security:
    read_only: true
    cap_drop: true
    icc: false
  logging:
    level: "info"
    max_size: "10m"
    max_files: 5
EOF
    fi

    sed -i "s|default_model:.*|default_model: \"${SELECTED_MODEL_FULL}\"|" "$runtime_yaml"
    sed -i "s|default_provider:.*|default_provider: \"${SELECTED_PROVIDER}\"|" "$runtime_yaml" 2>/dev/null || \
        sed -i "/default_model:/a\\    default_provider: \"${SELECTED_PROVIDER}\"" "$runtime_yaml"

    # Also write a .env fragment for provider
    local wizard_env="$RUNTIME_ROOT/.env.wizard"
    cat > "$wizard_env" <<EOF
# Generated by setup-wizard.sh on $(date '+%Y-%m-%d %H:%M')
MODEL_PROVIDER=${SELECTED_PROVIDER}
DEFAULT_MODEL=${SELECTED_MODEL_FULL}
EOF
    [[ "$SELECTED_PROVIDER" == "ollama" ]] && echo "OLLAMA_HOST=http://localhost:11434" >> "$wizard_env"
}

# =============================================================================
# SECTION 3 — Runtime / Gateway Configuration
# =============================================================================
section_runtime() {
    title "STEP 2 — Runtime & Gateway Configuration"

    local runtime_yaml="$CONFIG_DIR/runtime.yaml"
    local current_port current_bind

    current_port=$(grep "port:" "$runtime_yaml" 2>/dev/null | head -1 | awk '{print $2}' || echo "18789")
    current_bind=$(grep "bind:" "$runtime_yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "lan")

    echo "  The OpenClaw gateway handles agent communication."
    blank

    ask "Gateway port"       "$current_port" GW_PORT
    ask "Bind interface"     "$current_bind" GW_BIND

    blank
    echo "  Token configuration:"
    echo "   a)  Generate a secure random token (recommended)"
    echo "   b)  Enter a custom token"
    echo -en "  ${BOLD}Choice${NC} [a]: "
    read -r tok_choice
    tok_choice="${tok_choice:-a}"

    local GW_TOKEN
    if [[ "${tok_choice,,}" == "b" ]]; then
        echo -en "  ${BOLD}Token${NC}: "
        read -rs GW_TOKEN
        echo
    else
        GW_TOKEN=$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | xxd -p | tr -d '\n')
        ok "Generated token: ${CYAN}$GW_TOKEN${NC}"
    fi

    blank
    echo "  Logging level:"
    ask_choice "Select log level" "debug" "info" "warn" "error"
    LOG_LEVEL="${CHOICE_RESULT}"

    blank
    info "Updating runtime.yaml …"

    cat > "$runtime_yaml" <<EOF
runtime:
  gateway:
    port: ${GW_PORT}
    token: "${GW_TOKEN}"
    bind: "${GW_BIND}"
  agents:
    default_model: "${SELECTED_MODEL_FULL:-ollama/qwen3:0.6b}"
    default_provider: "${SELECTED_PROVIDER:-ollama}"
    default_network: "agents_net"
  security:
    read_only: true
    cap_drop: true
    icc: false
    tmpfs: true
    tmpfs_size: "64m"
  logging:
    level: "${LOG_LEVEL}"
    max_size: "10m"
    max_files: 5
EOF

    ok "Runtime configuration saved to config/runtime.yaml"
    blank
    echo "  ${YELLOW}Important:${NC} Add the gateway token to your environment:"
    echo -e "    ${CYAN}export OPENCLAW_GATEWAY_TOKEN=${GW_TOKEN}${NC}"

    # Append to .env
    local env_file="$RUNTIME_ROOT/.env"
    {
        grep -v "^OPENCLAW_GATEWAY_TOKEN=" "$env_file" 2>/dev/null || true
    } > "${env_file}.tmp" && mv "${env_file}.tmp" "$env_file" || true
    echo "OPENCLAW_GATEWAY_TOKEN=${GW_TOKEN}" >> "$env_file"
    ok "Token also written to .env"

    blank
    read -rp "  Press Enter to continue …"
}

# =============================================================================
# SECTION 4 — Agent Configuration
# =============================================================================
section_agent() {
    title "STEP 3 — Agent Configuration"

    local existing_agents=()
    while IFS= read -r -d '' d; do
        existing_agents+=("$(basename "$d")")
    done < <(find "$AGENTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    if [[ ${#existing_agents[@]} -gt 0 ]]; then
        echo "  Existing agents:"
        for ag in "${existing_agents[@]}"; do
            local ag_model
            ag_model=$(grep "model:" "$AGENTS_DIR/$ag/config.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "unknown")
            printf "    %-20s  model: %s\n" "$ag" "$ag_model"
        done
        blank

        echo "  Options:"
        echo "    1)  Create a new agent"
        echo "    2)  Update an existing agent's model/config"
        echo "    3)  Skip agent setup"
        blank
        echo -en "  ${BOLD}Choice${NC} [1]: "
        read -r ag_choice
        ag_choice="${ag_choice:-1}"
    else
        info "No agents found — proceeding to create your first agent."
        ag_choice="1"
    fi

    case "$ag_choice" in
        1) _create_agent ;;
        2) _update_agent ;;
        3) info "Agent setup skipped."; blank; return ;;
        *) info "Skipping."; return ;;
    esac

    blank
    read -rp "  Press Enter to continue …"
}

_create_agent() {
    blank
    echo "  ${BOLD}Create New Agent${NC}"
    hr
    blank

    local AGENT_ID AGENT_NAME AGENT_MODEL AGENT_PERSONALITY AGENT_MEMORY AGENT_PURPOSE

    while true; do
        ask "Agent ID (3-16 chars, lowercase, letters/numbers/_/-)" "" AGENT_ID
        if [[ "$AGENT_ID" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
            if [[ -d "$AGENTS_DIR/$AGENT_ID" ]]; then
                warn "Agent '${AGENT_ID}' already exists. Choose a different ID or use option 2 to update."
            else
                break
            fi
        else
            warn "Invalid ID — must be 3-16 chars, start with a lowercase letter, only a-z0-9_- allowed."
        fi
    done

    ask "Display name"          "$AGENT_ID"  AGENT_NAME
    ask "Purpose / role"        "General purpose assistant"  AGENT_PURPOSE
    ask "Model"                 "${SELECTED_MODEL_FULL:-ollama/qwen3:0.6b}"  AGENT_MODEL

    blank
    echo "  Personality preset:"
    ask_choice "Select personality" \
        "default (balanced)" \
        "assistant (helpful, concise)" \
        "analyst (methodical, detailed)" \
        "developer (code-focused)" \
        "researcher (thorough, citing sources)" \
        "custom (write your own)"
    case "$CHOICE_RESULT" in
        "default (balanced)")                 AGENT_PERSONALITY="default" ;;
        "assistant (helpful, concise)")       AGENT_PERSONALITY="assistant" ;;
        "analyst (methodical, detailed)")     AGENT_PERSONALITY="analyst" ;;
        "developer (code-focused)")           AGENT_PERSONALITY="developer" ;;
        "researcher (thorough, citing sources)") AGENT_PERSONALITY="researcher" ;;
        "custom (write your own)")
            ask "Enter personality description" "" AGENT_PERSONALITY ;;
    esac

    blank
    ask "Max memory (characters)" "100000" AGENT_MEMORY

    blank
    info "Creating agent '${AGENT_ID}' …"

    local agent_dir="$AGENTS_DIR/$AGENT_ID"
    mkdir -p "$agent_dir"/{config,data,logs,tools,skills,.secrets,.hermes,.archive}
    touch "$agent_dir/.env" "$agent_dir/.env.enc"
    chmod 700 "$agent_dir/.secrets"
    chmod 600 "$agent_dir/.env"

    cat > "$agent_dir/config.yaml" <<EOF
agent:
  id: ${AGENT_ID}
  name: "${AGENT_NAME}"
  model: "${AGENT_MODEL}"
  personality: "${AGENT_PERSONALITY}"
  purpose: "${AGENT_PURPOSE}"
  memory:
    enabled: true
    max_chars: ${AGENT_MEMORY}
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
EOF

    cat > "$agent_dir/SOUL.md" <<EOF
# SOUL.md — ${AGENT_ID}

**Identity:** ${AGENT_NAME}

**Purpose:** ${AGENT_PURPOSE}

**Model:** ${AGENT_MODEL}

**Personality:** ${AGENT_PERSONALITY}

**Capabilities:**
- Natural language understanding and generation
- Task automation and orchestration
- Memory and contextual awareness
- Tool use and skill execution

**Limitations:**
- No physical world access
- Bounded by available tools and skills
- Subject to model capability ceiling
EOF

    ok "Agent '${AGENT_ID}' created at agents/${AGENT_ID}/"
    blank

    # Offer to add another agent
    if ask_yn "Create another agent?"; then
        blank
        _create_agent
    fi
}

_update_agent() {
    blank
    local existing_agents=()
    while IFS= read -r -d '' d; do
        existing_agents+=("$(basename "$d")")
    done < <(find "$AGENTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    ask_choice "Which agent to update?" "${existing_agents[@]}"
    local target_agent="$CHOICE_RESULT"

    blank
    local current_model
    current_model=$(grep "model:" "$AGENTS_DIR/$target_agent/config.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "ollama/qwen3:0.6b")

    ask "New model" "$current_model" NEW_MODEL

    sed -i "s|model:.*|model: \"${NEW_MODEL}\"|" "$AGENTS_DIR/$target_agent/config.yaml"
    ok "Updated $target_agent → model: $NEW_MODEL"

    if ask_yn "Update personality / purpose too?"; then
        ask "Purpose" "" NEW_PURPOSE
        ask "Personality" "" NEW_PERSONALITY
        if grep -q "^  purpose:" "$AGENTS_DIR/$target_agent/config.yaml"; then
            sed -i "s|^  purpose:.*|  purpose: \"${NEW_PURPOSE}\"|" "$AGENTS_DIR/$target_agent/config.yaml"
        else
            sed -i "/personality:/a\\  purpose: \"${NEW_PURPOSE}\"" "$AGENTS_DIR/$target_agent/config.yaml"
        fi
        sed -i "s|^  personality:.*|  personality: \"${NEW_PERSONALITY}\"|" "$AGENTS_DIR/$target_agent/config.yaml"
        ok "Updated purpose and personality."
    fi
}

# =============================================================================
# SECTION 5 — Crew Configuration
# =============================================================================
section_crew() {
    title "STEP 4 — Crew Configuration"

    echo "  A crew is a named group of agents that collaborate on shared tasks."
    blank

    if ! ask_yn "Configure a crew now?"; then
        info "Crew setup skipped."
        blank
        return
    fi

    local CREW_NAME CREW_DESC CREW_STRATEGY

    while true; do
        ask "Crew name (3-16 chars, lowercase, letters/numbers/_/-)" "" CREW_NAME
        if [[ "$CREW_NAME" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
            break
        else
            warn "Invalid name — must be 3-16 chars, start with a lowercase letter, only a-z0-9_- allowed."
        fi
    done

    ask "Description" "Multi-agent crew" CREW_DESC

    blank
    ask_choice "Collaboration strategy" \
        "sequential (agents run one after another in order)" \
        "parallel (all agents run concurrently, results merged)" \
        "hierarchical (lead agent delegates to sub-agents)" \
        "vote (agents propose, majority vote decides)"
    case "$CHOICE_RESULT" in
        "sequential"*) CREW_STRATEGY="sequential" ;;
        "parallel"*)   CREW_STRATEGY="parallel"   ;;
        "hierarchical"*) CREW_STRATEGY="hierarchical" ;;
        "vote"*)       CREW_STRATEGY="vote" ;;
    esac

    blank
    # Select agents for crew
    local existing_agents=()
    while IFS= read -r -d '' d; do
        existing_agents+=("$(basename "$d")")
    done < <(find "$AGENTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    local CREW_AGENTS=()
    if [[ ${#existing_agents[@]} -gt 0 ]]; then
        echo "  Select agents to add to this crew:"
        blank
        local ai=1
        for ag in "${existing_agents[@]}"; do
            printf "    %2d)  %s\n" "$ai" "$ag"
            (( ai++ ))
        done
        printf "    %2d)  Done — no more agents\n" "$ai"
        blank
        while true; do
            echo -en "  ${BOLD}Add agent (number) or press ${CYAN}${ai}${NC}${BOLD} when done${NC}: "
            read -r pick
            if [[ "$pick" == "$ai" ]] || [[ -z "$pick" ]]; then
                break
            fi
            if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick < ai )); then
                local chosen="${existing_agents[$((pick-1))]}"
                if [[ " ${CREW_AGENTS[*]} " == *" $chosen "* ]]; then
                    warn "$chosen already in crew."
                else
                    CREW_AGENTS+=("$chosen")
                    ok "Added: $chosen"
                fi
            else
                warn "Enter a number 1-${ai}."
            fi
        done
    else
        warn "No existing agents found. Create agents first, then add them to a crew."
    fi

    # Write crew config
    local crew_dir="$CONFIG_DIR/crews"
    mkdir -p "$crew_dir"

    local crew_yaml="$crew_dir/${CREW_NAME}.yaml"
    {
        echo "crew:"
        echo "  name: \"${CREW_NAME}\""
        echo "  description: \"${CREW_DESC}\""
        echo "  strategy: \"${CREW_STRATEGY}\""
        echo "  agents:"
        if [[ ${#CREW_AGENTS[@]} -gt 0 ]]; then
            for ag in "${CREW_AGENTS[@]}"; do
                echo "    - id: \"${ag}\""
                echo "      model: \"$(grep 'model:' "$AGENTS_DIR/$ag/config.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "ollama/qwen3:0.6b")\""
            done
        else
            echo "    []"
        fi
        echo "  memory:"
        echo "    shared: true"
        echo "    max_chars: 500000"
    } > "$crew_yaml"

    ok "Crew '${CREW_NAME}' configured at config/crews/${CREW_NAME}.yaml"
    blank

    if [[ ${#CREW_AGENTS[@]} -gt 0 ]]; then
        echo "  Crew members:"
        for ag in "${CREW_AGENTS[@]}"; do
            echo -e "    ${GREEN}•${NC} $ag"
        done
    else
        warn "Crew has no members — add agents with:  ./runtime.sh crew-join $CREW_NAME <agent-id>"
    fi

    blank
    if ask_yn "Configure another crew?"; then
        blank
        section_crew
    fi

    blank
    read -rp "  Press Enter to continue …"
}

# =============================================================================
# SECTION 6 — Summary & Next Steps
# =============================================================================
section_summary() {
    title "Setup Complete — Summary"

    echo -e "  ${GREEN}Provider:${NC}  ${SELECTED_PROVIDER:-not set}"
    echo -e "  ${GREEN}Model:${NC}     ${SELECTED_MODEL_FULL:-not set}"
    blank

    # List created agents
    local agent_count=0
    while IFS= read -r -d '' d; do
        (( agent_count++ ))
        local ag
        ag="$(basename "$d")"
        local ag_model
        ag_model=$(grep "model:" "$AGENTS_DIR/$ag/config.yaml" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "?")
        echo -e "  ${GREEN}Agent:${NC}     $ag  (${ag_model})"
    done < <(find "$AGENTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    [[ $agent_count -eq 0 ]] && warn "No agents configured yet."

    # List crews
    local crew_count=0
    local crews_dir="$CONFIG_DIR/crews"
    if [[ -d "$crews_dir" ]]; then
        for cf in "$crews_dir"/*.yaml; do
            [[ -f "$cf" ]] || continue
            (( crew_count++ ))
            local cn
            cn=$(grep "^  name:" "$cf" | head -1 | awk '{print $2}' | tr -d '"' || basename "$cf" .yaml)
            echo -e "  ${GREEN}Crew:${NC}      $cn"
        done
    fi

    blank
    hr
    echo
    echo -e "  ${BOLD}Next steps:${NC}"
    blank

    if [[ "${SELECTED_PROVIDER:-}" == "ollama" ]]; then
        echo "  1.  Ensure Ollama is running:"
        echo -e "        ${CYAN}ollama serve${NC}"
        echo "  2.  Verify the model is available:"
        echo -e "        ${CYAN}ollama list${NC}"
        blank
    fi

    echo "  Run all validation checks:"
    echo -e "    ${CYAN}bash tests/run_all.sh validation${NC}"
    blank
    echo "  Start an agent:"
    if [[ $agent_count -gt 0 ]]; then
        local first_agent
        first_agent=$(find "$AGENTS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | head -1)
        echo -e "    ${CYAN}bash scripts/agent-control.sh start ${first_agent}${NC}"
    else
        echo -e "    ${CYAN}bash scripts/agent-create.sh --id myagent --model ollama/qwen3:0.6b${NC}"
    fi
    blank
    echo "  Run the full setup wizard again at any time:"
    echo -e "    ${CYAN}bash scripts/setup-wizard.sh${NC}"
    echo "  Jump to a specific section:"
    echo -e "    ${CYAN}bash scripts/setup-wizard.sh --provider${NC}"
    echo -e "    ${CYAN}bash scripts/setup-wizard.sh --agent${NC}"
    echo -e "    ${CYAN}bash scripts/setup-wizard.sh --crew${NC}"
    blank
    hr
}

# =============================================================================
# MAIN — argument parsing and flow control
# =============================================================================

# Initialise globals so sections can reference them even if skipped
SELECTED_PROVIDER="${MODEL_PROVIDER:-ollama}"
SELECTED_MODEL="${DEFAULT_MODEL_TAG:-qwen3:0.6b}"
SELECTED_MODEL_FULL="${DEFAULT_MODEL:-ollama/qwen3:0.6b}"

# Source .env.wizard if present (from previous wizard run)
[[ -f "$RUNTIME_ROOT/.env.wizard" ]] && source "$RUNTIME_ROOT/.env.wizard" 2>/dev/null || true

MODE="${1:-all}"

case "$MODE" in
    --provider|-p)
        show_welcome
        section_provider
        section_summary
        ;;
    --runtime|-r)
        show_welcome
        section_runtime
        section_summary
        ;;
    --agent|-a)
        show_welcome
        section_agent
        section_summary
        ;;
    --crew|-c)
        show_welcome
        section_crew
        section_summary
        ;;
    --all|all|"")
        show_welcome
        if ! ask_yn "Run full setup wizard (provider → runtime → agent → crew)?" "y"; then
            blank
            echo "  ${BOLD}Quick-start menu:${NC}"
            ask_choice "What would you like to do?" \
                "Configure provider & model" \
                "Configure runtime / gateway" \
                "Create or update an agent" \
                "Create or update a crew" \
                "Exit"
            case "$CHOICE_RESULT" in
                "Configure provider & model")   section_provider; section_summary ;;
                "Configure runtime / gateway")  section_runtime;  section_summary ;;
                "Create or update an agent")    section_agent;    section_summary ;;
                "Create or update a crew")      section_crew;     section_summary ;;
                "Exit") exit 0 ;;
            esac
        else
            section_provider
            section_runtime
            section_agent
            section_crew
            section_summary
        fi
        ;;
    --help|-h)
        echo "Usage: $0 [--all | --provider | --runtime | --agent | --crew | --help]"
        echo
        echo "  --all        Run the full interactive wizard (default)"
        echo "  --provider   Configure model provider and model selection only"
        echo "  --runtime    Configure gateway / runtime.yaml only"
        echo "  --agent      Create or update agents only"
        echo "  --crew       Create or update crews only"
        echo "  --help       Show this help"
        exit 0
        ;;
    *)
        err "Unknown option: $MODE"
        echo "Run with --help for usage."
        exit 1
        ;;
esac
