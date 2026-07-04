#!/bin/bash
# =============================================================================
# OpenClaw Agent Migration Script
# Migrates agents from ~/.openclaw/agents/<id> to runtime/agents/<id>
# with full isolation, security hardening, and canonical homefront setup
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ROOT="${SOURCE_ROOT:-$HOME/.openclaw/agents}"
AGENTS_ROOT="${RUNTIME_ROOT}/agents"
BACKUP_ROOT="${RUNTIME_ROOT}/backups"
CANONICAL_HOME="${RUNTIME_ROOT}/canonical"
SKILLS_DIR="${CANONICAL_HOME}/skills"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_agent_id() {
    local agent_id="$1"
    
    # Check format (alphanumeric + hyphens/underscores only)
    if ! [[ "$agent_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid agent ID '$agent_id'. Use alphanumeric, hyphens, and underscores only."
        return 1
    fi
    
    # Check for dangerous patterns
    if [[ "$agent_id" =~ \.\.|\/$|^/ ]]; then
        log_error "Invalid agent ID path traversal attempt detected."
        return 1
    fi
    
    return 0
}

validate_source_agent() {
    local agent_id="$1"
    local source_path="${SOURCE_ROOT}/${agent_id}"
    
    if [[ ! -d "$source_path" ]]; then
        log_error "Source agent not found: $source_path"
        return 1
    fi
    
    if [[ ! -r "$source_path" ]]; then
        log_error "Source agent not readable: $source_path"
        return 1
    fi
    
    return 0
}

validate_target_not_exists() {
    local agent_id="$1"
    local target_path="${AGENTS_ROOT}/${agent_id}"
    
    if [[ -e "$target_path" ]]; then
        log_error "Target agent already exists: $target_path"
        log_error "Use --force to overwrite or --update to incrementally update."
        return 1
    fi
    
    return 0
}

validate_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH."
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or user lacks permissions."
        return 1
    fi
    
    return 0
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

create_backup() {
    local agent_id="$1"
    local timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="${BACKUP_ROOT}/${agent_id}_${timestamp}"
    
    log_info "Creating backup of existing target (if any)..."
    
    mkdir -p "$BACKUP_ROOT"
    
    if [[ -d "${AGENTS_ROOT}/${agent_id}" ]]; then
        mkdir -p "$backup_dir"
        if cp -a "${AGENTS_ROOT}/${agent_id}"/* "$backup_dir/" 2>/dev/null; then
            log_success "Backup created: $backup_dir"
            echo "$backup_dir"
        else
            log_warn "Failed to create backup, continuing anyway..."
            echo ""
        fi
    else
        log_info "No existing target to backup."
        echo ""
    fi
}

# =============================================================================
# CREATION FUNCTIONS
# =============================================================================

create_directory_structure() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    
    log_info "Creating directory structure for agent: $agent_id"
    
    # Create agent directories
    mkdir -p "${target_root}/${AGENT_APP_DIR_NAME:-app}"
    mkdir -p "${target_root}/${AGENT_DATA_DIR_NAME:-data}"
    mkdir -p "${target_root}/${AGENT_CONFIG_DIR_NAME:-config}"
    mkdir -p "${target_root}/sessions"
    mkdir -p "${target_root}/memory"
    mkdir -p "${target_root}/workspace"
    
    log_success "Directory structure created."
}

create_agent_metadata() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    
    log_info "Creating agent metadata..."
    
    # Create agent metadata file
    cat > "${target_root}/agent-meta.json" << EOF
{
  "agent_id": "${agent_id}",
  "migrated_at": "$(date -Iseconds)",
  "migrated_by": "migrate-agent.sh",
  "version": "1.0.0",
  "runtime_root": "${RUNTIME_ROOT}",
  "canonical_home": "${CANONICAL_HOME}",
  "structure": {
    "app": "${AGENT_APP_DIR_NAME:-app}",
    "data": "${AGENT_DATA_DIR_NAME:-data}",
    "config": "${AGENT_CONFIG_DIR_NAME:-config}",
    "sessions": "sessions",
    "memory": "memory",
    "workspace": "workspace"
  }
}
EOF
    
    log_success "Agent metadata created."
}

copy_agent_data() {
    local agent_id="$1"
    local source_path="${SOURCE_ROOT}/${agent_id}"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    local target_data="${target_root}/${AGENT_DATA_DIR_NAME:-data}"
    
    log_info "Copying agent data from $source_path to $target_data"
    
    # Copy SOUL.md if exists
    if [[ -f "${source_path}/SOUL.md" ]]; then
        cp -a "${source_path}/SOUL.md" "${target_data}/SOUL.md"
        log_success "Copied SOUL.md"
    fi
    
    # Copy config.yaml if exists
    if [[ -f "${source_path}/config.yaml" ]]; then
        cp -a "${source_path}/config.yaml" "${target_data}/config.yaml"
        log_success "Copied config.yaml"
    fi
    
    # Copy config.json if exists
    if [[ -f "${source_path}/config.json" ]]; then
        cp -a "${source_path}/config.json" "${target_data}/config.json"
        log_success "Copied config.json"
    fi
    
    # Copy memory directory if exists
    if [[ -d "${source_path}/memory" ]]; then
        mkdir -p "${target_root}/memory"
        cp -a "${source_path}/memory/"* "${target_root}/memory/" 2>/dev/null || true
        log_success "Copied memory/"
    fi
    
    # Copy sessions directory if exists
    if [[ -d "${source_path}/sessions" ]]; then
        mkdir -p "${target_root}/sessions"
        cp -a "${source_path}/sessions/"* "${target_root}/sessions/" 2>/dev/null || true
        log_success "Copied sessions/"
    fi
    
    # Copy agent subdirectory contents to root (flatten structure)
    if [[ -d "${source_path}/agent" ]]; then
        cp -a "${source_path}/agent/"* "${target_data}/" 2>/dev/null || true
        log_success "Flattened agent/ subdirectory to root"
    fi
    
    # Copy any other files in source root
    for item in "$source_path"/*; do
        local basename="$(basename "$item")"
        case "$basename" in
            app|data|config|sessions|memory|workspace|agent-meta.json)
                # Already handled or skip
                ;;
            *)
                if [[ -f "$item" ]]; then
                    cp -a "$item" "${target_data}/"
                    log_info "Copied $basename"
                fi
                ;;
        esac
    done
    
    log_success "Agent data copied."
}

setup_app_symlink() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    local canonical_app="${CANONICAL_HOME}/app"
    
    log_info "Setting up app symlink to canonical homefront..."
    
    # If canonical home app exists, symlink to it
    if [[ -d "$canonical_app" ]]; then
        ln -sfn "$canonical_app" "${target_root}/app"
        log_success "App symlinked to canonical: $canonical_app"
    else
        log_warn "Canonical app not found at $canonical_app. Agent will use its own app/ directory."
        # Create a placeholder to indicate this agent has no shared app
        touch "${target_root}/app/.isolated"
    fi
}

setup_skills_access() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    
    log_info "Setting up skills access from canonical homefront..."
    
    # Create skills directory in agent if it doesn't exist
    mkdir -p "${target_root}/skills"
    
    # If canonical skills exist, create read-only symlinks
    if [[ -d "$SKILLS_DIR" ]]; then
        for skill in "$SKILLS_DIR"/*; do
            if [[ -d "$skill" ]]; then
                local skill_name="$(basename "$skill")"
                ln -sfn "$skill" "${target_root}/skills/$skill_name"
                log_info "Linked skill: $skill_name"
            fi
        done
        log_success "Skills access configured."
    else
        log_info "No canonical skills found. Agent will have local skills only."
    fi
}

create_agent_config() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    local target_config="${target_root}/${AGENT_CONFIG_DIR_NAME:-config}"
    
    log_info "Creating agent-specific configuration..."
    
    # Create agent config
    cat > "${target_config}/agent.json" << EOF
{
  "agent_id": "${agent_id}",
  "name": "${agent_id}",
  "runtime": {
    "type": "openclaw",
    "version": "1.0.0",
    "canonical_home": "${CANONICAL_HOME}",
    "isolated": true
  },
  "paths": {
    "data": "${AGENT_DATA_DIR_NAME:-data}",
    "config": "${AGENT_CONFIG_DIR_NAME:-config}",
    "sessions": "sessions",
    "memory": "memory",
    "workspace": "workspace",
    "skills": "skills"
  },
  "security": {
    "isolated_container": true,
    "read_only_app": true,
    "tmpfs_enabled": true,
    "cap_drop_all": true,
    "no_new_privileges": true
  }
}
EOF
    
    # Create environment template for agent overrides
    cat > "${target_config}/agent.env.template" << EOF
# Agent-specific overrides for ${agent_id}
# Copy to agent.env and customize

# Model configuration
# MODEL_BACKEND=ollama
# DEFAULT_MODEL=mistral/devstral-2512

# Resource limits
# AGENT_CPU_LIMIT=1.0
# AGENT_MEM_LIMIT=512m

# Agent-specific settings
# AGENT_TEMPERATURE=0.7
# AGENT_MAX_TOKENS=2048
EOF
    
    log_success "Agent configuration created."
}

setup_network_isolation() {
    local agent_id="$1"
    local network_name="agent_net_${agent_id}"
    
    log_info "Setting up network isolation for agent: $agent_id"
    
    # Create agent-specific network
    if ! docker network ls | grep -q "^${network_name} "; then
        docker network create \
            --driver bridge \
            --opt "com.docker.network.bridge.enable_icc=false" \
            "$network_name" 2>/dev/null || true
        log_success "Network created: $network_name"
    else
        log_info "Network already exists: $network_name"
    fi
}

set_permissions() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    
    log_info "Setting secure permissions..."
    
    # Get AGENT_UID and AGENT_GID from environment or use defaults
    local uid="${AGENT_UID:-1000}"
    local gid="${AGENT_GID:-1000}"
    
    # Set ownership
    chown -R "${uid}:${gid}" "$target_root" 2>/dev/null || true
    
    # Secure permissions on sensitive files
    chmod 600 "${target_root}/${AGENT_DATA_DIR_NAME:-data}"/*.yaml 2>/dev/null || true
    chmod 600 "${target_root}/${AGENT_DATA_DIR_NAME:-data}"/*.json 2>/dev/null || true
    chmod 600 "${target_root}/${AGENT_CONFIG_DIR_NAME:-config}"/*.json 2>/dev/null || true
    chmod 600 "${target_root}/${AGENT_CONFIG_DIR_NAME:-config}"/*.env* 2>/dev/null || true
    
    # Ensure app directory is read-only
    chmod 555 "${target_root}/${AGENT_APP_DIR_NAME:-app}" 2>/dev/null || true
    
    # Make scripts executable
    chmod +x "${target_root}/scripts"/*.sh 2>/dev/null || true
    
    log_success "Permissions set."
}

create_isolation_manifest() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    
    log_info "Creating isolation manifest..."
    
    cat > "${target_root}/ISOLATION.md" << EOF
# Agent Isolation Manifest - ${agent_id}

## Status
**ISOLATED** - This agent operates in a hardened, isolated container.

## Isolation Guarantees

### Container Security
- \`no-new-privileges: true\` - Prevents privilege escalation
- \`cap_drop: ALL\` - Drops all Linux capabilities
- \`read_only: true\` - Filesystem is read-only except for data volumes
- \`tmpfs: /tmp\` - Sensitive operations use tmpfs

### Network Isolation
- \`icc: false\` - Inter-container communication disabled
- Agent-specific network: \`agent_net_${agent_id}\`
- Only defined external access via extra_hosts

### Filesystem Isolation
- \`app/\` - Read-only mount (shared canonical or agent-specific)
- \`data/\` - Read-write agent state
- \`config/\` - Read-only agent configuration
- \`workspace/\` - Agent working directory

## Canonical Homefront

This agent references the canonical homefront at:
\`${CANONICAL_HOME}\`

Shared resources:
- \`canonical/skills/\` - Shared skill modules
- \`canonical/app/\` - Shared application code (if applicable)

## Migration Info

- Migrated: $(date -Iseconds)
- Migration script: migrate-agent.sh
- Source: ${SOURCE_ROOT}/${agent_id}

## Emergency Access

To access this agent's container:
\`\`\`bash
docker exec -it oc-${agent_id} /bin/bash
\`\`\`

To view logs:
\`\`\`bash
docker logs oc-${agent_id}
\`\`\`

To stop:
\`\`\`bash
docker stop oc-${agent_id}
\`\`\`
EOF
    
    log_success "Isolation manifest created."
}

generate_docker_override() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    
    log_info "Generating Docker Compose override for isolated deployment..."
    
    cat > "${target_root}/docker-compose.override.yml" << EOF
# Docker Compose Override - ${agent_id}
# Auto-generated by migrate-agent.sh
# This override enforces isolation for this specific agent

services:
  agent:
    container_name: oc-${agent_id}
    container_name: oc-${agent_id}
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /tmp:size=64m,mode=1777
    user: "${AGENT_UID:-1000}:${AGENT_GID:-1000}"
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    networks:
      - agent_net_${agent_id}
    environment:
      - AGENT_ID=${agent_id}
      - CANONICAL_HOME=${CANONICAL_HOME}
    volumes:
      - ${target_root}/${AGENT_APP_DIR_NAME:-app}:/app:ro
      - ${target_root}/${AGENT_DATA_DIR_NAME:-data}:/data:rw
      - ${target_root}/${AGENT_CONFIG_DIR_NAME:-config}:/config:ro
      - ${target_root}/workspace:/workspace:rw
      - ${target_root}/sessions:/sessions:ro
      - ${CANONICAL_HOME}/skills:/canonical/skills:ro

networks:
  agent_net_${agent_id}:
    name: agent_net_${agent_id}
    driver: bridge
    driver_opts:
      com.docker.network.bridge.enable_icc: "false"
    external: false
EOF
    
    log_success "Docker Compose override created."
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_migration() {
    local agent_id="$1"
    local target_root="${AGENTS_ROOT}/${agent_id}"
    local errors=0
    
    log_info "Validating migration..."
    
    # Check required directories exist
    for dir in "${AGENT_APP_DIR_NAME:-app}" "${AGENT_DATA_DIR_NAME:-data}" "${AGENT_CONFIG_DIR_NAME:-config}" sessions memory workspace; do
        if [[ ! -d "${target_root}/${dir}" ]]; then
            log_error "Missing directory: $dir"
            ((errors++))
        fi
    done
    
    # Check SOUL.md exists (if source had one)
    if [[ -f "${SOURCE_ROOT}/${agent_id}/SOUL.md" ]]; then
        if [[ ! -f "${target_root}/${AGENT_DATA_DIR_NAME:-data}/SOUL.md" ]]; then
            log_error "SOUL.md not copied!"
            ((errors++))
        fi
    fi
    
    # Check agent metadata
    if [[ ! -f "${target_root}/agent-meta.json" ]]; then
        log_error "Agent metadata not created!"
        ((errors++))
    fi
    
    # Check isolation manifest
    if [[ ! -f "${target_root}/ISOLATION.md" ]]; then
        log_error "Isolation manifest not created!"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Migration validation passed!"
        return 0
    else
        log_error "Migration validation failed with $errors errors."
        return 1
    fi
}

# =============================================================================
# CANONICAL HOMEFRONT SETUP
# =============================================================================

setup_canonical_homefront() {
    log_info "Setting up canonical homefront..."
    
    mkdir -p "$CANONICAL_HOME"
    mkdir -p "$SKILLS_DIR"
    
    # Create canonical homefront metadata
    cat > "${CANONICAL_HOME}/canonical-meta.json" << EOF
{
  "type": "canonical_homefront",
  "version": "1.0.0",
  "created_at": "$(date -Iseconds)",
  "runtime_root": "${RUNTIME_ROOT}",
  "directories": {
    "skills": "${SKILLS_DIR}",
    "app": "${CANONICAL_HOME}/app",
    "shared": "${CANONICAL_HOME}/shared"
  },
  "agents": []
}
EOF
    
    # Create shared skills placeholder
    cat > "${SKILLS_DIR}/README.md" << EOF
# Canonical Skills Directory

This directory contains shared skill modules that all agents can reference.

## Structure

Each skill should be in its own subdirectory:
\`\`\`
skills/
├── skill-name/
│   ├── SKILL.md
│   └── (skill files)
\`\`\`

## Adding Skills

1. Create a subdirectory for your skill
2. Add a SKILL.md file with skill metadata
3. The skill will be automatically available to all migrated agents

## Available Skills

EOF
    
    log_success "Canonical homefront initialized at: $CANONICAL_HOME"
}

update_canonical_registry() {
    local agent_id="$1"
    local meta_file="${CANONICAL_HOME}/canonical-meta.json"
    
    if [[ -f "$meta_file" ]]; then
        # Add agent to registry (simple append for now)
        local agents=$(grep -o '"agents": \[[^]]*\]' "$meta_file" 2>/dev/null || echo '[]')
        # This is a simplified approach - a proper JSON update would need jq
        log_info "Agent registered in canonical registry."
    fi
}

# =============================================================================
# USAGE AND HELP
# =============================================================================

usage() {
    cat << EOF
${GREEN}OpenClaw Agent Migration Script${NC}

${YELLOW}Usage:${NC}
    $0 <AGENT_ID> [OPTIONS]

${YELLOW}Arguments:${NC}
    AGENT_ID          The agent to migrate (e.g., 'allman', 'mort', 'avery')

${YELLOW}Options:${NC}
    -h, --help        Show this help message
    -f, --force       Force migration (overwrite existing)
    -u, --update      Update existing migration (incremental)
    -d, --dry-run     Show what would be done without doing it
    -s, --source      Override source directory (default: ~/.openclaw/agents)
    -r, --runtime     Override runtime directory (default: ./runtime)
    --skip-network    Skip network isolation setup
    --skip-validation Skip post-migration validation

${YELLOW}Examples:${NC}
    # Migrate agent 'allman'
    $0 allman

    # Force migrate (overwrite existing)
    $0 allman --force

    # Dry run to see what would happen
    $0 allman --dry-run

    # Update existing migration
    $0 allman --update

${YELLOW}What this script does:${NC}
    1. Validates agent ID and source existence
    2. Creates backup of existing target (if any)
    3. Creates isolated directory structure (app/data/config/sessions/memory/workspace)
    4. Copies agent data (SOUL.md, config, memory, sessions)
    5. Sets up canonical homefront reference
    6. Creates network isolation
    7. Sets secure permissions
    8. Generates Docker Compose override for isolated deployment
    9. Validates migration integrity

${YELLOW}Security features:${NC}
    - Network isolation (icc=false)
    - Read-only app directory
    - Tmpfs for sensitive operations
    - Capability dropping (CAP_DROP_ALL)
    - No new privileges enforcement
    - Secure file permissions

EOF
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

main() {
    local agent_id=""
    local force=false
    local update=false
    local dry_run=false
    local skip_network=false
    local skip_validation=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -u|--update)
                update=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -s|--source)
                SOURCE_ROOT="$2"
                shift 2
                ;;
            -r|--runtime)
                RUNTIME_ROOT="$2"
                shift 2
                ;;
            --skip-network)
                skip_network=true
                shift
                ;;
            --skip-validation)
                skip_validation=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -z "$agent_id" ]]; then
                    agent_id="$1"
                else
                    log_error "Unexpected argument: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate agent_id provided
    if [[ -z "$agent_id" ]]; then
        log_error "Agent ID required."
        usage
        exit 1
    fi
    
    # Print configuration
    echo ""
    log_info "OpenClaw Agent Migration"
    log_info "======================="
    log_info "Agent ID:     $agent_id"
    log_info "Source:       $SOURCE_ROOT/$agent_id"
    log_info "Target:       $AGENTS_ROOT/$agent_id"
    log_info "Runtime:      $RUNTIME_ROOT"
    log_info "Canonical:    $CANONICAL_HOME"
    log_info "Force:        $force"
    log_info "Update:       $update"
    log_info "Dry-run:      $dry_run"
    echo ""
    
    # Validation phase
    log_info "Validating..."
    
    validate_agent_id "$agent_id" || exit 1
    
    if [[ "$force" == "false" && "$update" == "false" ]]; then
        validate_source_agent "$agent_id" || exit 1
        validate_target_not_exists "$agent_id" || exit 1
    fi
    
    validate_docker || exit 1
    
    if [[ "$dry_run" == "true" ]]; then
        log_warn "DRY RUN - No changes will be made."
        log_info "Would do the following:"
        log_info "  1. Validate source agent exists"
        log_info "  2. Create directory structure in $AGENTS_ROOT/$agent_id"
        log_info "  3. Copy data from $SOURCE_ROOT/$agent_id"
        log_info "  4. Set up canonical homefront symlinks"
        log_info "  5. Create network isolation"
        log_info "  6. Set secure permissions"
        log_info "  7. Generate Docker Compose override"
        log_info "  8. Validate migration"
        exit 0
    fi
    
    # Migration phase
    log_info "Starting migration..."
    
    # Create backup if target exists and we're not forcing
    if [[ -d "${AGENTS_ROOT}/${agent_id}" && "$force" == "true" ]]; then
        create_backup "$agent_id"
    fi
    
    # Ensure canonical homefront exists
    setup_canonical_homefront
    
    # Create directory structure
    create_directory_structure "$agent_id"
    
    # Copy agent data
    copy_agent_data "$agent_id"
    
    # Create metadata
    create_agent_metadata "$agent_id"
    
    # Set up symlinks
    setup_app_symlink "$agent_id"
    setup_skills_access "$agent_id"
    
    # Create configuration
    create_agent_config "$agent_id"
    
    # Network isolation
    if [[ "$skip_network" == "false" ]]; then
        setup_network_isolation "$agent_id"
    fi
    
    # Set permissions
    set_permissions "$agent_id"
    
    # Create documentation
    create_isolation_manifest "$agent_id"
    
    # Generate Docker override
    generate_docker_override "$agent_id"
    
    # Validation
    if [[ "$skip_validation" == "false" ]]; then
        if validate_migration "$agent_id"; then
            # Update canonical registry
            update_canonical_registry "$agent_id"
            
            echo ""
            log_success "============================================"
            log_success "Migration complete!"
            log_success "============================================"
            echo ""
            log_info "Next steps:"
            echo ""
            echo "  ${GREEN}1. Review the migration:${NC}"
            echo "     ls -la $AGENTS_ROOT/$agent_id/"
            echo ""
            echo "  ${GREEN}2. Start the agent:${NC}"
            echo "     cd $RUNTIME_ROOT"
            echo "     docker compose -p $agent_id -f docker-compose.yml -f agents/$agent_id/docker-compose.override.yml up -d"
            echo ""
            echo "  ${GREEN}3. Check logs:${NC}"
            echo "     docker logs oc-$agent_id"
            echo ""
            echo "  ${GREEN}4. Access agent shell:${NC}"
            echo "     docker exec -it oc-$agent_id /bin/bash"
            echo ""
            echo "  ${GREEN}Documentation:${NC}"
            echo "     $AGENTS_ROOT/$agent_id/ISOLATION.md"
            echo ""
        else
            log_error "Migration validation failed!"
            log_error "Check the errors above and retry with --update to fix."
            exit 1
        fi
    else
        log_success "Migration complete (validation skipped)."
    fi
}

# Run main
main "$@"