#!/usr/bin/env bash
# install-agent.sh - Create agent workspace, install constitution + habits
# Usage: sudo ./install-agent.sh <agent-id> [workspace-path] [--single|--standalone]
#
# Modes:
#   Default (crew): Uses WORKSPACE_ROOT env or $HOME/agents/<id>
#   --single / --standalone: Path-agnostic, uses $HOME/agents/<id> or custom path

set -euo pipefail

show_help() {
    cat <<'EOF'
Install Agent - Create agent workspace with identity layer

Usage: sudo ./install-agent.sh <agent-id> [workspace-path] [--single|--standalone]

Arguments:
  agent-id        Agent identifier (e.g., synthesis-1, ui-a1b2)
  workspace-path  Optional custom workspace path

Options:
  --single, --standalone   Path-agnostic single agent mode
                           Uses $HOME/agents/<id> unless --workspace specified
  --workspace <path>       Explicit workspace path (overrides defaults)
  --help                   Show this help

Environment:
  WORKSPACE_ROOT     Root for crew agents (default: $HOME/agents)
  AGENT_IDENTITY_SKILL  Path to this skill (auto-detected)
  SKILL_DIR          Same as AGENT_IDENTITY_SKILL

Examples:
  # Crew agent (uses WORKSPACE_ROOT)
  sudo ./install-agent.sh ui-a1b2

  # Single standalone agent (path-agnostic)
  sudo ./install-agent.sh synthesis-1 --single

  # Single agent with custom path
  sudo ./install-agent.sh my-agent --workspace \${CUSTOM_WORKSPACE:-$HOME/agents/my-agent}

  # Crew agent with explicit path
  sudo ./install-agent.sh blockchain-c3d4 \${VENTOY_MOUNT:-\$HOME/crews}/prod-crew/agents/blockchain-c3d4
EOF
    exit 0
}

# Parse arguments
AGENT_ID=""
WORKSPACE_PATH=""
SINGLE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --single|--standalone) SINGLE_MODE=true; shift ;;
        --workspace) WORKSPACE_PATH="$2"; shift 2 ;;
        *)
            if [[ -z "$AGENT_ID" ]]; then
                AGENT_ID="$1"
            elif [[ -z "$WORKSPACE_PATH" ]]; then
                WORKSPACE_PATH="$1"
            else
                echo "ERROR: Too many arguments"
                show_help
            fi
            shift
            ;;
    esac
done

if [[ -z "$AGENT_ID" ]]; then
    echo "ERROR: agent-id required"
    show_help
fi

# Determine workspace path
if [[ -n "$WORKSPACE_PATH" ]]; then
    # Explicit path provided
    WORKSPACE="$WORKSPACE_PATH"
elif [[ "$SINGLE_MODE" == "true" ]]; then
    # Single/standalone mode - path agnostic, uses $HOME/agents
    WORKSPACE="${HOME}/agents/${AGENT_ID}"
else
    # Crew mode - uses WORKSPACE_ROOT
    WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/agents}"
    WORKSPACE="${WORKSPACE_ROOT}/${AGENT_ID}"
fi

SKILL_DIR="${AGENT_IDENTITY_SKILL:-${SKILL_DIR:-${HOME}/.hermes/skills/devops/agent-identity-architecture}}"

if [[ ! -d "$SKILL_DIR" ]]; then
    echo "ERROR: Skill directory not found: $SKILL_DIR"
    echo "Set AGENT_IDENTITY_SKILL or SKILL_DIR environment variable"
    exit 1
fi

echo "=== Creating agent: $AGENT_ID ==="
echo "Mode: $([[ "$SINGLE_MODE" == "true" ]] && echo "Single (standalone)" || echo "Crew")"
echo "Workspace: $WORKSPACE"

# 1. Create directory structure
mkdir -p "$WORKSPACE"/{.agent/{habits,logs,metrics,templates,constitutions},tools,skills,memory/{daily,weekly,long-term},.secrets}

# 2. Install constitution
cp "$SKILL_DIR/references/templates/constitution-template.yaml" "$WORKSPACE/.agent/constitution.yaml"
# Customize: agent name, purpose, etc.
sed -i "s/{{AGENT_ID}}/$AGENT_ID/g" "$WORKSPACE/.agent/constitution.yaml"
sed -i "s/{{AGENT_NAME}}/$(echo "$AGENT_ID" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')/g" "$WORKSPACE/.agent/constitution.yaml"
sed -i "s/{{DATE}}/$(date +%Y-%m-%d)/g" "$WORKSPACE/.agent/constitution.yaml"

# Add mode metadata
MODE_META=$([[ "$SINGLE_MODE" == "true" ]] && echo "standalone" || echo "crew")
sed -i "s/{{MODE}}/$MODE_META/g" "$WORKSPACE/.agent/constitution.yaml"

# 3. Install habits (if they exist)
if [[ -d "$SKILL_DIR/references" ]]; then
    for habit in tool-enforcement identity-enforcement reflective-loop; do
        if [[ -f "$SKILL_DIR/references/$habit.yaml" ]]; then
            cp "$SKILL_DIR/references/$habit.yaml" "$WORKSPACE/.agent/habits/"
        else
            echo "# $AGENT_ID identity habit: $habit" > "$WORKSPACE/.agent/habits/$habit.yaml"
        fi
    done
fi
cp "$SKILL_DIR/references/templates/habit-template.yaml" "$WORKSPACE/.agent/habits/example-habit.yaml"

# 4. Create agent.json with builder code placeholder
cat > "$WORKSPACE/.agent/agent.json" << EOF
{
  "agentId": "$AGENT_ID",
  "mode": "$MODE_META",
  "workspace": "$WORKSPACE",
  "builderCode": {
    "code": "SET_AFTER_REGISTRATION",
    "hex": "SET_AFTER_REGISTRATION",
    "owner": "SET_AFTER_REGISTRATION",
    "hardwired": true,
    "enforced": true
  },
  "identityLayer": "v1",
  "habits": ["identity-enforcement", "tool-enforcement", "reflective-loop"]
}
EOF

# 5. Set permissions
chmod -R 755 "$WORKSPACE/.agent" "$WORKSPACE/tools"
chmod 700 "$WORKSPACE/.secrets"
find "$WORKSPACE/.secrets" -type f -exec chmod 600 {} \; 2>/dev/null || true
find "$WORKSPACE/" -name "*.sh" -type f -exec chmod 755 {} \; 2>/dev/null || true

echo ""
echo "=== Agent workspace created: $WORKSPACE ==="
echo "Mode: $MODE_META"
echo "Next steps:"
echo "  1. Edit $WORKSPACE/.agent/constitution.yaml — customize core values, purpose, hard constraints"
echo "  2. Create $WORKSPACE/.agent/genesis.md — agent origin story"
echo "  3. Install enforcer daemon (from skill scripts/)"
echo "  4. Start agent runtime"
echo ""
echo "To verify:"
echo "  python3 -c \"import yaml; c=yaml.safe_load(open('$WORKSPACE/.agent/constitution.yaml')); print('✅', c['agent']['name'], 'constitution loaded')\""