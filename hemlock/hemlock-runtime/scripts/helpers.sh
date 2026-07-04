#!/bin/bash
# Helper functions for Hemlock Runtime
#
# Path resolution: In Docker containers, paths come from environment variables
# set by docker-compose.runtime.yml (e.g., AGENTS_DIR=/data/agents).
# On the host, paths are derived from RUNTIME_ROOT.
# Scripts should source helpers.sh AFTER setting SCRIPT_DIR, then use
# the resolved AGENTS_DIR, CREWS_DIR, etc.

# ── Path Resolution ──────────────────────────────────────────────────────────
# Resolve SCRIPT_DIR if not already set
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
RUNTIME_ROOT="${RUNTIME_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Container paths (env vars) take priority; host paths are the fallback
AGENTS_DIR="${AGENTS_DIR:-$RUNTIME_ROOT/agents}"
CREWS_DIR="${CREWS_DIR:-$RUNTIME_ROOT/crews}"
PROJECTS_DIR="${PROJECTS_DIR:-$RUNTIME_ROOT/projects}"
PLUGINS_DIR="${PLUGINS_DIR:-$RUNTIME_ROOT/plugins}"
CONFIG_DIR="${CONFIG_DIR:-$RUNTIME_ROOT/config}"
LOGS_DIR="${LOGS_DIR:-$RUNTIME_ROOT/logs}"
MEMORY_DIR="${MEMORY_DIR:-$RUNTIME_ROOT/memory}"
SKILLS_DIR="${SKILLS_DIR:-$RUNTIME_ROOT/skills}"
KNOWLEDGE_BASE_DIR="${KNOWLEDGE_BASE_DIR:-$RUNTIME_ROOT/knowledge_base}"
IMPORTS_DIR="${IMPORTS_DIR:-$RUNTIME_ROOT/volumes/imports}"
EXPORTS_DIR="${EXPORTS_DIR:-$RUNTIME_ROOT/volumes/exports}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$RUNTIME_ROOT/scripts}"

# Docker compose file for service management (may not exist in all contexts)
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-$RUNTIME_ROOT/docker-compose.yml}"

# ── Utility Functions ────────────────────────────────────────────────────────

# Generate random token
generate_random_token() {
    openssl rand -hex 16
}

# Check if agent exists. CL-018: identity file is "<id>.json" (per-agent
# isolation); accept legacy "agent.json" too for pre-CL-018 workspaces.
agent_exists() {
    local agent_id=$1
    [ -d "$AGENTS_DIR/$agent_id" ] && \
        { [ -f "$AGENTS_DIR/$agent_id/${agent_id}.json" ] || [ -f "$AGENTS_DIR/$agent_id/agent.json" ]; }
}

# Active/Archive registration helpers
register_agent_active() {
    local agent_id=$1
    mkdir -p "$AGENTS_DIR/active"
    ln -sfn "../$agent_id" "$AGENTS_DIR/active/$agent_id"
}

register_agent_archive() {
    local agent_id=$1
    mkdir -p "$AGENTS_DIR/archive"
    # Move the active symlink to archive, or create a reference
    if [ -L "$AGENTS_DIR/active/$agent_id" ]; then
        mv "$AGENTS_DIR/active/$agent_id" "$AGENTS_DIR/archive/$agent_id"
    elif [ -d "$AGENTS_DIR/$agent_id" ]; then
        ln -sfn "../$agent_id" "$AGENTS_DIR/archive/$agent_id"
    fi
}

unregister_agent_active() {
    local agent_id=$1
    rm -f "$AGENTS_DIR/active/$agent_id"
}

unregister_agent_archive() {
    local agent_id=$1
    rm -f "$AGENTS_DIR/archive/$agent_id"
}

get_agent_status() {
    local agent_id=$1
    local agent_json="$AGENTS_DIR/$agent_id/agent.json"
    if [ -f "$agent_json" ]; then
        python3 -c "import json; d=json.load(open('$agent_json')); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown"
    else
        echo "missing"
    fi
}

set_agent_status() {
    local agent_id=$1
    local new_status=$2
    local agent_json="$AGENTS_DIR/$agent_id/agent.json"
    if [ -f "$agent_json" ]; then
        python3 -c "
import json
with open('$agent_json', 'r') as f:
    d = json.load(f)
d['status'] = '$new_status'
with open('$agent_json', 'w') as f:
    json.dump(d, f, indent=2)
"
    fi
}

# List existing agents (status-based, no active/ directory)
list_existing_agents() {
    echo "Existing agents:"
    local count=0
    for agent_dir in "$AGENTS_DIR"/*/; do
        [[ -d "$agent_dir" ]] || continue
        local slug; slug=$(basename "$agent_dir")
        [[ "$slug" == "archive" || "$slug" == "templates" || "$slug" == "rules" || "$slug" == "envs" || "$slug" == "workflow" || "$slug" == "workspace-template" || "$slug" == "active" ]] && continue
        printf "  %-30s" "$slug"
        if [[ -f "$agent_dir/agent.json" ]]; then
            local status; status=$(python3 -c "import json; d=json.load(open('$agent_dir/agent.json')); print(d.get('status','unknown'))" 2>/dev/null || echo "unknown")
            printf " [%s]" "$status"
        fi
        echo ""
        count=$((count + 1))
    done
    if [[ $count -eq 0 ]]; then
        echo "  No agents found."
    fi
    echo "---------------------------------------------"
}

# Validate agent ID format
validate_agent_id() {
    local agent_id=$1
    if [[ ! "$agent_id" =~ ^[a-z][a-z0-9_-]{2,15}$ ]]; then
        echo "Invalid agent ID. Must be 3-16 chars, lowercase, start with letter, only a-z0-9_- allowed."
        return 1
    fi
    return 0
}

# Check if Docker is running
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Please install Docker."
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        echo "Docker daemon not running. Please start Docker."
        return 1
    fi
    
    return 0
}

# Check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose not found. Please install Docker Compose."
        return 1
    fi
    
    return 0
}

# Check if port is available
check_port_available() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        echo "Port $port is already in use."
        return 1
    fi
    
    return 0
}

# Create agent directory structure
create_agent_structure() {
    local agent_id=$1
    mkdir -p "$AGENTS_DIR/$agent_id/data" "$AGENTS_DIR/$agent_id/config" "$AGENTS_DIR/$agent_id/logs" "$AGENTS_DIR/$agent_id/skills" "$AGENTS_DIR/$agent_id/tools"
    
    # Create default config
    cat > "$AGENTS_DIR/$agent_id/config.yaml" <<EOL
agent:
  id: $agent_id
  name: $agent_id
  model: "ollama/qwen3:0.6b"
  personality: "default"
  memory:
    enabled: true
    max_chars: 100000
  tools:
    enabled: true
  security:
    read_only: true
    cap_drop: true
EOL
    
    # Create default SOUL.md
    cat > "$AGENTS_DIR/$agent_id/data/SOUL.md" <<EOL
# SOUL.md - $agent_id

**Identity:** $agent_id agent

**Purpose:** General purpose assistant

**Capabilities:**
- Natural language processing
- Task automation
- Memory and learning

**Limitations:**
- No physical capabilities
- Limited to available tools
EOL
    
    # Create default AGENTS.md
    cat > "$AGENTS_DIR/$agent_id/data/AGENTS.md" <<EOL
# AGENTS.md - $agent_id Workspace

This is the workspace for $agent_id agent.
EOL
}

# Validate YAML file
validate_yaml() {
    local file=$1
    if ! command -v yq &> /dev/null; then
        echo "yq not found. Skipping YAML validation."
        return 0
    fi
    
    if ! yq eval '.' "$file" &> /dev/null; then
        echo "Invalid YAML in $file"
        return 1
    fi
    
    return 0
}

# Log message
log() {
    local level=$1
    local message=${2:-}
    local logdir=${LOGS_DIR:-/tmp}
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" >> "$logdir/runtime.log" 2>/dev/null || :
}

# Agent log
agent_log() {
    local agent_id=$1
    local level=$2
    local message=$3
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    mkdir -p "$LOGS_DIR"
    echo "[$timestamp] [$level] $message" >> "$LOGS_DIR/$agent_id.log"
}

# Check if service is running. CL-017: docker is optional inside container
# (no socket per CL-012); gracefully return 1 when docker unreachable instead
# of letting bash's exit-on-error trip the caller.
is_service_running() {
    local service_name=$1
    command -v docker >/dev/null 2>&1 || return 1
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^$service_name$"
}

# Get agent container name
get_agent_container() {
    local agent_id=$1
    echo "hemlock_$agent_id"
}

# ── Docker Volume Helpers ────────────────────────────────────────────────────

VOLUME_PREFIX="${VOLUME_PREFIX:-hemlock}"

_volume_name() {
    echo "${VOLUME_PREFIX}_$1"
}

volume_exists() {
    local vol="$1"
    docker volume inspect "$vol" &>/dev/null
}

volume_copy_to() {
    local vol="$1" src="$2" dest="$3"
    if ! volume_exists "$vol"; then
        docker volume create "$vol" >/dev/null 2>&1
    fi
    docker run --rm -v "$vol:/vol" -v "$src:/src:ro" alpine \
        sh -c "cp -ra /src/. $dest 2>/dev/null || true"
}

volume_write_file() {
    local vol="$1" src="$2" dest="$3"
    if ! volume_exists "$vol"; then
        docker volume create "$vol" >/dev/null 2>&1
    fi
    docker run --rm -v "$vol:/vol" -v "$src:/src:ro" alpine \
        sh -c "cp -a /src $dest 2>/dev/null || true"
}

volume_copy_from() {
    local vol="$1" src="$2" dest="$3"
    mkdir -p "$dest"
    docker run --rm -v "$vol:/vol" -v "$dest:/dest" alpine \
        sh -c "cp -ra $src /dest/ 2>/dev/null || true"
}

volume_exec() {
    local vol="$1"
    shift
    docker run --rm -v "$vol:/vol" alpine sh -c "$*"
}

volume_agent_exists() {
    local vol="$1" agent_id="$2"
    volume_exists "$vol" && \
        docker run --rm -v "$vol:/vol" alpine test -d "/vol/$agent_id" 2>/dev/null
}

agent_volume() {
    _volume_name "agents_data"
}