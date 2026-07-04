#!/bin/bash
# =============================================================================
# Tool Injection: Memory Context Injection
# Injects agent memory files into tools context for OpenClaw/Hermes
# Includes: SOUL.md, USER.md, IDENTITY.md, MEMORY.md, AGENTS.md, daily memory, active tasks
# =============================================================================

set -euo pipefail
shopt -s nullglob

# Find RUNTIME_ROOT by searching for runtime.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers.sh"

AGENTS_DIR="${AGENTS_DIR:-/data/agents}"
PLUGINS_DIR="${PLUGINS_DIR:-/plugins}"
TOOL_ENFORCEMENT_DIR="$PLUGINS_DIR/tool-enforcement"

# =============================================================================
# SECURITY & SIZE LIMITS
# =============================================================================

# Maximum size for individual memory files (in bytes) - default 10MB
MAX_MEMORY_FILE_SIZE="${MAX_MEMORY_FILE_SIZE:-10485760}"

# Maximum total size for injected context (in bytes) - default 50MB
MAX_CONTEXT_SIZE="${MAX_CONTEXT_SIZE:-52428800}"

# Track cleanup hooks
CLEANUP_HOOKS=()

# Register cleanup hook
register_cleanup() {
    local hook="$1"
    CLEANUP_HOOKS+=("$hook")
}

# Run cleanup hooks
run_cleanup() {
    local exit_code=$?
    
    # Run cleanup hooks in reverse order
    for ((i=${#CLEANUP_HOOKS[@]}-1; i>=0; i--)); do
        debug "Running cleanup hook: ${CLEANUP_HOOKS[$i]}"
        eval "${CLEANUP_HOOKS[$i]}" 2>/dev/null || warn "Cleanup hook failed: ${CLEANUP_HOOKS[$i]}"
    done
    
    exit $exit_code
}

# Register cleanup for temp files
trap run_cleanup EXIT

# =============================================================================
# SIZE VALIDATION FUNCTIONS
# =============================================================================

# Check if a file exceeds size limits
check_file_size() {
    local file_path="$1"
    local max_size="${2:-$MAX_MEMORY_FILE_SIZE}"
    
    if [[ ! -f "$file_path" ]]; then
        warn "File does not exist: $file_path"
        return 1
    fi
    
    local file_size
    file_size=$(stat -c %s "$file_path" 2>/dev/null || stat -f %z "$file_path" 2>/dev/null || echo "0")
    
    if [[ $file_size -gt $max_size ]]; then
        error "File exceeds maximum size limit: $file_path (${file_size} bytes > ${max_size} bytes)"
        error "Consider increasing MAX_MEMORY_FILE_SIZE or splitting the file"
        return 1
    fi
    
    return 0
}

# Get file size in human-readable format
get_human_readable_size() {
    local bytes="$1"
    
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} bytes"
    fi
}

# Check total context size
check_total_size() {
    local context_file="$1"
    
    if [[ -f "$context_file" ]]; then
        local current_size
        current_size=$(stat -c %s "$context_file" 2>/dev/null || stat -f %z "$context_file" 2>/dev/null || echo "0")
        
        if [[ $current_size -gt $MAX_CONTEXT_SIZE ]]; then
            warn "Context file approaching size limit: $(get_human_readable_size $current_size) / $(get_human_readable_size $MAX_CONTEXT_SIZE)"
            return 1
        fi
    fi
    
    return 0
}

# Sanitize agent ID to prevent path traversal
sanitize_agent_id() {
    local agent_id="$1"
    
    # Remove any path traversal attempts
    agent_id=$(echo "$agent_id" | sed 's|/||g; s|\.\.||g')
    
    # Only allow alphanumeric, hyphens, underscores, and dots
    if [[ ! "$agent_id" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error "Invalid agent ID: $agent_id (contains invalid characters)"
        return 1
    fi
    
    # Validate length
    if [[ ${#agent_id} -gt 256 ]]; then
        error "Agent ID too long: $agent_id (max 256 characters)"
        return 1
    fi
    
    echo "$agent_id"
    return 0
}

success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
${GREEN}Memory Context Injection Tool${NC}

Injects agent memory files as context for OpenClaw/Hermes tools.
Includes: SOUL.md, USER.md, IDENTITY.md, MEMORY.md, AGENTS.md, daily memory, and active tasks.

Usage: $0 <agent_id> [options]

Arguments:
  agent_id       ID of the agent to inject memory for

Options:
  --all         Inject memory for all agents
  --list        List available agents with memory files
  --date YYYY-MM-DD  Specific date for daily memory (default: today and yesterday)
  --daily-only   Inject only daily memory files
  --force       Overwrite existing injections
  --quiet       Suppress output
  --verify      Verify injected files exist
  --help, -h    Show this help

Examples:
  $0 test-e2e-agent
  $0 --all
  $0 test-e2e-agent --date 2024-04-24
  $0 test-e2e-agent --daily-only
  $0 --all --force
  $0 test-e2e-agent --quiet
EOF
    exit 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
AGENT_ID=""
ALL_AGENTS=false
LIST_AGENTS=false
SPECIFIC_DATE=""
FORCE=false
QUIET=false
DAILY_ONLY=false
VERIFY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            ALL_AGENTS=true
            shift
            ;;
        --list)
            LIST_AGENTS=true
            shift
            ;;
        --date)
            SPECIFIC_DATE="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --daily-only)
            DAILY_ONLY=true
            shift
            ;;
        --verify)
            VERIFY=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            if [[ -z "$AGENT_ID" ]]; then
                AGENT_ID="$1"
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# =============================================================================
# FILE LISTING AND DISCOVERY
# =============================================================================

# Get today's and yesterday's dates
get_dates() {
    local today
    today=$(date +%Y-%m-%d)
    local yesterday
    yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo "")
    
    if [[ -n "$SPECIFIC_DATE" ]]; then
        echo "$SPECIFIC_DATE"
    else
        echo "$today"
        if [[ -n "$yesterday" ]]; then
            echo "$yesterday"
        fi
    fi
}

# Find all agents with memory files
find_agents_with_memory() {
    local agents=()
    
    # Apply self-healing
    with_self_healing "find_agents_with_memory" 2>/dev/null || true
    
    if [[ ! -d "$AGENTS_DIR" ]]; then
        # Attempt to create directory if missing
        mkdir -p "$AGENTS_DIR" 2>/dev/null
    fi
    
    for agent_dir in "$AGENTS_DIR"/*/; do
        if [[ -d "$agent_dir" ]]; then
            local agent_id=$(basename "$agent_dir")
            local data_dir="$agent_dir/data"
            
            # Sanitize agent ID for safety
            if ! agent_id=$(sanitize_agent_id "$agent_id" 2>/dev/null); then
                warn "Skipping agent with invalid ID: $agent_id"
                continue
            fi
            
            # Check if agent has any memory files
            if [[ -f "$data_dir/SOUL.md" ]] || \
               [[ -f "$data_dir/USER.md" ]] || \
               [[ -f "$data_dir/IDENTITY.md" ]] || \
               [[ -f "$data_dir/MEMORY.md" ]] || \
               [[ -f "$data_dir/AGENTS.md" ]]; then
                agents+=("$agent_id")
            fi
        fi
    done
    
    echo "${agents[@]}"
}

# =============================================================================
# MEMORY INJECTION
# =============================================================================

# Inject memory context for a single agent
inject_memory() {
    local agent_id=$1
    local target_date=$2
    
    # Security: Sanitize agent ID to prevent path traversal
    if ! agent_id=$(sanitize_agent_id "$agent_id" 2>/dev/null); then
        warn "Invalid agent ID: $agent_id"
        return 1
    fi
    
    local agent_dir="$AGENTS_DIR/$agent_id"
    local data_dir="$agent_dir/data"
    local memory_dir="$agent_dir/data/memory"
    local tools_dir="$agent_dir/tools"
    local config_dir="$agent_dir/config"
    
    # Check agent exists
    if [[ ! -d "$agent_dir" ]]; then
        [[ "$QUIET" != true ]] && warn "Agent $agent_id not found at $agent_dir"
        return 1
    fi
    
    # Run tool enforcement check
    local enforce_script="$tools_dir/enforce.sh"
    if [[ -f "$enforce_script" ]]; then
        [[ "$QUIET" != true ]] && log "  Running tool enforcement check..."
        bash "$enforce_script" "$agent_dir" 2>/dev/null || [[ "$QUIET" != true ]] && log "  Tool enforcement check completed (some fixes may apply)"
    fi
    
    # Check memory directory exists and validate sizes
    if [[ -d "$data_dir" ]]; then
        # Check individual memory files for size limits
        for mem_file in "SOUL.md" "USER.md" "IDENTITY.md" "MEMORY.md" "AGENTS.md"; do
            local file_path="$data_dir/$mem_file"
            if [[ -f "$file_path" ]]; then
                if ! check_file_size "$file_path"; then
                    warn "Skipping injection for $agent_id due to oversized file: $mem_file"
                    return 1
                fi
            fi
        done
        
        # Check daily memory files
        local today=$(date +%Y-%m-%d)
        local yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo "")
        
        for d in "$today" "$yesterday"; do
            local file_path="$data_dir/memory/${d}.md"
            if [[ -f "$file_path" ]]; then
                if ! check_file_size "$file_path"; then
                    warn "Skipping injection for $agent_id due to oversized daily memory: ${d}.md"
                    return 1
                fi
            fi
        done
    fi
    
    # Create tools directory if it doesn't exist
    mkdir -p "$tools_dir" 2>/dev/null
    
    # Determine which memory files to inject
    local core_files=("SOUL.md" "USER.md" "IDENTITY.md" "MEMORY.md" "AGENTS.md")
    local daily_files=()
    local today=$(date +%Y-%m-%d)
    local yesterday=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d 2>/dev/null || echo "")
    
    # Get dates
    local dates=()
    if [[ -n "$target_date" ]]; then
        dates+=("$target_date")
    else
        dates+=("$today")
        if [[ -n "$yesterday" ]]; then
            dates+=("$yesterday")
        fi
    fi
    
    # Build daily files list
    for d in "${dates[@]}"; do
        daily_files+=("memory/${d}.md")
    done
    
    # Create memory injection context file
    local context_file="$tools_dir/memory-context.md"
    
    # Only create if force or file doesn't exist
    if [[ "$FORCE" != true ]] && [[ -f "$context_file" ]]; then
        [[ "$QUIET" != true ]] && log "  SKIP: memory-context.md already exists for $agent_id (use --force)"
        return 0
    fi
    
    if [[ "$DAILY_ONLY" == true ]]; then
        # Only inject daily memory files
        context_file="$tools_dir/daily-memory-context.md"
    fi
    
    [[ "$QUIET" != true ]] && log "Injecting memory context for agent: $agent_id"
    
    # Create context header
    local workflow_info=""
    if [[ -f "$data_dir/WORKFLOW.md" ]]; then
        workflow_info=" (Workflow: $(head -1 "$data_dir/WORKFLOW.md"))"
    fi
    
    cat > "$context_file" <<EOF
# Memory Context Injection
**Agent:** $agent_id
**Injected:** $(date)
**Source:** $AGENTS_DIR/$agent_id/
**Purpose:** Provide persistent memory context for tool operations
$workflow_info

---

## Core Identity Files
*These define the agent's purpose, user context, and long-term knowledge*
EOF
    
    # Inject core identity files
    local injected_count=0
    local total_files=0
    local daily_count=0
    
    if [[ "$DAILY_ONLY" != true ]]; then
        for mem_file in "${core_files[@]}"; do
            local file_path="$data_dir/$mem_file"
            local base_name=$(basename "$mem_file")
            
            total_files=$((total_files + 1))
            
            if [[ -f "$file_path" ]]; then
                echo "" >> "$context_file"
                echo "### ${base_name^^}" >> "$context_file"
                echo "*Last modified: $(stat -c %y "$file_path" 2>/dev/null || date)*" >> "$context_file"
                echo "" >> "$context_file"
                cat "$file_path" >> "$context_file"
                echo "" >> "$context_file"
                echo "---" >> "$context_file"
                ((injected_count++))
                [[ "$QUIET" != true ]] && log "  Injected: $mem_file"
            else
                # Missing core file - create placeholder or warning
                echo "" >> "$context_file"
                echo "### ${base_name^^}" >> "$context_file"
                echo "*WARNING: File not found - agent may need initialization*" >> "$context_file"
                echo "" >> "$context_file"
                echo "---" >> "$context_file"
                [[ "$QUIET" != true ]] && warn "  MISSING: $mem_file"
            fi
        done
        
        # Inject AGENTS.md (operating standard) + TOOLS.md (tool registry;
        # TOOLS-GUIDE.md was consolidated into TOOLS.md). Both live at the
        # workspace root, not in tools/.
        for doc in AGENTS.md TOOLS.md; do
            local doc_path="$agent_dir/$doc"
            if [[ -f "$doc_path" ]]; then
                echo "" >> "$context_file"
                echo "### $doc" >> "$context_file"
                echo "*Last modified: $(stat -c %y "$doc_path" 2>/dev/null || date)*" >> "$context_file"
                echo "" >> "$context_file"
                cat "$doc_path" >> "$context_file"
                echo "" >> "$context_file"
                echo "---" >> "$context_file"
                ((injected_count++))
                ((total_files++))
                [[ "$QUIET" != true ]] && log "  Injected: $doc"
            else
                [[ "$QUIET" != true ]] && log "  SKIP: $doc (not found)"
            fi
        done
    fi
    
    # Inject daily memory files
    echo "" >> "$context_file"
    echo "## Daily Memory Files" >> "$context_file"
    echo "*Ephemeral knowledge from recent sessions*" >> "$context_file"
    echo "" >> "$context_file"
    
    if [[ "$DAILY_ONLY" == true ]] || [[ "$FULL_BACKUP" == true ]]; then
        # Inject from sessions directory too
        local sessions_dir="$agent_dir/sessions"
        if [[ -d "$sessions_dir" ]]; then
            for session_file in "$sessions_dir"/*.md "$sessions_dir"/*.txt "$sessions_dir"/*.json; do
                if [[ -f "$session_file" ]]; then
                    local sname=$(basename "$session_file")
                    echo "" >> "$context_file"
                    echo "### Session: ${sname}" >> "$context_file"
                    echo "*Last modified: $(stat -c %y "$session_file" 2>/dev/null || date)*" >> "$context_file"
                    echo "" >> "$context_file"
                    cat "$session_file" >> "$context_file"
                    echo "" >> "$context_file"
                    echo "---" >> "$context_file"
                    ((injected_count++))
                    ((total_files++))
                    [[ "$QUIET" != true ]] && log "  Injected: sessions/$sname"
                fi
            done
        fi
    fi
    
    for mem_file in "${daily_files[@]}"; do
        local file_path="$data_dir/$mem_file"
        local base_name=$(basename "$mem_file")
        
        if [[ -f "$file_path" ]]; then
            echo "" >> "$context_file"
            echo "### ${base_name} " >> "$context_file"
            echo "*Last modified: $(stat -c %y "$file_path" 2>/dev/null || date)*" >> "$context_file"
            echo "" >> "$context_file"
            cat "$file_path" >> "$context_file"
            echo "" >> "$context_file"
            echo "---" >> "$context_file"
            ((injected_count++))
            ((daily_count++))
            [[ "$QUIET" != true ]] && log "  Injected: $mem_file"
        elif [[ "$mem_file" == "memory/"* ]]; then
            # Daily memory file doesn't exist - skip
            [[ "$QUIET" != true ]] && log "  SKIP: $mem_file (not found)"
        fi
    done
    
    # Inject active tasks from HEARTBEAT.md
    local heartbeat_file="$data_dir/HEARTBEAT.md"
    if [[ -f "$heartbeat_file" ]]; then
        echo "" >> "$context_file"
        echo "## Active Tasks" >> "$context_file"
        echo "*Current and pending tasks for the agent*" >> "$context_file"
        echo "" >> "$context_file"
        cat "$heartbeat_file" >> "$context_file"
        [[ "$QUIET" != true ]] && log "  Injected: HEARTBEAT.md (active tasks)"
        ((injected_count++))
        ((total_files++))
    fi
    
    # Inject active projects
    local projects_dir="$agent_dir/projects"
    if [[ -d "$projects_dir" ]]; then
        echo "" >> "$context_file"
        echo "## Active Projects" >> "$context_file"
        echo "*Ongoing work and deliverables*" >> "$context_file"
        echo "" >> "$context_file"
        
        local project_count=0
        for project_file in "$projects_dir"/*.md "$projects_dir"/*.txt "$projects_dir"/*.json; do
            if [[ -f "$project_file" ]]; then
                local pname=$(basename "$project_file")
                echo "### Project: ${pname}" >> "$context_file"
                echo "" >> "$context_file"
                cat "$project_file" >> "$context_file"
                echo "" >> "$context_file"
                echo "---" >> "$context_file"
                ((injected_count++))
                ((project_count++))
                [[ "$QUIET" != true ]] && log "  Injected: projects/$pname"
            fi
        done
        
        if [[ $project_count -gt 0 ]]; then
            ((total_files+=$project_count))
        fi
    fi
    
    # Inject workflow information if available
    local agent_json="$agent_dir/agent.json"
    if [[ -f "$agent_json" ]]; then
        echo "" >> "$context_file"
        echo "## Workflow Configuration" >> "$context_file"
        echo "*Agent workflow and integration points*" >> "$context_file"
        echo "" >> "$context_file"
        echo "```json" >> "$context_file"
        # Extract workflow-related fields
        python3 -c "
import json, sys
try:
    with open('$agent_json', 'r') as f:
        data = json.load(f)
    workflow_info = {
        'workflow_file': data.get('workflow_file', 'N/A'),
        'crew_workflows': data.get('crew_workflows', []),
        'cooperative_level': data.get('cooperative_level', 'N/A'),
        'integration_points': data.get('integration_points', []),
        'specialized_capabilities': data.get('specialized_capabilities', [])
    }
    print(json.dumps(workflow_info, indent=2))
except:
    print('Workflow info not available')
" 2>/dev/null >> "$context_file" || echo "File: $agent_json" >> "$context_file"
        echo "```" >> "$context_file"
        ((injected_count++))
        [[ "$QUIET" != true ]] && log "  Injected: Workflow configuration"
    fi
    
    # Inject environment variables (sanitized - no secrets)
    local env_file="$agent_dir/agent.env"
    local env_file2="$data_dir/.env"
    
    if [[ -f "$env_file" ]]; then
        inject_env_file "$env_file" "$context_file" "$injected_count"
    elif [[ -f "$env_file2" ]]; then
        inject_env_file "$env_file2" "$context_file" "$injected_count"
    fi
    
    # Inject core skills context
    local skills_dir="$agent_dir/skills"
    if [[ -d "$skills_dir" ]]; then
        echo "" >> "$context_file"
        echo "## Available Skills" >> "$context_file"
        echo "*Loaded skill descriptions for context*" >> "$context_file"
        echo "" >> "$context_file"
        
        local skill_count=0
        for skill_dir in "$skills_dir"/*/; do
            [[ -d "$skill_dir" ]] || continue
            local skill_name=$(basename "$skill_dir")
            local skill_md="$skill_dir/SKILL.md"
            if [[ -f "$skill_md" ]]; then
                local description=$(sed -n '/^---$/,/^---$/p' "$skill_md" 2>/dev/null | grep -A1 '^description:' | tail -1 | sed 's/^  *//')
                echo "- **$skill_name**: $description" >> "$context_file"
                ((skill_count++))
            fi
        done
        
        if [[ $skill_count -eq 0 ]]; then
            echo "_No skills with SKILL.md found._" >> "$context_file"
        fi
        echo "" >> "$context_file"
        echo "---" >> "$context_file"
        ((injected_count++))
        ((total_files++))
        [[ "$QUIET" != true ]] && log "  Injected: Skills context ($skill_count skills)"
    fi
    
    # Add footer
    echo "" >> "$context_file"
    echo "---" >> "$context_file"
    echo "*Memory Context Injection Summary*" >> "$context_file"
    echo "*Generated: $(date)*" >> "$context_file"
    echo "*Core files: $injected_count / $total_files injected*" >> "$context_file"
    if [[ "$DAILY_ONLY" == true ]]; then
        echo "*Mode: Daily memory only*" >> "$context_file"
    fi
    
    # Set permissions
    chmod 644 "$context_file"
    
    [[ "$QUIET" != true ]] && success "Memory context injected for $agent_id ($injected_count files)"
    return 0
}

# Inject environment file (sanitized)
inject_env_file() {
    local env_file="$1"
    local context_file="$2"
    local injected_count="$3"
    
    echo "" >> "$context_file"
    echo "## Environment Configuration" >> "$context_file"
    echo "*Non-sensitive configuration settings*" >> "$context_file"
    echo "" >> "$context_file"
    echo "```" >> "$context_file"
    
    # Extract non-sensitive env vars
    grep -E "^(AGENT_ID|AGENT_NAME|AGENT_CATEGORY|PRIMARY_MODEL|BACKUP_MODEL|MODEL|WORKFLOW_FILE|CREW_CHANNEL)" "$env_file" 2>/dev/null || true
    
    echo "```" >> "$context_file"
    echo "" >> "$context_file"
    echo "---" >> "$context_file"
}

# =============================================================================
# BATCH OPERATIONS
# =============================================================================

# Inject memory for all agents
inject_all_memory() {
    local count=0
    local total=0
    local success_count=0
    
    # Apply self-healing
    with_self_healing "inject_all_memory" 2>/dev/null || true
    
    if [[ ! -d "$AGENTS_DIR" ]]; then
        # Attempt to create agents directory
        mkdir -p "$AGENTS_DIR" 2>/dev/null
    fi
    
    for agent_dir in "$AGENTS_DIR"/*/; do
        if [[ -d "$agent_dir" ]]; then
            local agent_id=$(basename "$agent_dir")
            total=$((total + 1))
            
            # Apply self-healing for individual agent injection
            if with_self_healing "inject_memory $agent_id" inject_memory "$agent_id" "$SPECIFIC_DATE" 2>/dev/null; then
                success_count=$((success_count + 1))
            else
                warn "Failed to inject memory for $agent_id, attempting retry..."
                if retry_with_fallback "inject_memory $agent_id $SPECIFIC_DATE" "echo 'Fallback injection failed'" 2 1 2>/dev/null; then
                    success_count=$((success_count + 1))
                else
                    warn "Permanent failure for $agent_id"
                fi
            fi
        fi
    done
    
    success "Injected memory for $success_count/$total agents"
    
    if [[ $success_count -lt $total ]]; then
        warn "Some agents may not have memory files"
    fi
}

# List agents with memory files
list_agents_memory() {
    log "Agents with Memory Files"
    log "========================"
    echo ""
    
    local total_agents=0
    local agent_count=0
    
    if [[ ! -d "$AGENTS_DIR" ]]; then
        log "No agents directory found"
        return 0
    fi
    
    for agent_dir in "$AGENTS_DIR"/*/; do
        if [[ -d "$agent_dir" ]]; then
            total_agents=$((total_agents + 1))
            local agent_id=$(basename "$agent_dir")
            local data_dir="$agent_dir/data"
            local memory_dir="$data_dir/memory"
            
            local has_core=false
            local has_daily=false
            local core_files=()
            
            # Check for core files
            for core in SOUL.md USER.md IDENTITY.md MEMORY.md AGENTS.md; do
                if [[ -f "$data_dir/$core" ]]; then
                    has_core=true
                    core_files+=("$core")
                fi
            done
            
            # Check for daily memory
            if [[ -d "$memory_dir" ]]; then
                local daily_files=$(find "$memory_dir" -name "*.md" -type f 2>/dev/null | wc -l)
                if [[ $daily_files -gt 0 ]]; then
                    has_daily=true
                fi
            fi
            
            # Check for heartbeat (active tasks)
            local has_tasks=false
            if [[ -f "$data_dir/HEARTBEAT.md" ]]; then
                has_tasks=true
            fi
            
            # Check for projects
            local has_projects=false
            if [[ -d "$agent_dir/projects" ]]; then
                local proj_files=$(find "$agent_dir/projects" -name "*.md" -o -name "*.txt" | wc -l)
                if [[ $proj_files -gt 0 ]]; then
                    has_projects=true
                fi
            fi
            
            # Only include agents with at least one memory file
            if [[ "$has_core" == true ]] || [[ "$has_daily" == true ]] || [[ "$has_tasks" == true ]]; then
                local status_icons=""
                
                # Build status icons
                local sep=""
                [[ "$has_core" == true ]] && status_icons="${status_icons}${sep}ID" && sep=" "
                [[ "$has_daily" == true ]] && status_icons="${status_icons}${sep}DM" && sep=" "
                [[ "$has_tasks" == true ]] && status_icons="${status_icons}${sep}AT" && sep=" "
                [[ "$has_projects" == true ]] && status_icons="${status_icons}${sep}PR" && sep=" "
                
                printf "  %-30s | %s | %s\n" "$agent_id" "${status_icons:-none}" "${core_files[*]:-}"
                agent_count=$((agent_count + 1))
            fi
        fi
    done
    
    echo ""
    if [[ $agent_count -gt 0 ]]; then
        success "Found $agent_count agents with memory files (out of $total_agents total)"
    else
        log "No agents have memory files yet"
    fi
}

# Verify injected files
verify_injected() {
    local agent_id="$1"
    local agent_dir="$AGENTS_DIR/$agent_id"
    local tools_dir="$agent_dir/tools"
    
    if [[ ! -d "$agent_dir" ]]; then
        error "Agent not found: $agent_id"
    fi
    
    log "Verifying memory injection for: $agent_id"
    echo ""
    
    local context_file="$tools_dir/memory-context.md"
    local daily_file="$tools_dir/daily-memory-context.md"
    
    if [[ -f "$context_file" ]]; then
        log "  memory-context.md: EXISTS"
        local size=$(wc -l < "$context_file")
        log "    Lines: $size"
        local mtime=$(stat -c %y "$context_file" 2>/dev/null || date)
        log "    Last modified: $mtime"
    else
        warn "  memory-context.md: NOT FOUND"
    fi
    
    if [[ -f "$daily_file" ]]; then
        log "  daily-memory-context.md: EXISTS"
        local size=$(wc -l < "$daily_file")
        log "    Lines: $size"
    else
        log "  daily-memory-context.md: NOT FOUND"
    fi
    
    # Check for required sections
    if [[ -f "$context_file" ]]; then
        echo ""
        log "Checking content sections:"
        
        local sections=("Core Identity Files" "Daily Memory Files" "Active Tasks" "Active Projects" "Workflow Configuration")
        
        for section in "${sections[@]}"; do
            if grep -q "^## $section" "$context_file" 2>/dev/null; then
                log "  ✓ $section"
            else
                warn "  ✗ $section (not found)"
            fi
        done
    fi
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

# Verify mode
if [[ "$VERIFY" == true ]]; then
    if [[ -n "$AGENT_ID" ]]; then
        verify_injected "$AGENT_ID"
    else
        error "Please specify an agent ID to verify"
    fi
    exit 0
fi

# List mode
if [[ "$LIST_AGENTS" == true ]]; then
    list_agents_memory
    exit 0
fi

# All agents mode
if [[ "$ALL_AGENTS" == true ]]; then
    inject_all_memory
    exit 0
fi

# Single agent mode
if [[ -n "$AGENT_ID" ]]; then
    inject_memory "$AGENT_ID" "$SPECIFIC_DATE"
else
    error "No agent ID specified. Use --list to see available agents or specify an agent ID."
fi
