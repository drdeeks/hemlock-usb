#!/bin/bash
# =============================================================================
# hemlock-stage — Host-side staging bridge for Hemlock container imports/exports
#
# Runs ON THE HOST, not inside Docker. Bridges host filesystem paths
# to container-accessible staging areas via bind mounts.
#
# Staging areas:
#   volumes/imports/ → /data/imports/  (host → container)
#   volumes/exports/ → /data/exports/ (container → host)
#
# Always copies (never symlinks) for portability across devices.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IMPORTS_HOST="${PROJECT_ROOT}/volumes/imports"
EXPORTS_HOST="${PROJECT_ROOT}/volumes/exports"
CONTAINER_NAME="${HEMLOCK_CONTAINER:-hemlock_runtime}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${BLUE}[STAGE]${NC} $1"; }
ok()    { echo -e "${GREEN}[  OK ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[FAIL]${NC} $1"; }

usage() {
    cat <<EOF
${BOLD}hemlock-stage${NC} — Host-side staging bridge for Hemlock

${BOLD}USAGE${NC}
  $0 <command> [arguments]

${BOLD}COMMANDS${NC}
  import <host_path> [agent_id]   Copy file into staging and import agent
  export <agent_id> [host_dest]  Export agent and copy to host destination
  crew-import <host_path> [name]   Stage and import crew
  crew-export <name> [host_dest]   Export crew and copy to host destination
  list-imports                   List files in import staging area
  list-exports                   List files in export staging area
  clean-imports                  Remove all files from import staging
  clean-exports                  Remove all files from export staging
  stage <host_path>              Copy file to import staging (no import)
  pull <filename> [host_dest]    Copy file from export staging to host
  up                             Start Hemlock runtime container
  down                           Stop Hemlock runtime container
  status                         Show runtime status and staged files
  shell                          Shell into running container
  menu                           Open interactive runtime menu

${BOLD}IMPORT${NC}
  Copies the source file/directory to volumes/imports/, then execs into
  the running container to run agent-import.sh.

  If no agent_id given, derives from filename.

  Examples:
    $0 import /home/user/downloads/aton.zip aton
    $0 import /home/user/downloads/agents/allman/

${BOLD}EXPORT${NC}
  Execs into container to export agent to /data/exports/, then copies
  the result to an optional host destination.

  If no host_dest given, file remains in volumes/exports/.

  Examples:
    $0 export aton /media/91BD-23E7/hemlock/
    $0 export aton

${BOLD}STAGING${NC}
  volumes/imports/  →  /data/imports/   (bind-mounted into container)
  volumes/exports/  →  /data/exports/   (bind-mounted into container)
EOF
    exit 0
}

_ensure_dirs() {
    mkdir -p "$IMPORTS_HOST" "$EXPORTS_HOST"
}

_is_container_running() {
    docker ps -q -f name="$CONTAINER_NAME" 2>/dev/null | grep -q .
}

_container_exec() {
    if _is_container_running; then
        docker exec -i "$CONTAINER_NAME" "$@"
    else
        err "Container '$CONTAINER_NAME' is not running."
        err "Start it with: docker compose -f docker-compose.runtime.yml up -d"
        return 1
    fi
}

cmd_import() {
    local host_path="${1:-}"
    local agent_id="${2:-}"

    [[ -z "$host_path" ]] && { err "Usage: $0 import <host_path> [agent_id]"; return 1; }
    [[ ! -e "$host_path" ]] && { err "Source not found: $host_path"; return 1; }

    _ensure_dirs

    local basename
    basename="$(basename "$host_path")"

    if [[ -d "$host_path" ]]; then
        basename="${basename}.tar.gz"
        log "Compressing directory: $host_path"
        tar -czf "$IMPORTS_HOST/$basename" -C "$(dirname "$host_path")" "$(basename "$host_path")"
        ok "Compressed to: $IMPORTS_HOST/$basename"
    else
        log "Copying: $host_path → $IMPORTS_HOST/$basename"
        cp -a "$host_path" "$IMPORTS_HOST/$basename"
        ok "Copied to: $IMPORTS_HOST/$basename"
    fi

    [[ -z "$agent_id" ]] && agent_id="${basename%%.*}"
    agent_id="${agent_id// /-}"

    local container_path="/data/imports/$basename"
    log "Staged at container path: $container_path"
    log "Importing as agent: $agent_id"

    if _is_container_running; then
        log "Running agent-import.sh inside container..."
        _container_exec /opt/hermes/scripts/agent-import.sh --source "$container_path" --target "$agent_id" --non-interactive
        local rc=$?
        if [[ $rc -eq 0 ]]; then
            ok "Agent '$agent_id' imported successfully"
            log "Cleaning staged file..."
            rm -f "$IMPORTS_HOST/$basename"
            ok "Staged file removed"
        else
            err "Import failed with exit code $rc"
            warn "Staged file kept at: $IMPORTS_HOST/$basename"
            return $rc
        fi
    else
        warn "Container not running. Attempting to start..."
        cmd_up
        if _is_container_running; then
            log "Running agent-import.sh inside container..."
            _container_exec /opt/hermes/scripts/agent-import.sh --source "$container_path" --target "$agent_id" --non-interactive
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                ok "Agent '$agent_id' imported successfully"
                rm -f "$IMPORTS_HOST/$basename"
            else
                err "Import failed with exit code $rc"
                warn "Staged file kept at: $IMPORTS_HOST/$basename"
                return $rc
            fi
        else
            warn "Cannot start container. File staged but not imported."
            log "Start the container, then run:"
            log "  docker exec hemlock_runtime agent-import.sh --source $container_path --target $agent_id"
        fi
    fi
}

cmd_export() {
    local agent_id="${1:-}"
    local host_dest="${2:-}"

    [[ -z "$agent_id" ]] && { err "Usage: $0 export <agent_id> [host_dest]"; return 1; }

    _ensure_dirs

    local dest_path="/data/exports/${agent_id}.tar.gz"

    if _is_container_running; then
        log "Exporting agent '$agent_id' inside container..."
        _container_exec /opt/hermes/scripts/agent-export.sh --id "$agent_id" --dest "$dest_path" --mode STANDARD --non-interactive
        local rc=$?
        if [[ $rc -ne 0 ]]; then
            err "Export failed with exit code $rc"
            return $rc
        fi
        ok "Agent exported to container path: $dest_path"
    else
        warn "Container not running. Attempting to start..."
        cmd_up
        if _is_container_running; then
            log "Exporting agent '$agent_id' inside container..."
            _container_exec /opt/hermes/scripts/agent-export.sh --id "$agent_id" --dest "$dest_path" --mode STANDARD --non-interactive
            local rc=$?
            if [[ $rc -ne 0 ]]; then
                err "Export failed with exit code $rc"
                return $rc
            fi
            ok "Agent exported to container path: $dest_path"
        else
            err "Cannot start container."
            return 1
        fi
    fi

    if [[ -n "$host_dest" ]]; then
        mkdir -p "$host_dest"
        local src_file="$EXPORTS_HOST/${agent_id}.tar.gz"
        if [[ -f "$src_file" ]]; then
            log "Copying to host: $host_dest"
            cp -a "$src_file" "$host_dest/"
            ok "Copied to: $host_dest/${agent_id}.tar.gz"
        else
            err "Export file not found at: $src_file"
            err "Check volumes/exports/ for the file"
            return 1
        fi
    else
        ok "Export file available at: $EXPORTS_HOST/${agent_id}.tar.gz"
        log "Copy to host with: $0 pull ${agent_id}.tar.gz [destination]"
    fi
}

cmd_crew_import() {
    local host_path="${1:-}"
    local crew_name="${2:-}"

    [[ -z "$host_path" ]] && { err "Usage: $0 crew-import <host_path> [crew_name]"; return 1; }
    [[ ! -e "$host_path" ]] && { err "Source not found: $host_path"; return 1; }

    _ensure_dirs

    local basename
    basename="$(basename "$host_path")"

    if [[ -d "$host_path" ]]; then
        basename="${basename}.tar.gz"
        log "Compressing directory: $host_path"
        tar -czf "$IMPORTS_HOST/$basename" -C "$(dirname "$host_path")" "$(basename "$host_path")"
        ok "Compressed to: $IMPORTS_HOST/$basename"
    else
        log "Copying: $host_path → $IMPORTS_HOST/$basename"
        cp -a "$host_path" "$IMPORTS_HOST/$basename"
        ok "Copied to: $IMPORTS_HOST/$basename"
    fi

    local container_path="/data/imports/$basename"

    if _is_container_running; then
        log "Running crew-import inside container..."
        local flags="--force"
        [[ -n "$crew_name" ]] && flags="$flags --name $crew_name"
        _container_exec /opt/hermes/scripts/crew-import.sh "$container_path" $flags
        local rc=$?
        if [[ $rc -eq 0 ]]; then
            ok "Crew imported successfully"
            rm -f "$IMPORTS_HOST/$basename"
        else
            err "Crew import failed with exit code $rc"
            warn "Staged file kept at: $IMPORTS_HOST/$basename"
            return $rc
        fi
    else
        warn "Container not running. File staged but not imported."
        log "Start the container, then run:"
        log "  docker exec hemlock_runtime crew-import.sh $container_path"
    fi
}

cmd_crew_export() {
    local crew_name="${1:-}"
    local host_dest="${2:-}"

    [[ -z "$crew_name" ]] && { err "Usage: $0 crew-export <crew_name> [host_dest]"; return 1; }

    _ensure_dirs

    local dest_path="/data/exports/${crew_name}.tar.gz"

    if _is_container_running; then
        log "Exporting crew '$crew_name' inside container..."
        _container_exec /opt/hermes/scripts/crew-export.sh "$crew_name" --dest "$dest_path" --compress
        local rc=$?
        if [[ $rc -ne 0 ]]; then
            err "Crew export failed with exit code $rc"
            return $rc
        fi
        ok "Crew exported to container path: $dest_path"
    else
        err "Container not running."
        return 1
    fi

    if [[ -n "$host_dest" ]]; then
        mkdir -p "$host_dest"
        local src_file="$EXPORTS_HOST/${crew_name}.tar.gz"
        if [[ -f "$src_file" ]]; then
            log "Copying to host: $host_dest"
            cp -a "$src_file" "$host_dest/"
            ok "Copied to: $host_dest/${crew_name}.tar.gz"
        else
            err "Export file not found at: $src_file"
            return 1
        fi
    else
        ok "Export file available at: $EXPORTS_HOST/${crew_name}.tar.gz"
    fi
}

cmd_list_imports() {
    _ensure_dirs
    echo -e "${BOLD}Import staging area:${NC} $IMPORTS_HOST"
    echo ""
    local count=0
    for f in "$IMPORTS_HOST"/*; do
        [[ -e "$f" ]] || continue
        [[ "$(basename "$f")" == ".gitkeep" ]] && continue
        local size
        size=$(du -h "$f" | cut -f1)
        echo "  $(basename "$f")  ($size)"
        count=$((count + 1))
    done
    if [[ $count -eq 0 ]]; then
        echo "  (empty)"
        echo ""
        echo "  Stage a file with: $0 stage <host_path>"
        echo "  Import directly with: $0 import <host_path> [agent_id]"
    fi
    echo ""
}

cmd_list_exports() {
    _ensure_dirs
    echo -e "${BOLD}Export staging area:${NC} $EXPORTS_HOST"
    echo ""
    local count=0
    for f in "$EXPORTS_HOST"/*; do
        [[ -e "$f" ]] || continue
        [[ "$(basename "$f")" == ".gitkeep" ]] && continue
        local size
        size=$(du -h "$f" | cut -f1)
        echo "  $(basename "$f")  ($size)"
        count=$((count + 1))
    done
    if [[ $count -eq 0 ]]; then
        echo "  (empty)"
    else
        echo ""
        echo "  Pull to host with: $0 pull <filename> [destination]"
    fi
    echo ""
}

cmd_clean_imports() {
    _ensure_dirs
    local count=0
    for f in "$IMPORTS_HOST"/*; do
        [[ -e "$f" ]] || continue
        [[ "$(basename "$f")" == ".gitkeep" ]] && continue
        rm -f "$f"
        count=$((count + 1))
    done
    ok "Cleaned $count file(s) from import staging"
}

cmd_clean_exports() {
    _ensure_dirs
    local count=0
    for f in "$EXPORTS_HOST"/*; do
        [[ -e "$f" ]] || continue
        [[ "$(basename "$f")" == ".gitkeep" ]] && continue
        rm -f "$f"
        count=$((count + 1))
    done
    ok "Cleaned $count file(s) from export staging"
}

cmd_stage() {
    local host_path="${1:-}"
    [[ -z "$host_path" ]] && { err "Usage: $0 stage <host_path>"; return 1; }
    [[ ! -e "$host_path" ]] && { err "Source not found: $host_path"; return 1; }

    _ensure_dirs

    local basename
    basename="$(basename "$host_path")"

    if [[ -d "$host_path" ]]; then
        basename="${basename}.tar.gz"
        log "Compressing directory: $host_path"
        tar -czf "$IMPORTS_HOST/$basename" -C "$(dirname "$host_path")" "$(basename "$host_path")"
        ok "Compressed to: $IMPORTS_HOST/$basename"
    else
        cp -a "$host_path" "$IMPORTS_HOST/$basename"
        ok "Copied to: $IMPORTS_HOST/$basename"
    fi

    echo ""
    log "Container path: /data/imports/$basename"
    log "To import inside container menu, use path: /data/imports/$basename"
}

cmd_pull() {
    local filename="${1:-}"
    local host_dest="${2:-.}"

    [[ -z "$filename" ]] && { err "Usage: $0 pull <filename> [host_dest]"; return 1; }

    _ensure_dirs

    local src="$EXPORTS_HOST/$filename"
    [[ ! -f "$src" ]] && { err "File not found in exports: $src"; return 1; }

    mkdir -p "$host_dest"
    cp -a "$src" "$host_dest/"
    ok "Pulled: $host_dest/$(basename "$filename")"
}

cmd_shell() {
    _ensure_running
    docker exec -it "$CONTAINER_NAME" bash
}

cmd_menu() {
    _ensure_running
    docker exec -it "$CONTAINER_NAME" /opt/hermes/scripts/runtime.sh
}

cmd_up() {
    if _is_container_running; then
        ok "Container '$CONTAINER_NAME' is already running."
    else
        log "Starting Hemlock runtime..."
        docker compose -f "$COMPOSE_FILE" up -d 2>&1
        log "Waiting for container to be healthy..."
        local attempts=0
        while ! _is_container_running && [[ $attempts -lt 30 ]]; do
            sleep 2
            attempts=$((attempts + 1))
        done
        if _is_container_running; then
            ok "Container started successfully."
        else
            err "Container failed to start. Check logs:"
            err "  docker compose -f $COMPOSE_FILE logs"
            return 1
        fi
    fi
}

cmd_down() {
    if _is_container_running; then
        log "Stopping Hemlock runtime..."
        docker compose -f "$COMPOSE_FILE" down 2>&1
        ok "Runtime stopped."
    else
        warn "Container '$CONTAINER_NAME' is not running."
    fi
}

cmd_status() {
    echo -e "${BOLD}Hemlock Runtime Status${NC}"
    echo ""
    if _is_container_running; then
        echo -e "  Container: ${GREEN}running${NC}"
        docker ps -f name="$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
    else
        echo -e "  Container: ${RED}not running${NC}"
    fi
    echo ""
    echo -e "  Import staging: $IMPORTS_HOST"
    cmd_list_imports
    echo ""
    echo -e "  Export staging: $EXPORTS_HOST"
    cmd_list_exports
}

_ensure_running() {
    if ! _is_container_running; then
        err "Container '$CONTAINER_NAME' is not running."
        log "Starting container..."
        cmd_up
        if ! _is_container_running; then
            err "Cannot start container."
            err "Start manually: docker compose -f $COMPOSE_FILE up -d"
            exit 1
        fi
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

case "${1:-help}" in
    import)        cmd_import "${2:-}" "${3:-}" ;;
    export)        cmd_export "${2:-}" "${3:-}" ;;
    crew-import)   cmd_crew_import "${2:-}" "${3:-}" ;;
    crew-export)    cmd_crew_export "${2:-}" "${3:-}" ;;
    list-imports|li)  cmd_list_imports ;;
    list-exports|le)  cmd_list_exports ;;
    clean-imports) cmd_clean_imports ;;
    clean-exports) cmd_clean_exports ;;
    stage)         cmd_stage "${2:-}" ;;
    pull)          cmd_pull "${2:-}" "${3:-.}" ;;
    shell|sh)      cmd_shell ;;
    menu|m)        cmd_menu ;;
    up)            cmd_up ;;
    down)          cmd_down ;;
    status|st)     cmd_status ;;
    help|--help|-h) usage ;;
    *)
        echo "Unknown command: $1"
        echo "Run '$0 help' for usage."
        exit 1
        ;;
esac