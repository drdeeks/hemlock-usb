#!/bin/bash
# =============================================================================
# pm-create.sh — Create Project Manager Agent
#
# Creates a Project Manager agent with model warning and plugin injection.
#
# Usage:
#   ./scripts/pm-create.sh [--model <model>]
#
# Options:
#   --model <model>  Select model (default: ollama/qwen2.5-coder:32b)
#
# Models:
#   1. ollama/qwen2.5-coder:32b (recommended)
#   2. ollama/qwen2.5-coder:16b
#   3. ollama/qwen2.5-coder:7b
#   4. ollama/qwen2.5-coder:3b
#   5. ollama/qwen2.5-coder:1.8b
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

mkdir -p "$AGENTS_DIR" "$LOGS_DIR" "$CONFIG_DIR"

# =============================================================================
# DEFAULTS
# =============================================================================

MODEL=""

# =============================================================================
# HELPERS
# =============================================================================

info()    { echo "  $*"; }
success() { echo "  [OK] $*"; }
warn()    { echo "  [WARN] $*" >&2; }
die()     { echo "  [ERROR] $*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [--model <model>]

Create a Project Manager agent with model warning and plugin injection.

Options:
  --model <model>  Select model (default: ollama/qwen2.5-coder:32b)

Models:
  1. ollama/qwen2.5-coder:32b (recommended)
  2. ollama/qwen2.5-coder:16b
  3. ollama/qwen2.5-coder:7b
  4. ollama/qwen2.5-coder:3b
  5. ollama/qwen2.5-coder:1.8b

Examples:
  $(basename "$0")
  $(basename "$0") --model ollama/qwen2.5-coder:16b
EOF
    exit 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --model)       MODEL="$2"; shift 2 ;;
        -h|--help)     usage ;;
        -*) die "Unknown flag: $1 (try --help)" ;;
        *)  die "Unexpected argument: $1" ;;
    esac
done

# =============================================================================
# MODEL SELECTION
# =============================================================================

if [[ -z "$MODEL" ]]; then
    echo ""
    echo "=== PROJECT MANAGER MODEL SELECTION ==="
    echo ""
    echo "  ⚠️  MODEL WARNING:"
    echo "     Project Manager agents are NOT RECOMMENDED for models <7b"
    echo "     Recommended model: ollama/qwen2.5-coder:32b"
    echo ""
    echo "  Available models:"
    echo "    1. ollama/qwen2.5-coder:32b (recommended)"
    echo "    2. ollama/qwen2.5-coder:16b"
    echo "    3. ollama/qwen2.5-coder:7b"
    echo "    4. ollama/qwen2.5-coder:3b"
    echo "    5. ollama/qwen2.5-coder:1.8b"
    echo ""
    
    read -p "  Select model (1-5): " -n 1 -r MODEL_CHOICE
    echo ""
    
    case $MODEL_CHOICE in
        1) MODEL="ollama/qwen2.5-coder:32b" ;;
        2) MODEL="ollama/qwen2.5-coder:16b" ;;
        3) MODEL="ollama/qwen2.5-coder:7b" ;;
        4) MODEL="ollama/qwen2.5-coder:3b" ;;
        5) MODEL="ollama/qwen2.5-coder:1.8b" ;;
        *)
            warn "Invalid choice, using recommended model"
            MODEL="ollama/qwen2.5-coder:32b" ;;
    esac
    
    echo "  Selected model: $MODEL"
    echo ""
fi

# =============================================================================
# CREATE PM AGENT
# =============================================================================

PM_ID="project-manager"

info "Creating Project Manager agent: $PM_ID"

# Call agent-create.sh with selected model
"$SCRIPT_DIR/agent-create.sh" --id "$PM_ID" --model "$MODEL"

# =============================================================================
# CREATE PM IDENTITY
# =============================================================================

info "Creating Project Manager identity"

cat > "$AGENTS_DIR/$PM_ID/identity.md" <<EOL
# PROJECT MANAGER IDENTITY

**Core Identity:**
- Autonomous project management agent
- Mission: Coordinate and oversee project execution
- Behavioral Profile: Analytical, strategic, proactive
- Autonomy Level: Maximum

**Injected Plugins:**
- project-coordination
- crew-management
- quality-validation
- autonomous-loop
- dormant-marking

**Mission Statement:**
To autonomously manage projects from conception to completion, ensuring quality, efficiency, and user satisfaction.

**Behavioral Profile:**
- Analytical: Comprehensive project analysis
- Strategic: Optimal resource allocation
- Proactive: Anticipate and prevent issues
- Adaptive: Adjust to changing requirements
- Collaborative: Effective team coordination

**Autonomy Level:**
Maximum - Fully autonomous operation with user confirmation for critical decisions.

**Skills:**
- Project planning and blueprint creation
- Crew creation and management
- Progress monitoring and quality validation
- User approval workflow
- Dormant marking and retrospective analysis
EOL

# =============================================================================
# INJECT PM PLUGINS
# =============================================================================

info "Injecting Project Manager plugins"

# Use plugin manager to inject plugins
PYTHONPATH="$RUNTIME_ROOT/docker/hermes-agent" python3 -m plugins.cli inject --agent "$PM_ID" --plugins project-coordination,crew-management,quality-validation,autonomous-loop,dormant-marking

# =============================================================================
# FINALIZATION
# =============================================================================

success "Project Manager agent created successfully: $PM_ID"
echo ""
echo "  Agent ID:   $PM_ID"
echo "  Model:      $MODEL"
echo "  Plugins:    project-coordination, crew-management, quality-validation, autonomous-loop, dormant-marking"
echo ""
echo "  Next steps:"
echo "    1. Start the agent: ./scripts/agent-control.sh start $PM_ID"
echo "    2. Monitor progress: ./scripts/agent-logs.sh $PM_ID"
echo "    3. Define mission: python3 -m project.manager autonomous_loop"
echo ""
