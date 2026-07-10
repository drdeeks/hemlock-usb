#!/bin/bash
# Hemlock Runtime Management System
# Unified CLI for agent lifecycle management
#
# Runs inside container. Host paths are not accessible — the menu
# shows the correct `hemlock import/export` command to run on the host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.runtime.yml"
CONTAINER_NAME="${HEMLOCK_CONTAINER:-hemlock_runtime}"

# ── Detect environment ────────────────────────────────────────────────────────
# If HEMLOCK_DOCKER=1, we're inside the container already
# If docker compose is up, container is running
# Otherwise, we need to start it

is_inside_container() {
    [[ "${HEMLOCK_DOCKER:-}" == "1" ]] && return 0
    [[ -f /.dockerenv ]] && return 0
    grep -q '/docker/' /proc/1/cgroup 2>/dev/null && return 0
    return 1
}

is_container_running() {
    docker ps -q -f name="$CONTAINER_NAME" 2>/dev/null | grep -q .
}

start_container() {
    echo -e "${BLUE}━━━ Hemlock Runtime ━━━${NC}"
    echo ""
    echo "  Container '$CONTAINER_NAME' is not running."
    echo ""
    read -rp "  Start it now? [Y/n]: " answer
    answer="${answer:-Y}"
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "  Starting Hemlock runtime..."
        docker compose -f "$COMPOSE_FILE" up -d 2>&1
        echo ""
        echo "  Waiting for container to be healthy..."
        local attempts=0
        while ! is_container_running && [[ $attempts -lt 30 ]]; do
            sleep 2
            attempts=$((attempts + 1))
            echo "  ...waiting ($attempts/30)"
        done
        if is_container_running; then
            echo -e "  ${GREEN}Container started successfully.${NC}"
        else
            echo -e "  ${RED}Container failed to start. Check logs with:${NC}"
            echo "    docker compose -f $COMPOSE_FILE logs"
            return 1
        fi
    else
        echo "  Cancelled."
        return 1
    fi
}

# ── Host-side entrypoint ──────────────────────────────────────────────────────
# If we're on the host (not inside Docker):
#   - Bare invocation or "menu" → start container, exec interactive menu inside it
#   - import/export/etc → delegate to hemlock-stage.sh for staging + container exec
#   - The user should never see staging details — just the nice menu

if ! is_inside_container; then
    # Ensure container is running for any command that needs it
    _ensure_running() {
        if ! is_container_running; then
            start_container || exit 1
        fi
    }

    case "${1:-}" in
        import|export|crew-import|crew-export|list-imports|li|list-exports|le|clean-imports|clean-exports|stage|pull)
            # Plumbing commands — delegate to hemlock-stage.sh
            shift || true
            exec "$SCRIPT_DIR/hemlock-stage.sh" "$@"
            ;;
        shell|sh)
            _ensure_running
            exec docker exec -it "$CONTAINER_NAME" bash
            ;;
        up)
            docker compose -f "$COMPOSE_FILE" up -d
            echo "  Runtime started."
            ;;
        down)
            docker compose -f "$COMPOSE_FILE" down
            echo "  Runtime stopped."
            ;;
        status|st)
            if is_container_running; then
                echo "  Container '$CONTAINER_NAME' is running."
                docker ps -f name="$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            else
                echo "  Container '$CONTAINER_NAME' is not running."
            fi
            ;;
        help|--help|-h)
            echo ""
            echo -e "${BOLD}Hemlock Runtime Management${NC}"
            echo ""
            echo "  hemlock                           Open interactive menu (default)"
            echo "  hemlock import <file> [agent_id]  Import agent from host"
            echo "  hemlock export <agent_id> [dest]   Export agent to host"
            echo "  hemlock crew-import <file> [name] Import crew from host"
            echo "  hemlock crew-export <name> [dest] Export crew to host"
            echo "  hemlock up                        Start runtime"
            echo "  hemlock down                      Stop runtime"
            echo "  hemlock status                    Show status"
            echo "  hemlock shell                     Shell into container"
            echo ""
            exit 0
            ;;
        *)
            # Default: start container and open the interactive menu
            _ensure_running
            exec docker exec -it "$CONTAINER_NAME" /opt/hermes/scripts/runtime.sh
            ;;
    esac
fi

# ── Past this point, we are INSIDE the container ──────────────────────────────

source "$SCRIPT_DIR/helpers.sh"

mkdir -p "$AGENTS_DIR" "$CONFIG_DIR" "$LOGS_DIR" "$CREWS_DIR"

# ── UI Helpers ────────────────────────────────────────────────────────────────

BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

HEADER="============================================="
DIVIDER="---------------------------------------------"

clear_screen() { clear; }

print_header() {
    echo -e "${BLUE}${HEADER}${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}${HEADER}${NC}"
    echo ""
}

print_divider() {
    echo "$DIVIDER"
}

get_stats() {
    local agent_count=0
    for d in "$AGENTS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local name
        name="$(basename "$d")"
        [[ "$name" == "workspace-template" || "$name" == "active" || "$name" == "archive" ]] && continue
        agent_count=$((agent_count + 1))
    done

    local crew_count=0
    if [[ -d "$CREWS_DIR" ]]; then
        for d in "$CREWS_DIR"/*/; do
            [[ -d "$d" ]] || continue
            crew_count=$((crew_count + 1))
        done
    fi

    local docker_status="not available"
    if docker info &>/dev/null; then
        docker_status="available"
    fi

    local ollama_status="not running"
    if curl -s http://localhost:11434/api/tags &>/dev/null; then
        ollama_status="running"
    fi

    echo "$agent_count $crew_count $docker_status $ollama_status"
}

print_main_banner() {
    local stats
    stats=$(get_stats)
    local agent_count crew_count docker_status ollama_status
    agent_count=$(echo "$stats" | awk '{print $1}')
    crew_count=$(echo "$stats" | awk '{print $2}')
    docker_status=$(echo "$stats" | awk '{print $3}')
    ollama_status=$(echo "$stats" | awk '{print $4}')

    local docker_color="${GREEN}"
    local ollama_color="${RED}"
    [[ "$docker_status" == "available" ]] && docker_color="${GREEN}"
    [[ "$ollama_status" == "running" ]] && ollama_color="${GREEN}"

    echo ""
    echo -e "${BLUE}   ╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}   ║${NC}        ${BOLD}${BLUE}HEMLOCK ENTERPRISE AGENT FRAMEWORK${NC}                   ${BLUE}║${NC}"
    echo -e "${BLUE}   ║${NC}             ${CYAN}Interactive Management Console${NC}                  ${BLUE}║${NC}"
    echo -e "${BLUE}   ╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "   ${BOLD}Agents:${NC} $agent_count  ${BOLD}Crews:${NC} $crew_count  ${BOLD}Docker:${NC} ${docker_color}${docker_status}${NC}  ${BOLD}Ollama:${NC} ${ollama_color}${ollama_status}${NC}"
    echo ""
}

press_any_key() {
    echo ""
    echo "$DIVIDER"
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
    echo ""
}

prompt_input() {
    local label="$1"
    local default="${2:-}"
    local required="${3:-false}"
    local result=""

    while true; do
        if [[ -n "$default" ]]; then
            echo -n "$label [$default]: "
        else
            echo -n "$label: "
        fi
        read -r result

        if [[ -z "$result" && -n "$default" ]]; then
            echo "$default"
            return
        fi

        if [[ -z "$result" && "$required" == "true" ]]; then
            echo "  → This field is required. Please enter a value."
            continue
        fi

        echo "$result"
        return
    done
}

confirm_action() {
    local message="$1"
    local default="${2:-N}"
    local response

    echo -n "$message [y/N]: "
    read -r response
    response="${response:-$default}"

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

list_available_agents() {
    echo ""
    echo "Available agents:"
    local agents=()
    for d in "$AGENTS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local name
        name="$(basename "$d")"
        [[ "$name" == "workspace-template" || "$name" == "active" || "$name" == "archive" ]] && continue
        agents+=("$name")
    done

    if [[ ${#agents[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        for a in "${agents[@]}"; do
            echo "  • $a"
        done
    fi
    echo "$DIVIDER"
}

list_available_crews() {
    echo ""
    echo "Available crews:"
    local crews=()
    if [[ -d "$CREWS_DIR" ]]; then
        for d in "$CREWS_DIR"/*/; do
            [[ -d "$d" ]] || continue
            crews+=("$(basename "$d")")
        done
    fi

    if [[ ${#crews[@]} -eq 0 ]]; then
        echo "  (none)"
    else
        for c in "${crews[@]}"; do
            echo "  • $c"
        done
    fi
    echo "$DIVIDER"
}

# ── Main Menu ─────────────────────────────────────────────────────────────────

main_menu() {
    while true; do
        clear_screen
        print_main_banner
        echo -e "   ${BOLD}1.${NC} Agent Management"
        echo -e "   ${BOLD}2.${NC} Crew Management (A2A)"
        echo -e "   ${BOLD}3.${NC} Runtime Validation"
        echo -e "   ${BOLD}4.${NC} Security Hardening"
        echo -e "   ${BOLD}5.${NC} System Monitoring"
        echo -e "   ${BOLD}6.${NC} Configuration"
        echo -e "   ${BOLD}7.${NC} Knowledge Base (links & docs)"
        echo -e "   ${BOLD}8.${NC} Backup & Restore"
        echo -e "   ${BOLD}9.${NC} Exit"
        echo ""
        echo "$DIVIDER"

        read -rp "   Select option [1-9]: " choice
        case "$choice" in
            1) agent_menu ;;
            2) crew_menu ;;
            3) validation_menu ;;
            4) security_menu ;;
            5) monitoring_menu ;;
            6) config_menu ;;
            7) knowledge_menu ;;
            8) backup_menu ;;
            9) echo "Exiting..."; exit 0 ;;
            *) echo -e "   ${RED}→ Invalid option. Please enter a number between 1 and 9.${NC}"; sleep 1 ;;
        esac
    done
}

# ── Agent Management ──────────────────────────────────────────────────────────

agent_menu() {
    while true; do
        clear_screen
        print_header "Agent Management"
        echo -e "  ${BOLD}1.${NC} Create New Agent"
        echo -e "  ${BOLD}2.${NC} Import Existing Agent"
        echo -e "  ${BOLD}3.${NC} Export Agent"
        echo -e "  ${BOLD}4.${NC} Delete Agent"
        echo -e "  ${BOLD}5.${NC} Start Agent"
        echo -e "  ${BOLD}6.${NC} Stop Agent"
        echo -e "  ${BOLD}7.${NC} Monitor Agent"
        echo -e "  ${BOLD}8.${NC} List Agents"
        echo -e "  ${BOLD}9.${NC} Back to Main Menu"
        echo "$DIVIDER"

        read -rp "  Select option [1-9]: " choice
        case "$choice" in
            1) create_agent ;;
            2) import_agent ;;
            3) export_agent ;;
            4) delete_agent ;;
            5) start_agent ;;
            6) stop_agent ;;
            7) monitor_agent ;;
            8) list_agents_action ;;
            9) return ;;
            *) echo -e "  ${RED}→ Invalid option. Please enter a number between 1 and 9.${NC}"; sleep 1 ;;
        esac
    done
}

create_agent() {
    clear_screen
    print_header "Create New Agent"
    echo "  This will create a new agent workspace from the template."
    echo "  The agent will have its own isolated directory and Docker volume."
    echo ""

    read -rp "  Enter agent ID (e.g., my-agent): " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    read -rp "  Enter model (e.g., ollama/qwen3:0.6b) [ollama/qwen3:0.6b]: " model
    model="${model:-ollama/qwen3:0.6b}"

    read -rp "  Enter agent name (default: $agent_id): " name
    name="${name:-$agent_id}"

    echo ""
    echo "  Creating agent '$agent_id'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/agent-create.sh" --id "$agent_id" --model "$model" --name "$name"
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Agent '$agent_id' created successfully."
    press_any_key
}

import_agent() {
    clear_screen
    print_header "Import Agent"
    echo "  Enter a staged filename, number, or path (host paths auto-stage):"
    echo ""

    local imports_dir="${IMPORTS_DIR:-/data/imports}"
    local staged=()
    if [[ -d "$imports_dir" ]]; then
        for f in "$imports_dir"/*; do
            [[ -e "$f" ]] || continue
            local bn
            bn="$(basename "$f")"
            [[ "$bn" == ".gitkeep" || "$bn" == .request ]] && continue
            staged+=("$bn")
        done
    fi

    if [[ ${#staged[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}Staged files:${NC}"
        local i=1
        for s in "${staged[@]}"; do
            echo -e "  ${BOLD}${i}.${NC} $s"
            i=$((i + 1))
        done
        echo ""
    fi

    list_available_agents

    echo -e "  ${BOLD}Enter source${NC} (number, filename, or path):"
    read -rp "  > " source
    if [[ -z "$source" ]]; then
        echo "  Cancelled."
        press_any_key
        return
    fi

    # Resolve number selection
    if [[ "$source" =~ ^[0-9]+$ ]] && [[ "$source" -ge 1 ]] && [[ "$source" -le "${#staged[@]}" ]]; then
        source="/data/imports/${staged[$((source - 1))]}"
    fi

    read -rp "  Enter target agent ID (Enter for auto): " target_id

    # Resolve: if not found as-is, try IMPORTS_DIR/basename
    local resolved_source="$source"
    if [[ ! -e "$resolved_source" ]]; then
        local bn
        bn="$(basename "$resolved_source")"
        if [[ -e "${imports_dir}/${bn}" ]]; then
            resolved_source="${imports_dir}/${bn}"
            echo -e "  ${GREEN}Resolved:${NC} $source → $resolved_source"
        else
            # ── Staging request: ask the host watcher to copy the file ──
            echo -e "  ${CYAN}Requesting file from host: $source${NC}"
            mkdir -p "$imports_dir"
            printf 'IMPORT_AGENT\n%s\n%s\n' "$source" "${target_id:-}" > "$imports_dir/.request"

            echo -n "  Staging"
            local attempts=0
            while [[ ! -f "${imports_dir}/${bn}" ]] && [[ $attempts -lt 30 ]]; do
                sleep 2
                attempts=$((attempts + 1))
                echo -n "."
            done
            echo ""

            if [[ -f "${imports_dir}/${bn}" ]]; then
                rm -f "$imports_dir/.request"
                resolved_source="${imports_dir}/${bn}"
                echo -e "  ${GREEN}File staged successfully.${NC}"
            else
                rm -f "$imports_dir/.request"
                echo -e "  ${RED}Staging timed out.${NC}"
                echo -e "  Run on host: ${BOLD}hemlock import $source${target_id:+ $target_id}${NC}"
                press_any_key
                return
            fi
        fi
    fi

    target_id="${target_id:-$(basename "$resolved_source" | sed 's/\.[^.]*$//')}"
    if [[ -z "$target_id" ]]; then
        echo "  Target agent ID is required."
        press_any_key
        return
    fi

    # If agent already exists, ask to overwrite
    local overwrite_flag=""
    if [[ -d "$AGENTS_DIR/$target_id" ]]; then
        echo -e "  ${YELLOW}Agent '$target_id' already exists.${NC}"
        read -rp "  Overwrite? [y/N]: " ow
        if [[ "$ow" =~ ^[Yy]$ ]]; then
            overwrite_flag="--overwrite"
        else
            echo "  Cancelled."
            press_any_key
            return
        fi
    fi

    echo ""
    echo "  Importing agent from '$resolved_source' to '$target_id'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/agent-import.sh" --source "$resolved_source" --target "$target_id" $overwrite_flag
    local import_rc=$?
    echo "$DIVIDER"
    echo ""

    if [[ $import_rc -eq 0 ]]; then
        # Clean up staged file after successful import
        if [[ "$resolved_source" == /data/imports/* ]]; then
            rm -f "$resolved_source"
            echo -e "  ${GREEN}Cleaned up staged file.${NC}"
        fi
        echo "  ✓ Agent '$target_id' imported successfully."
    else
        echo -e "  ${RED}✗ Import failed.${NC}"
    fi
    press_any_key
}

export_agent() {
    clear_screen
    print_header "Export Agent"
    echo "  Export an agent workspace to a tarball archive."
    echo "  Exports land in /data/exports/ (host: volumes/exports/)"
    echo ""

    list_available_agents

    read -rp "  Enter agent ID to export: " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    if [[ ! -d "$AGENTS_DIR/$agent_id" ]]; then
        echo "  → Agent '$agent_id' not found."
        press_any_key
        return
    fi

    read -rp "  Enter export mode (MINIMAL/STANDARD/FULL) [STANDARD]: " mode
    mode="${mode:-STANDARD}"

    local exports_dir="${EXPORTS_DIR:-/data/exports}"
    mkdir -p "$exports_dir"
    local default_dest="$exports_dir/${agent_id}.tar.gz"
    read -rp "  Enter destination path [$default_dest]: " dest
    dest="${dest:-$default_dest}"

    echo ""
    echo "  Exporting agent '$agent_id' to '$dest' (mode: $mode)..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/agent-export.sh" --id "$agent_id" --dest "$dest" --mode "$mode" --non-interactive
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Agent '$agent_id' exported successfully."
    echo -e "  ${GREEN}On host, find it at: volumes/exports/${agent_id}.tar.gz${NC}"
    echo -e "  Copy to host destination with: ${CYAN}hemlock export $agent_id /path/on/host/${NC}"
    echo ""

    # List exports directory
    if [[ -d "$exports_dir" ]]; then
        echo -e "  ${GREEN}Files in exports:${NC}"
        for f in "$exports_dir"/*; do
            [[ -e "$f" ]] || continue
            [[ "$(basename "$f")" == ".gitkeep" ]] && continue
            echo "    $(basename "$f")  ($(du -h "$f" | cut -f1))"
        done
    fi
    press_any_key
}

start_agent() {
    clear_screen
    print_header "Start Agent"
    echo ""

    list_available_agents

    read -rp "  Enter agent ID to start: " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Starting agent '$agent_id'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/agent-control.sh" start "$agent_id"
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Agent '$agent_id' started."
    press_any_key
}

stop_agent() {
    clear_screen
    print_header "Stop Agent"
    echo ""

    list_available_agents

    read -rp "  Enter agent ID to stop: " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Stopping agent '$agent_id'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/agent-control.sh" stop "$agent_id"
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Agent '$agent_id' stopped."
    press_any_key
}

monitor_agent() {
    clear_screen
    print_header "Monitor Agent"
    echo ""

    list_available_agents

    read -rp "  Enter agent ID to monitor: " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Monitoring agent '$agent_id' (Ctrl+C to exit)..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/agent-monitor.sh" "$agent_id" || true
    press_any_key
}

list_agents_action() {
    clear_screen
    print_header "List Agents"
    echo ""
    list_available_agents
    press_any_key
}

# ── Crew Management ───────────────────────────────────────────────────────────

crew_menu() {
    while true; do
        clear_screen
        print_header "Crew Management (A2A Orchestration)"
        echo -e "  ${BOLD}1.${NC} Create New Crew"
        echo -e "  ${BOLD}2.${NC} Import Crew"
        echo -e "  ${BOLD}3.${NC} Export Crew"
        echo -e "  ${BOLD}4.${NC} Join Crew"
        echo -e "  ${BOLD}5.${NC} Leave Crew"
        echo -e "  ${BOLD}6.${NC} List All Crews"
        echo -e "  ${BOLD}7.${NC} Start Crew"
        echo -e "  ${BOLD}8.${NC} Monitor Crew"
        echo -e "  ${BOLD}9.${NC} Dissolve Crew"
        echo -e "  ${BOLD}0.${NC} Back to Main Menu"
        echo "$DIVIDER"

        read -rp "  Select option [0-9]: " choice
        case "$choice" in
            1) create_crew ;;
            2) import_crew ;;
            3) export_crew ;;
            4) join_crew ;;
            5) leave_crew ;;
            6) list_crews_action ;;
            7) start_crew ;;
            8) monitor_crew ;;
            9) dissolve_crew ;;
            0) return ;;
            *) echo -e "  ${RED}→ Invalid option. Please enter a number between 0 and 9.${NC}"; sleep 1 ;;
        esac
    done
}

create_crew() {
    clear_screen
    print_header "Create New Crew"
    echo "  Create a crew of agents that work together on tasks."
    echo ""

    list_available_agents

    read -rp "  Enter crew name (e.g., dev-team): " crew_name
    if [[ -z "$crew_name" ]]; then
        echo "  → Crew name is required."
        press_any_key
        return
    fi

    read -rp "  Enter agent IDs separated by space (e.g., agent1 agent2): " agents
    if [[ -z "$agents" ]]; then
        echo "  → At least one agent ID is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Creating crew '$crew_name' with agents: $agents"
    echo "$DIVIDER"
    "$SCRIPT_DIR/crew-create.sh" "$crew_name" $agents
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Crew '$crew_name' created successfully."
    press_any_key
}

import_crew() {
    clear_screen
    print_header "Import Crew"
    echo "  Enter a staged filename, number, or any path."
    echo ""

    local imports_dir="${IMPORTS_DIR:-/data/imports}"
    local staged=()
    if [[ -d "$imports_dir" ]]; then
        for f in "$imports_dir"/*; do
            [[ -e "$f" ]] || continue
            local bn
            bn="$(basename "$f")"
            [[ "$bn" == ".gitkeep" || "$bn" == .request ]] && continue
            staged+=("$bn")
        done
    fi

    if [[ ${#staged[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}Staged files:${NC}"
        local i=1
        for s in "${staged[@]}"; do
            echo -e "  ${BOLD}${i}.${NC} $s"
            i=$((i + 1))
        done
        echo ""
    fi

    list_available_crews

    echo -e "  ${BOLD}Enter source${NC} (number, filename, or path):"
    read -rp "  > " source
    if [[ -z "$source" ]]; then
        echo "  Cancelled."
        press_any_key
        return
    fi

    # Resolve number selection
    if [[ "$source" =~ ^[0-9]+$ ]] && [[ "$source" -ge 1 ]] && [[ "$source" -le "${#staged[@]}" ]]; then
        source="/data/imports/${staged[$((source - 1))]}"
    fi

    read -rp "  Crew name (Enter for auto): " crew_name

    # Resolve: if not found as-is, try IMPORTS_DIR/basename
    local resolved_source="$source"
    if [[ ! -e "$resolved_source" ]]; then
        local bn
        bn="$(basename "$resolved_source")"
        if [[ -e "${imports_dir}/${bn}" ]]; then
            resolved_source="${imports_dir}/${bn}"
            echo -e "  ${GREEN}Resolved:${NC} $source → $resolved_source"
        else
            # ── Staging request: ask the host watcher to copy the file ──
            echo -e "  ${CYAN}Requesting file from host: $source${NC}"
            mkdir -p "$imports_dir"
            printf 'IMPORT_CREW\n%s\n%s\n' "$source" "${crew_name:-}" > "$imports_dir/.request"

            echo -n "  Staging"
            local attempts=0
            while [[ ! -f "${imports_dir}/${bn}" ]] && [[ $attempts -lt 30 ]]; do
                sleep 2
                attempts=$((attempts + 1))
                echo -n "."
            done
            echo ""

            if [[ -f "${imports_dir}/${bn}" ]]; then
                rm -f "$imports_dir/.request"
                resolved_source="${imports_dir}/${bn}"
                echo -e "  ${GREEN}File staged successfully.${NC}"
            else
                rm -f "$imports_dir/.request"
                echo -e "  ${RED}Staging timed out.${NC}"
                echo -e "  Run on host: ${BOLD}hemlock crew-import $source${crew_name:+ $crew_name}${NC}"
                press_any_key
                return
            fi
        fi
    fi

    echo ""
    echo "  Importing crew from '$resolved_source'..."
    echo "$DIVIDER"
    local flags="--force"
    [[ -n "$crew_name" ]] && flags="$flags --name $crew_name"
    "$SCRIPT_DIR/crew-import.sh" "$resolved_source" $flags
    local import_rc=$?
    echo "$DIVIDER"
    echo ""

    if [[ $import_rc -eq 0 ]]; then
        # Clean up staged file after successful import
        if [[ "$resolved_source" == /data/imports/* ]]; then
            rm -f "$resolved_source"
            echo -e "  ${GREEN}Cleaned up staged file.${NC}"
        fi
        echo "  ✓ Crew imported successfully."
    else
        echo -e "  ${RED}✗ Import failed.${NC}"
    fi
    press_any_key
}

export_crew() {
    clear_screen
    print_header "Export Crew"
    echo "  Export a crew configuration for backup or transfer."
    echo "  Exports land in /data/exports/ (host: volumes/exports/)"
    echo ""

    list_available_crews

    read -rp "  Enter crew name to export: " crew_name
    if [[ -z "$crew_name" ]]; then
        echo "  → Crew name is required."
        press_any_key
        return
    fi

    if [[ ! -d "$CREWS_DIR/$crew_name" ]]; then
        echo "  → Crew '$crew_name' not found."
        press_any_key
        return
    fi

    local exports_dir="${EXPORTS_DIR:-/data/exports}"
    mkdir -p "$exports_dir"
    local default_dest="$exports_dir/${crew_name}.tar.gz"
    read -rp "  Enter destination [$default_dest]: " dest
    dest="${dest:-$default_dest}"

    echo ""
    echo "  Exporting crew '$crew_name'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/crew-export.sh" "$crew_name" --dest "$dest" --compress
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Crew '$crew_name' exported successfully."
    echo -e "  ${GREEN}On host: volumes/exports/${crew_name}.tar.gz${NC}"
    echo -e "  Copy to host: ${CYAN}hemlock crew-export $crew_name /path/on/host/${NC}"
    press_any_key
}

join_crew() {
    clear_screen
    print_header "Join Crew"
    echo ""

    list_available_crews

    read -rp "  Enter crew name: " crew_name
    if [[ -z "$crew_name" ]]; then
        echo "  → Crew name is required."
        press_any_key
        return
    fi

    list_available_agents

    read -rp "  Enter agent ID to add: " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Adding '$agent_id' to crew '$crew_name'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/crew-join.sh" "$crew_name" "$agent_id"
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Agent '$agent_id' added to crew '$crew_name'."
    press_any_key
}

leave_crew() {
    clear_screen
    print_header "Leave Crew"
    echo ""

    list_available_crews

    read -rp "  Enter crew name: " crew_name
    if [[ -z "$crew_name" ]]; then
        echo "  → Crew name is required."
        press_any_key
        return
    fi

    list_available_agents

    read -rp "  Enter agent ID to remove: " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Removing '$agent_id' from crew '$crew_name'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/crew-leave.sh" "$crew_name" "$agent_id"
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Agent '$agent_id' removed from crew '$crew_name'."
    press_any_key
}

list_crews_action() {
    clear_screen
    print_header "List Crews"
    echo ""
    list_available_crews
    press_any_key
}

start_crew() {
    clear_screen
    print_header "Start Crew"
    echo ""

    list_available_crews

    read -rp "  Enter crew name to start: " crew_name
    if [[ -z "$crew_name" ]]; then
        echo "  → Crew name is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Starting crew '$crew_name'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/crew-start.sh" "$crew_name"
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Crew '$crew_name' started."
    press_any_key
}

monitor_crew() {
    clear_screen
    print_header "Monitor Crew"
    echo ""

    list_available_crews

    read -rp "  Enter crew name to monitor: " crew_name
    if [[ -z "$crew_name" ]]; then
        echo "  → Crew name is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Monitoring crew '$crew_name' (Ctrl+C to exit)..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/crew-monitor.sh" "$crew_name" || true
    press_any_key
}

dissolve_crew() {
    clear_screen
    print_header "Dissolve Crew"
    echo "  WARNING: This will stop all agents in the crew!"
    echo ""

    list_available_crews

    read -rp "  Enter crew name to dissolve: " crew_name
    if [[ -z "$crew_name" ]]; then
        echo "  → Crew name is required."
        press_any_key
        return
    fi

    if ! confirm_action "  Are you sure you want to dissolve crew '$crew_name'?"; then
        echo "  → Cancelled."
        press_any_key
        return
    fi

    echo ""
    echo "  Dissolving crew '$crew_name'..."
    echo "$DIVIDER"
    "$SCRIPT_DIR/crew-dissolve.sh" "$crew_name"
    echo "$DIVIDER"
    echo ""
    echo "  ✓ Crew '$crew_name' dissolved."
    press_any_key
}

# ── Validation ────────────────────────────────────────────────────────────────

validation_menu() {
    while true; do
        clear_screen
        print_header "Runtime Validation"
        echo -e "  ${BOLD}1.${NC} Run Full Validation"
        echo -e "  ${BOLD}2.${NC} Hemlock Doctor (Interactive)"
        echo -e "  ${BOLD}3.${NC} Check Docker Environment"
        echo -e "  ${BOLD}4.${NC} Validate Configurations"
        echo -e "  ${BOLD}5.${NC} Back to Main Menu"
        echo "$DIVIDER"

        read -rp "  Select option [1-5]: " choice
        case "$choice" in
            1) run_validation ;;
            2) hermes_doctor ;;
            3) check_docker ;;
            4) validate_configs ;;
            5) return ;;
            *) echo -e "  ${RED}→ Invalid option. Please enter a number between 1 and 5.${NC}"; sleep 1 ;;
        esac
    done
}

run_validation() {
    clear_screen
    print_header "Running Full Validation"
    echo ""
    "$SCRIPT_DIR/runtime-doctor.sh" --full
    echo ""
    press_any_key
}

hermes_doctor() {
    clear_screen
    print_header "Hemlock Doctor - Interactive Validation"
    echo ""
    "$SCRIPT_DIR/runtime-doctor.sh" --interactive
    echo ""
    press_any_key
}

check_docker() {
    clear_screen
    print_header "Checking Docker Environment"
    echo ""
    "$SCRIPT_DIR/runtime-doctor.sh" --docker
    echo ""
    press_any_key
}

validate_configs() {
    clear_screen
    print_header "Validating Configurations"
    echo ""
    "$SCRIPT_DIR/runtime-doctor.sh" --config
    echo ""
    press_any_key
}

# ── Security ──────────────────────────────────────────────────────────────────

security_menu() {
    while true; do
        clear_screen
        print_header "Security Hardening"
        echo -e "  ${BOLD}1.${NC} Apply Security Hardening"
        echo -e "  ${BOLD}2.${NC} Check Security Status"
        echo -e "  ${BOLD}3.${NC} Reset Security Settings"
        echo -e "  ${BOLD}4.${NC} Back to Main Menu"
        echo "$DIVIDER"

        read -rp "  Select option [1-4]: " choice
        case "$choice" in
            1) apply_security_hardening ;;
            2) check_security_status ;;
            3) reset_security ;;
            4) return ;;
            *) echo -e "  ${RED}→ Invalid option. Please enter a number between 1 and 4.${NC}"; sleep 1 ;;
        esac
    done
}

apply_security_hardening() {
    clear_screen
    print_header "Applying Security Hardening"
    echo ""
    "$SCRIPT_DIR/security-harden.sh" --apply
    echo ""
    echo "  ✓ Security hardening applied."
    press_any_key
}

check_security_status() {
    clear_screen
    print_header "Checking Security Status"
    echo ""
    "$SCRIPT_DIR/security-harden.sh" --check
    echo ""
    press_any_key
}

reset_security() {
    clear_screen
    print_header "Reset Security Settings"
    echo "  WARNING: This will reset security settings to defaults!"
    echo ""

    if ! confirm_action "  Are you sure?"; then
        echo "  → Cancelled."
        press_any_key
        return
    fi

    echo ""
    "$SCRIPT_DIR/security-harden.sh" --reset
    echo ""
    echo "  ✓ Security settings reset."
    press_any_key
}

# ── Monitoring ────────────────────────────────────────────────────────────────

monitoring_menu() {
    while true; do
        clear_screen
        print_header "System Monitoring"
        echo -e "  ${BOLD}1.${NC} View Runtime Logs"
        echo -e "  ${BOLD}2.${NC} View Agent Logs"
        echo -e "  ${BOLD}3.${NC} Check System Health"
        echo -e "  ${BOLD}4.${NC} Back to Main Menu"
        echo "$DIVIDER"

        read -rp "  Select option [1-4]: " choice
        case "$choice" in
            1) view_runtime_logs ;;
            2) view_agent_logs ;;
            3) check_system_health ;;
            4) return ;;
            *) echo -e "  ${RED}→ Invalid option. Please enter a number between 1 and 4.${NC}"; sleep 1 ;;
        esac
    done
}

view_runtime_logs() {
    clear_screen
    print_header "Runtime Logs (Ctrl+C to exit)"
    echo ""
    if [[ -f "$LOGS_DIR/runtime.log" ]]; then
        tail -f "$LOGS_DIR/runtime.log"
    else
        echo "  No runtime logs found."
        press_any_key
    fi
}

view_agent_logs() {
    clear_screen
    print_header "View Agent Logs"
    echo ""

    list_available_agents

    read -rp "  Enter agent ID: " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    echo ""
    echo "  Logs for agent '$agent_id' (Ctrl+C to exit)..."
    echo "$DIVIDER"
    if [[ -f "$LOGS_DIR/$agent_id.log" ]]; then
        tail -f "$LOGS_DIR/$agent_id.log"
    else
        echo "  No logs found for agent '$agent_id'."
        press_any_key
    fi
}

check_system_health() {
    clear_screen
    print_header "System Health Check"
    echo ""
    echo "  Docker Containers:"
    docker ps 2>/dev/null || echo "  (Docker not available)"
    echo ""
    echo "  Disk Usage:"
    df -h / 2>/dev/null | tail -1
    echo ""
    echo "  Memory Usage:"
    free -h 2>/dev/null | grep -i mem || echo "  (free command not available)"
    echo ""
    press_any_key
}

# ── Configuration ─────────────────────────────────────────────────────────────

config_menu() {
    while true; do
        clear_screen
        print_header "Configuration Management"
        echo -e "  ${BOLD}1.${NC} Edit Runtime Configuration"
        echo -e "  ${BOLD}2.${NC} Edit Agent Configuration"
        echo -e "  ${BOLD}3.${NC} View Current Configuration"
        echo -e "  ${BOLD}4.${NC} Back to Main Menu"
        echo "$DIVIDER"

        read -rp "  Select option [1-4]: " choice
        case "$choice" in
            1) edit_runtime_config ;;
            2) edit_agent_config ;;
            3) view_config ;;
            4) return ;;
            *) echo -e "  ${RED}→ Invalid option. Please enter a number between 1 and 4.${NC}"; sleep 1 ;;
        esac
    done
}

edit_runtime_config() {
    clear_screen
    print_header "Edit Runtime Configuration"
    echo ""

    if [[ ! -f "$CONFIG_DIR/runtime.yaml" ]]; then
        echo "  → No runtime configuration found. Creating default..."
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_DIR/runtime.yaml" <<EOF
# Hemlock Runtime Configuration
runtime:
  gateway:
    port: 1437
  agents:
    default_model: "ollama/qwen3:0.6b"
EOF
    fi

    echo "  Opening runtime configuration in editor..."
    "${EDITOR:-nano}" "$CONFIG_DIR/runtime.yaml"
    echo "  ✓ Configuration saved."
    press_any_key
}

edit_agent_config() {
    clear_screen
    print_header "Edit Agent Configuration"
    echo ""

    list_available_agents

    read -rp "  Enter agent ID: " agent_id
    if [[ -z "$agent_id" ]]; then
        echo "  → Agent ID is required."
        press_any_key
        return
    fi

    local config_file="$AGENTS_DIR/$agent_id/config.yaml"
    if [[ ! -f "$config_file" ]]; then
        echo "  → No configuration found for agent '$agent_id'."
        press_any_key
        return
    fi

    echo "  Opening configuration for agent '$agent_id'..."
    "${EDITOR:-nano}" "$config_file"
    echo "  ✓ Configuration saved."
    press_any_key
}

view_config() {
    clear_screen
    print_header "Current Configuration"
    echo ""

    echo "  Runtime Configuration:"
    if [[ -f "$CONFIG_DIR/runtime.yaml" ]]; then
        cat "$CONFIG_DIR/runtime.yaml"
    else
        echo "  (none)"
    fi
    echo ""
    press_any_key
}

# ── Knowledge Base (global links & docs) ──────────────────────────────────────
# Owner-facing management of the runtime-root, append-only knowledge store.
# Agents capture links/docs automatically; here the OWNER can review, reclassify,
# add, archive (soft-remove — nothing is erased), and restore them.

_kc() {  # resolve the knowledge engine wrapper (sibling of this script)
    local kc="$SCRIPT_DIR/knowledge-capture.sh"
    [ -x "$kc" ] || kc="/scripts/knowledge-capture.sh"
    "$kc" "$@"
}

knowledge_menu() {
    while true; do
        clear_screen
        print_header "Knowledge Base — Links & Docs"
        echo -e "  ${BOLD}1.${NC} Overview / status"
        echo -e "  ${BOLD}2.${NC} List links"
        echo -e "  ${BOLD}3.${NC} Search"
        echo -e "  ${BOLD}4.${NC} View a link (details)"
        echo -e "  ${BOLD}5.${NC} Add a link"
        echo -e "  ${BOLD}6.${NC} Edit a link's classification"
        echo -e "  ${BOLD}7.${NC} Archive a link (soft-remove)"
        echo -e "  ${BOLD}8.${NC} Restore an archived link"
        echo -e "  ${BOLD}9.${NC} View capture log"
        echo -e "  ${BOLD}10.${NC} Back to Main Menu"
        echo "$DIVIDER"

        read -rp "  Select option [1-10]: " choice
        case "$choice" in
            1) clear_screen; print_header "Knowledge — Status"; echo ""; _kc status; echo ""; press_any_key ;;
            2) clear_screen; print_header "Knowledge — Links"; echo ""; _kc list --links; echo ""; press_any_key ;;
            3) clear_screen; print_header "Knowledge — Search"; echo ""
               read -rp "  Query: " q
               [ -n "$q" ] && { echo ""; _kc search $q; } || echo "  → Query required."
               echo ""; press_any_key ;;
            4) clear_screen; print_header "Knowledge — View Link"; echo ""
               _kc list --links; echo ""
               read -rp "  Link id or url: " ref
               [ -n "$ref" ] && { echo ""; _kc show "$ref"; } || echo "  → id/url required."
               echo ""; press_any_key ;;
            5) knowledge_add_link ;;
            6) knowledge_edit_link ;;
            7) clear_screen; print_header "Knowledge — Archive Link"; echo ""
               _kc list --links; echo ""
               read -rp "  Link id or url to archive: " ref
               if [ -n "$ref" ]; then
                   read -rp "  Reason (optional): " reason
                   echo ""; _kc archive "$ref" ${reason:+--reason "$reason"}
               else echo "  → id/url required."; fi
               echo ""; press_any_key ;;
            8) clear_screen; print_header "Knowledge — Restore Link"; echo ""
               _kc archived; echo ""
               read -rp "  Archived link id or url to restore: " ref
               [ -n "$ref" ] && { echo ""; _kc restore "$ref"; } || echo "  → id/url required."
               echo ""; press_any_key ;;
            9) clear_screen; print_header "Knowledge — Capture Log (recent)"; echo ""
               local kdir="${HEMLOCK_KNOWLEDGE_DIR:-${RUNTIME_ROOT:-/data}/knowledge}"
               if [ -f "$kdir/CAPTURE-LOG.md" ]; then tail -n 40 "$kdir/CAPTURE-LOG.md"
               else echo "  (no captures yet)"; fi
               echo ""; press_any_key ;;
            10) return ;;
            *) echo -e "  ${RED}→ Invalid option. Please enter a number between 1 and 10.${NC}"; sleep 1 ;;
        esac
    done
}

knowledge_add_link() {
    clear_screen; print_header "Knowledge — Add Link"; echo ""
    read -rp "  URL (required): " url
    if [ -z "$url" ]; then echo "  → URL required."; press_any_key; return; fi
    read -rp "  Title (optional): " title
    read -rp "  Use — what it's for (reference/api/code/dataset/llm-context…): " use
    read -rp "  Function — what it does (documentation/repository/…): " func
    read -rp "  Scope (global | agent:<id> | project:<name>) [global]: " scope
    local args=(url "$url")
    [ -n "$title" ] && args+=(--title "$title")
    [ -n "$use" ]   && args+=(--use "$use")
    [ -n "$func" ]  && args+=(--function "$func")
    [ -n "$scope" ] && args+=(--scope "$scope")
    args+=(--source owner:menu)
    echo ""; _kc "${args[@]}"; echo ""; press_any_key
}

knowledge_edit_link() {
    clear_screen; print_header "Knowledge — Edit Link"; echo ""
    _kc list --links; echo ""
    read -rp "  Link id or url to edit: " ref
    if [ -z "$ref" ]; then echo "  → id/url required."; press_any_key; return; fi
    echo "  (leave a field blank to keep it unchanged)"
    read -rp "  New title: " title
    read -rp "  New use: " use
    read -rp "  New function: " func
    read -rp "  New scope: " scope
    read -rp "  Add tag: " addtag
    read -rp "  Remove tag: " deltag
    local args=(edit "$ref")
    [ -n "$title" ]  && args+=(--title "$title")
    [ -n "$use" ]    && args+=(--use "$use")
    [ -n "$func" ]   && args+=(--function "$func")
    [ -n "$scope" ]  && args+=(--scope "$scope")
    [ -n "$addtag" ] && args+=(--add-tag "$addtag")
    [ -n "$deltag" ] && args+=(--del-tag "$deltag")
    echo ""; _kc "${args[@]}"; echo ""; press_any_key
}

# ── Backup & Restore ───────────────────────────────────────────────────────
# Owner-facing. TWO modes, you choose: FULL (entire persistent data state) or
# CUSTOM (pick one volume + its contents + destination, optionally scheduled).
# Both encrypt sensitive material at rest.

_bk() {  # resolve the backup tool (sibling of this script)
    local b="$SCRIPT_DIR/backup.sh"; [ -x "$b" ] || b="/scripts/backup.sh"
    "$b" "$@"
}

backup_menu() {
    while true; do
        clear_screen
        print_header "Backup & Restore"
        echo -e "  ${BOLD}1.${NC} Full backup — ENTIRE persistent data state"
        echo -e "  ${BOLD}2.${NC} Custom backup — pick a volume & contents"
        echo -e "  ${BOLD}3.${NC} Restore from a backup"
        echo -e "  ${BOLD}4.${NC} Backup status (list existing backups)"
        echo -e "  ${BOLD}5.${NC} Configure (destination / schedule / defaults)"
        echo -e "  ${BOLD}6.${NC} Initialize / check encryption key"
        echo -e "  ${BOLD}7.${NC} Back to Main Menu"
        echo "$DIVIDER"

        read -rp "  Select option [1-7]: " choice
        case "$choice" in
            1) clear_screen; print_header "Full Backup"; echo ""
               echo "  Backs up the ENTIRE persistent data state (all agents, crews,"
               echo "  global knowledge, config), encrypted by default — AND, when a"
               echo "  Ventoy USB is present, its delegated .dat persistence images"
               echo "  + ventoy.json (the OUTER state). You cannot copy a .dat you are"
               echo "  booted into; in-use images are detected and skipped."; echo ""
               read -rp "  Destination [default configured]: " dest
               read -rp "  Proceed? [y/N]: " ok
               case "$ok" in y|Y) echo ""; _bk full ${dest:+--dest "$dest"} ;; *) echo "  cancelled" ;; esac
               echo ""; press_any_key ;;
            2) backup_custom ;;
            3) backup_restore ;;
            4) clear_screen; print_header "Backup Status"; echo ""; _bk status; echo ""; press_any_key ;;
            5) backup_configure ;;
            6) clear_screen; print_header "Backup Encryption Key"; echo ""; _bk init; echo ""; press_any_key ;;
            7) return ;;
            *) echo -e "  ${RED}→ Invalid option. Please enter a number between 1 and 7.${NC}"; sleep 1 ;;
        esac
    done
}

backup_custom() {
    clear_screen; print_header "Custom Backup"; echo ""
    _bk list-volumes; echo ""
    echo "  Tip: use @ventoy (entire USB persistence) or dat:<name> (one .dat image)"
    echo "       to back up the Ventoy layer — do this from OUTSIDE the persistence."
    read -rp "  Volume (agent id, crew:<name>, @knowledge, @ventoy, dat:<name>): " vol
    [ -z "$vol" ] && { echo "  → volume required."; press_any_key; return; }
    echo "  Contents to include (comma-separated), or blank for default."
    echo "  Categories: memory identity sessions skills projects knowledge tools secrets logs  (or 'all')"
    read -rp "  Include: " inc
    read -rp "  Destination [default configured]: " dest
    read -rp "  Encrypt? (auto/yes/no) [auto]: " enc
    local args=(backup "$vol")
    [ -n "$inc" ]  && args+=(--include "$inc")
    [ -n "$dest" ] && args+=(--dest "$dest")
    case "$enc" in yes) args+=(--encrypt) ;; no) args+=(--no-encrypt) ;; esac
    echo ""; _bk "${args[@]}"; echo ""; press_any_key
}

backup_restore() {
    clear_screen; print_header "Restore from Backup"; echo ""
    _bk status; echo ""
    read -rp "  Full path to the archive (.tar.gz or .tar.gz.enc): " arch
    [ -z "$arch" ] && { echo "  → archive path required."; press_any_key; return; }
    read -rp "  Restore into volume (blank = use archive's own volume): " into
    read -rp "  Dry run first? [Y/n]: " dry
    local args=(restore "$arch"); [ -n "$into" ] && args+=(--into "$into")
    case "$dry" in n|N) ;; *) echo ""; _bk "${args[@]}" --dry-run; echo ""
        read -rp "  Proceed with actual restore? [y/N]: " go
        case "$go" in y|Y) ;; *) echo "  cancelled"; press_any_key; return ;; esac ;;
    esac
    echo ""; _bk "${args[@]}"; echo ""; press_any_key
}

backup_configure() {
    while true; do
        clear_screen; print_header "Backup Configuration"; echo ""
        _bk config get; echo ""; echo "$DIVIDER"
        echo -e "  ${BOLD}1.${NC} Set default destination"
        echo -e "  ${BOLD}2.${NC} Set default contents"
        echo -e "  ${BOLD}3.${NC} Set a volume's schedule (daily/weekly/monthly/off)"
        echo -e "  ${BOLD}4.${NC} Set a volume's destination"
        echo -e "  ${BOLD}5.${NC} Back"
        read -rp "  Select [1-5]: " c
        case "$c" in
            1) read -rp "  Default destination path: " v; [ -n "$v" ] && _bk config set-default destination "$v"; press_any_key ;;
            2) read -rp "  Default include (csv or 'all'): " v; [ -n "$v" ] && _bk config set-default include "$v"; press_any_key ;;
            3) read -rp "  Volume: " vv; read -rp "  Schedule (daily/weekly/monthly/off): " s
               [ -n "$vv" ] && [ -n "$s" ] && _bk config set-volume "$vv" schedule "$s"; press_any_key ;;
            4) read -rp "  Volume: " vv; read -rp "  Destination: " d
               [ -n "$vv" ] && [ -n "$d" ] && _bk config set-volume "$vv" destination "$d"; press_any_key ;;
            5) return ;;
            *) echo -e "  ${RED}→ Invalid.${NC}"; sleep 1 ;;
        esac
    done
}

# ── Initialize ────────────────────────────────────────────────────────────────

initialize_runtime() {
    echo "Initializing Hemlock Runtime..."

    if [[ ! -f "$CONFIG_DIR/runtime.yaml" ]]; then
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_DIR/runtime.yaml" <<EOF
# Hemlock Runtime Configuration
runtime:
  gateway:
    port: 1437
    token: "$(openssl rand -hex 16 2>/dev/null || echo 'change-me')"
  agents:
    default_model: "ollama/qwen3:0.6b"
EOF
    fi

    echo "Runtime initialized."
    press_any_key
}

# ── Main ──────────────────────────────────────────────────────────────────────

if [[ ! -f "$CONFIG_DIR/runtime.yaml" ]]; then
    initialize_runtime
fi

main_menu
