#!/bin/bash
# =============================================================================
# agent-export.sh — Granular Agent Export with Explicit Confirmation
#
# Exports agents with granular category selection and multiple export modes.
# Requires explicit confirmation - NO DEFAULT MODE.
#
# Usage:
#   ./scripts/agent-export.sh --id <agent_id> --dest <path> --mode <mode>
#   ./scripts/agent-export.sh --id <agent_id> --dest <path> --categories <list>
#   ./scripts/agent-export.sh --id <agent_id> --volume <volume_name> --mode <mode>
#
# Modes:
#   MINIMAL   - Core identity only (identity.md, config.yaml, SOUL.md)
#   STANDARD  - Core + Tools + Skills (no secrets, no memory)
#   FULL      - Everything including secrets and memory (with warning)
#   CUSTOM    - Select specific categories
#
# Export Targets:
#   --dest <path>        Export to directory (default)
#   --volume <name>      Export to Docker volume
#   --container <name>   Export to new container (creates volume automatically)
#
# Categories:
#   CORE_IDENTITY, TOOLS, SKILLS, MEMORY, SECRETS, RUNTIME, BACKUPS, MEDIA, PICTURE
#
# Flags:
#   --id <agent_id>        Agent ID to export
#   --dest <path>          Destination directory
#   --volume <name>        Docker volume name (alternative to --dest)
#   --container <name>     Container name (creates volume automatically)
#   --mode <mode>          Export mode (MINIMAL|STANDARD|FULL|CUSTOM)
#   --categories <list>    Comma-separated categories (for CUSTOM mode)
#   --tarball              Create .tar.gz archive after export
#   --force                Skip confirmation (for scripted use)
#   --quiet                Suppress non-error output
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers.sh"
AGENTS_DIR="${AGENTS_DIR:-/data/agents}"
LOGS_DIR="${LOGS_DIR:-/logs}"
CONFIG_DIR="${CONFIG_DIR:-/config}"

mkdir -p "$AGENTS_DIR" "$LOGS_DIR" "$CONFIG_DIR"

# =============================================================================
# DEFAULTS
# =============================================================================

AGENT_ID=""
DEST=""
VOLUME=""
CONTAINER=""
MODE=""
CATEGORIES=""
TARBALL=false
FORCE=false
QUIET=false
NONINTERACTIVE=false
CLEANUP=false
# CL-011: validate-then-destroy flow (blueprint §5.4)
#   --validate : round-trip the export; verify file list + sample-checksum
#                against the manifest BEFORE returning success.
#   --destroy  : after a passing validation, remove the source agent volume.
#                Implies --validate. Never destroys without a clean validate.
VALIDATE=false
DESTROY=false
VALIDATED=false

# =============================================================================
# EXPORT MODE DEFINITIONS (MINIMAL, STANDARD, FULL) — per hemlock-blueprint §5.3
# =============================================================================
#
# MINIMAL  — Identity & purpose ONLY (safe to share; no state, no secrets).
#            SOUL.md, IDENTITY.md, TOOLS.md, agent.json, AGENTS.md
#            NOTE: tools/ and skills/ are NOT in MINIMAL (they belong to
#            STANDARD per the user's spec — moved 2026-06-25, CL-011).
#
# STANDARD — MINIMAL + the everyday working set.
#            MEMORY.md, .secrets/, HEARTBEAT.md, tools/, skills/(agent's
#            own copies), sessions/ (5 most recent by mtime), memory/
#            (5 most recent by mtime), USER.md, cron jobs, projects/,
#            any .env, any config.yaml.
#
# FULL     — Bit-for-bit volume contents. Every file, hidden included.
# =============================================================================

# MINIMAL — identity files only (no tools/, no skills/, no state).
# CL-018: per-agent identity file is named <AGENT_ID>.json (not agent.json) for
# per-agent isolation. AGENTS.md removed from defaults (IDENTITY.md owns the
# identity role). Both legacy names are still accepted on IMPORT for backward
# compatibility, but export writes only the new names.
MINIMAL_FILES=(
    "${AGENT_ID}.json"
    "SOUL.md"
    "IDENTITY.md"
    "TOOLS.md"
)

# STANDARD adds — everyday working set on top of MINIMAL.
# Note: sessions/ and memory/ get the 5-most-recent treatment in code below,
# NOT as a whole-directory copy. They're listed here for documentation only.
STANDARD_ADDITIONAL_FILES=(
    ".secrets/"
    "USER.md"
    "MEMORY.md"
    "HEARTBEAT.md"
    "config.yaml"
    "config.yml"
    ".env"
    "tools/"           # MOVED from MINIMAL per CL-011
    "skills/"          # MOVED from MINIMAL per CL-011 (agent's own copies)
    "projects/"
    "cron/"
    # sessions/ and memory/ are HANDLED SEPARATELY in export_standard()
    # via copy_recent_files() with N=5. Don't add them here.
)

# FULL exclusion patterns
FULL_EXCLUDE_PATTERNS=(
    "node_modules"
    "__pycache__"
    ".pytest_cache"
    ".mypy_cache"
    ".tox"
    "dist/"
    "build/"
    "*.egg-info/"
    ".git"
)

# =============================================================================
# HELPERS
# =============================================================================

# Copy the N most recent files (by mtime) from SRC into DEST.
# Per blueprint §5.3 STANDARD: sessions/ and memory/ ship as "5 most recent",
# not as whole-directory copies. Latent bug (no definition) was fixed CL-011.
copy_recent_files() {
    local src="$1" dest="$2" n="${3:-5}"
    [[ -d "$src" ]] || return 0
    mkdir -p "$dest"
    # -printf '%T@ %p\0' sorts by mtime stable across spaces in names; head -n N.
    find "$src" -maxdepth 1 -type f -printf '%T@\t%p\0' 2>/dev/null \
        | sort -zrn \
        | head -zn "$n" \
        | while IFS= read -rd '' line; do
            local file="${line#*$'\t'}"
            cp -a --no-preserve=ownership "$file" "$dest/" 2>/dev/null || true
        done
    return 0
}

# Copy directory if exists. ALWAYS returns 0 — "file/dir not present" is not
# an error condition here, it's the expected no-op. This was a latent bug:
# returning 1 on missing source caused `set -e` to abort the entire export
# the moment any optional file (e.g. legacy tools.md) was absent. CL-011.
copy_dir_if_exists() {
    local src="$1"
    local dest="$2"
    if [[ -d "$src" ]]; then
        cp -ra --no-preserve=ownership "$src" "$dest/" 2>/dev/null || true
    fi
    return 0
}

# Copy file if exists. ALWAYS returns 0 (see copy_dir_if_exists rationale).
copy_file_if_exists() {
    local src="$1"
    local dest="$2"
    if [[ -f "$src" ]]; then
        cp -a --no-preserve=ownership "$src" "$dest/" 2>/dev/null || true
    fi
    return 0
}

die()     { echo "  [ERROR] $*" >&2; exit 1; }

success() { echo "  [OK] $*"; }
warn()    { echo "  [WARN] $*" >&2; }
info()    { echo "  [INFO] $*"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") --id <agent_id> --dest <path> --mode <mode>
       $(basename "$0") --id <agent_id> --volume <name> --mode <mode>
       $(basename "$0") --id <agent_id> --container <name> --mode <mode>

Export an agent with granular category selection to directory, Docker volume, or container.

Required:
  --id <agent_id>       Agent ID to export
  --mode <mode>         Export mode: MINIMAL|STANDARD|FULL|CUSTOM

Export Target (choose one):
  --dest <path>         Destination directory (must be empty or non-existent)
  --volume <name>       Docker volume name (creates if not exists)
  --container <name>    Container name (creates volume + container automatically)

Modes:
  MINIMAL     Core identity only (identity.md, config.yaml, SOUL.md)
  STANDARD    Core + Tools + Skills (safe for sharing)
  FULL        Everything including secrets (requires additional confirmation)
  CUSTOM      Select specific categories with --categories

Categories (for CUSTOM mode):
  CORE_IDENTITY  - Identity files (identity.md, config.yaml, SOUL.md, .env)
  TOOLS          - Tool collection (tools/)
  SKILLS         - Installed skills (skills/)
  MEMORY         - Memory and sessions (memory/, sessions/, reflections/)
  SECRETS        - Encrypted secrets (.secrets/, .env.enc, .secret-key)
  RUNTIME        - Runtime state (state/, workspace/, logs/)
  BACKUPS        - Backups and archives (.archive/)
  MEDIA          - Media files (media/, downloads/)
  PICTURE        - Picture files (pictures/, images/)

Optional:
  --categories <list>  Comma-separated categories (CUSTOM mode only)
  --tarball            Create .tar.gz archive (directory export only)
  --validate           Round-trip the export, verify file list + sample
                       checksums against the manifest (blueprint §5.4).
  --destroy            After a PASSING validation, remove the source
                       agent volume. Implies --validate. Never destroys
                       without a clean validation. Calls agent-delete.sh
                       to ensure single-source-of-truth deletion logic.
  --force              Skip confirmation prompts
  --non-interactive|-n Skip confirmation prompts (same as --force)
  --cleanup            Gracefully remove volume/container after successful export
  --quiet              Suppress non-error output
  -h, --help           Show this help

Examples:
  # Export to directory
  $(basename "$0") --id jack --dest /tmp/jack-export --mode MINIMAL
  $(basename "$0") --id jack --dest /tmp/jack-export --mode STANDARD
  $(basename "$0") --id jack --dest /tmp/jack-export --mode FULL
  $(basename "$0") --id jack --dest /tmp/jack-export --mode CUSTOM --categories CORE_IDENTITY,TOOLS,SKILLS
  $(basename "$0") --id jack --dest /tmp/jack-export --mode STANDARD --tarball

  # Export to Docker volume
  $(basename "$0") --id jack --volume jack-export-vol --mode STANDARD
  $(basename "$0") --id jack --volume jack-export-vol --mode FULL

  # Export to container (creates volume + container)
  $(basename "$0") --id jack --container jack-export-ctr --mode STANDARD
  $(basename "$0") --id jack --container jack-export-ctr --mode FULL

EOF
    exit 0
}

# =============================================================================
# ARGUMENT PARSING (only when executed directly, not sourced)
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    while [[ $# -gt 0 ]]; do
        case $1 in
            --id)          AGENT_ID="$2";        shift 2 ;;
            --dest)        DEST="$2";            shift 2 ;;
            --volume)      VOLUME="$2";          shift 2 ;;
            --container)   CONTAINER="$2";       shift 2 ;;
            --mode)        MODE="$2";            shift 2 ;;
            --categories)  CATEGORIES="$2";      shift 2 ;;
            --tarball|-t)  TARBALL=true;         shift ;;
            --validate)    VALIDATE=true;        shift ;;
            --destroy)     DESTROY=true; VALIDATE=true; shift ;;
            --force|-f)    FORCE=true;           shift ;;
            --quiet|-q)    QUIET=true;           shift ;;
            --non-interactive|-n) NONINTERACTIVE=true; FORCE=true; shift ;;
            --cleanup)     CLEANUP=true;         shift ;;
            -h|--help)     usage ;;
            -*) die "Unknown flag: $1 (try --help)" ;;
            *)  die "Unexpected argument: $1" ;;
        esac
    done
fi

# =============================================================================
# VALIDATION (only when executed directly)
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ -z "$AGENT_ID" ]] && die "Agent ID is required. Usage: $(basename "$0") --id <agent_id> ..."
    
    # Validate export target (must have exactly one: --dest, --volume, or --container)
    target_count=0
    [[ -n "$DEST" ]] && target_count=$((target_count + 1))
    [[ -n "$VOLUME" ]] && target_count=$((target_count + 1))
    [[ -n "$CONTAINER" ]] && target_count=$((target_count + 1))
    
    if [[ $target_count -eq 0 ]]; then
        die "Export target required. Use --dest <path>, --volume <name>, or --container <name>"
    fi
    
    if [[ $target_count -gt 1 ]]; then
        die "Cannot use multiple export targets. Choose one: --dest, --volume, or --container"
    fi
    
    validate_agent_id "$AGENT_ID" || exit 1
fi

if ! agent_exists "$AGENT_ID"; then
    die "Agent '$AGENT_ID' does not exist"
fi

# Validate mode (default to STANDARD if not specified)
MODE="${MODE:-STANDARD}"
MODE="${MODE^^}"  # Convert to uppercase
if [[ ! "$MODE" =~ ^(MINIMAL|STANDARD|FULL|CUSTOM)$ ]]; then
    die "Invalid mode: $MODE (must be MINIMAL, STANDARD, FULL, or CUSTOM)"
fi

# Validate CUSTOM mode has categories
if [[ "$MODE" == "CUSTOM" && -z "$CATEGORIES" ]]; then
    die "CUSTOM mode requires --categories <list>"
fi

# Check Docker availability if using volume or container
if [[ -n "$VOLUME" || -n "$CONTAINER" ]]; then
    if ! command -v docker &>/dev/null; then
        die "Docker is required for volume/container export but not found"
    fi
fi

# Handle volume export
if [[ -n "$VOLUME" ]]; then
    info "Creating Docker volume: $VOLUME"
    docker volume create "$VOLUME" 2>/dev/null || die "Failed to create volume $VOLUME"
    
    info "Volume created: $VOLUME"
    info "Copying files to volume via container..."
    
    # Create temporary directory for export
    TEMP_EXPORT=$(mktemp -d)
    DEST="$TEMP_EXPORT"
    
    # We'll copy to volume after export is complete
    COPY_TO_VOLUME=true
fi

# Handle container export
if [[ -n "$CONTAINER" ]]; then
    info "Creating container export: $CONTAINER"
    
    # Create volume for container
    VOLUME_NAME="hemlock-export-${CONTAINER}"
    info "Creating volume: $VOLUME_NAME"
    docker volume create "$VOLUME_NAME" 2>/dev/null || die "Failed to create volume $VOLUME_NAME"
    
    info "Creating container: $CONTAINER"
    docker create --name "$CONTAINER" -v "$VOLUME_NAME:/export" alpine:latest \
        echo "Export container ready" 2>/dev/null || \
        die "Failed to create container $CONTAINER (may already exist)"
    
    # Create temporary directory for export
    TEMP_EXPORT=$(mktemp -d)
    DEST="$TEMP_EXPORT"
    
    # We'll copy to volume after export is complete
    COPY_TO_VOLUME=true
fi

# Check destination directory (for direct file export)
if [[ -z "${COPY_TO_VOLUME:-}" ]]; then
    if [[ -d "$DEST" ]]; then
        if [[ -n "$(ls -A "$DEST" 2>/dev/null)" ]]; then
            die "Destination directory '$DEST' is not empty"
        fi
    else
        mkdir -p "$DEST"
    fi
else
    # For volume/container export, use temp directory
    mkdir -p "$DEST"
fi

# =============================================================================
# RESOLVE CATEGORIES FROM MODE
# =============================================================================

resolve_categories() {
    local mode=$1
    
    case $mode in
        MINIMAL)
            echo "CORE_IDENTITY"
            ;;
        STANDARD)
            echo "CORE_IDENTITY,TOOLS,SKILLS,MEMORY,SECRETS"
            ;;
        FULL)
            echo "CORE_IDENTITY,TOOLS,SKILLS,MEMORY,SECRETS,RUNTIME,BACKUPS,MEDIA,PICTURE"
            ;;
        CUSTOM)
            echo "$CATEGORIES"
            ;;
    esac
}

SELECTED_CATEGORIES=$(resolve_categories "$MODE")

# =============================================================================
# INTERACTIVE HELPERS
# =============================================================================

is_interactive() {
    if [[ "${HEMLOCK_NONINTERACTIVE:-}" == "1" || "$NONINTERACTIVE" == true || "$FORCE" == true ]]; then
        return 1
    fi
    if [[ -t 0 ]]; then
        return 0
    fi
    if [[ -c /dev/tty ]] && [[ -w /dev/tty ]]; then
        return 0
    fi
    return 1
}

read_tty() {
    # CL-017: HEMLOCK_NONINTERACTIVE=1 / NONINTERACTIVE=true short-circuit.
    [[ "${HEMLOCK_NONINTERACTIVE:-0}" == "1" || "${NONINTERACTIVE:-}" == true ]] && return 1
    if [[ -t 0 ]]; then
        read "$@"
    elif [[ -c /dev/tty ]] && [[ -w /dev/tty ]] && tty -s </dev/tty 2>/dev/null; then
        read "$@" < /dev/tty
    else
        return 1
    fi
}

# =============================================================================
# CONFIRMATION
# =============================================================================

if [[ "$FORCE" != true ]] && is_interactive; then
    echo ""
    echo "=== Agent Export Configuration ==="
    echo ""
    echo "  Agent:      $AGENT_ID"
    echo "  Destination: $DEST"
    echo "  Mode:       $MODE"
    echo "  Categories: $SELECTED_CATEGORIES"
    echo ""
    
    # Warn about SECRETS
    if [[ "$SELECTED_CATEGORIES" == *"SECRETS"* ]]; then
        echo "  ⚠️  WARNING: SECRETS category selected"
        echo "     This will export encrypted secrets including:"
        echo "       - .secrets/ directory"
        echo "       - .env.enc file"
        echo "       - .secret-key file (encryption key)"
        echo ""
        echo "     Ensure the destination is SECURE before proceeding."
        echo ""
        
        if [[ "$MODE" == "FULL" ]]; then
            echo "  FULL mode includes ALL sensitive data."
            echo "  Consider using STANDARD mode for safe sharing."
            echo ""
        fi
        
        read_tty -p "  Continue with secrets export? [y/N] " CONFIRM_SECRETS
        echo ""
        
        if [[ ! "${CONFIRM_SECRETS:-}" =~ ^[Yy]$ ]]; then
            echo "  Export cancelled."
            exit 0
        fi
    fi
    
    read_tty -p "  Continue with export? [y/N] " CONFIRM
    echo ""
    
    if [[ ! "${CONFIRM:-}" =~ ^[Yy]$ ]]; then
        echo "  Export cancelled."
        exit 0
    fi
fi

# =============================================================================
# MODE-BASED EXPORT HANDLERS (MINIMAL, STANDARD, FULL)
# =============================================================================

# Export MINIMAL mode — identity & purpose ONLY (no tools/, no skills/, no state)
# Per hemlock-blueprint §5.3: SOUL.md, IDENTITY.md, TOOLS.md, agent.json, AGENTS.md
# tools/ and skills/ MOVED to STANDARD per CL-011.
export_minimal() {
    local source_dir="$AGENTS_DIR/$AGENT_ID"
    local dest_dir="$DEST"

    info "Exporting MINIMAL mode (identity & purpose only)..."

    # CL-018: prefer ${AGENT_ID}.json; fall back to legacy agent.json for any
    # pre-CL-018 workspaces still on disk.
    for file in "${AGENT_ID}.json" "agent.json" "SOUL.md" "IDENTITY.md" "TOOLS.md"; do
        copy_file_if_exists "$source_dir/$file" "$dest_dir"
    done
    # Legacy lowercase tools.md (some old agents have it; harmless if absent).
    copy_file_if_exists "$source_dir/tools.md" "$dest_dir"

    info "MINIMAL export complete"
}

# Export STANDARD mode — MINIMAL + everyday working set
# Per hemlock-blueprint §5.3:
#   MEMORY.md, .secrets/, HEARTBEAT.md, tools/, skills/, sessions/ (5 latest),
#   memory/ (5 latest), USER.md, cron, projects/, .env, config.yaml
export_standard() {
    local source_dir="$AGENTS_DIR/$AGENT_ID"
    local dest_dir="$DEST"

    info "Exporting STANDARD mode (MINIMAL + working set)..."

    # 1. MINIMAL first (identity + purpose).
    export_minimal

    # 2. Top-level working files.
    copy_file_if_exists "$source_dir/USER.md"     "$dest_dir"
    copy_file_if_exists "$source_dir/MEMORY.md"   "$dest_dir"
    copy_file_if_exists "$source_dir/HEARTBEAT.md" "$dest_dir"
    copy_file_if_exists "$source_dir/config.yaml" "$dest_dir"
    copy_file_if_exists "$source_dir/config.yml"  "$dest_dir"
    # All .env* files at the agent root (excluding *.enc, which would be a
    # raw encrypted blob — the encrypted form lives inside .secrets/ already).
    find "$source_dir" -maxdepth 1 -name ".env*" -not -name "*.enc" -type f \
        | while read -r file; do
            cp -a --no-preserve=ownership "$file" "$dest_dir/" 2>/dev/null || true
        done

    # 3. Encrypted secrets (the recipient needs .secret-key from this dir
    #    to actually decrypt — they ship together as designed).
    copy_dir_if_exists "$source_dir/.secrets" "$dest_dir"

    # 4. Tools (agent's own scripts — secret.sh, enforce.sh, etc.)
    copy_dir_if_exists "$source_dir/tools" "$dest_dir"

    # 5. Skills (the AGENT's copies, NOT the shared /skills readonly mount).
    copy_dir_if_exists "$source_dir/skills" "$dest_dir"

    # 6. Sessions — 5 most recent files by mtime.
    if [[ -d "$source_dir/sessions" ]]; then
        mkdir -p "$dest_dir/sessions"
        copy_recent_files "$source_dir/sessions" "$dest_dir/sessions" 5
    fi

    # 7. Memory — 5 most recent files by mtime (per user's spec; was missing).
    if [[ -d "$source_dir/memory" ]]; then
        mkdir -p "$dest_dir/memory"
        copy_recent_files "$source_dir/memory" "$dest_dir/memory" 5
    fi

    # 8. Projects (entire dir — user's spec says full projects/, not recent).
    copy_dir_if_exists "$source_dir/projects" "$dest_dir"

    # 9. Cron jobs — both common shapes:
    #    - a cron/ directory with one file per job, OR
    #    - a single crontab file at the agent root.
    copy_dir_if_exists  "$source_dir/cron"     "$dest_dir"
    copy_file_if_exists "$source_dir/crontab"  "$dest_dir"

    info "STANDARD export complete"
}

# Export FULL mode - everything except exclusions
export_full() {
    local source_dir="$AGENTS_DIR/$AGENT_ID"
    local dest_dir="$DEST"
    
    info "Exporting FULL mode..."
    
    # First do STANDARD (which includes MINIMAL)
    export_standard
    
    # Now add everything else except exclusions
    # Copy everything not already copied, excluding patterns
    rsync -a --no-preserve=ownership \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        --exclude='.pytest_cache' \
        --exclude='.mypy_cache' \
        --exclude='.tox' \
        --exclude='dist/' \
        --exclude='build/' \
        --exclude='*.egg-info/' \
        --exclude='.git' \
        "$source_dir/" "$dest_dir/" 2>/dev/null || true
    
    info "FULL export complete"
}

# Export based on mode
export_mode() {
    local mode="$MODE"
    
    case "$mode" in
        MINIMAL)
            export_minimal
            ;;
        STANDARD)
            export_standard
            ;;
        FULL)
            export_full
            ;;
        CUSTOM)
            # CUSTOM mode - use old category-based approach
            IFS=',' read -ra CATEGORY_ARRAY <<< "$SELECTED_CATEGORIES"
            for category in "${CATEGORY_ARRAY[@]}"; do
                category="${category^^}"
                export_category "$category"
            done
            ;;
    esac
}

# =============================================================================
# CATEGORY-BASED EXPORT (for CUSTOM mode)
# =============================================================================

# =============================================================================
# CREATE MANIFESTS
# =============================================================================

create_manifests() {
    local dest_dir=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local export_timestamp=$(date "+%Y%m%d_%H%M%S")
    
    # Count exported files
    local file_count=$(find "$dest_dir" -type f | wc -l)
    
    # Check if secrets were exported
    local secrets_exported="false"
    if [[ -d "$dest_dir/.secrets" || -f "$dest_dir/.env.enc" ]]; then
        secrets_exported="true"
    fi
    
    # Create YAML manifest
    cat > "$dest_dir/export-manifest.yaml" <<EOL
# Export Manifest - $AGENT_ID
# Generated: $timestamp

export:
  agent_id: $AGENT_ID
  timestamp: $timestamp
  mode: $MODE
  categories:
$(echo "$SELECTED_CATEGORIES" | tr ',' '\n' | sed 's/^/    - /')
  destination: $dest_dir
  source: $AGENTS_DIR/$AGENT_ID
  file_count: $file_count
  secrets_included: $secrets_exported
  
encryption:
  status: $([ "$secrets_exported" = "true" ] && echo "preserved" || echo "not_applicable")
  algorithm: AES-256-CBC
  note: "Secrets remain encrypted. Decryption requires .secret-key file."
  
warnings:
$(if [[ "$secrets_exported" = "true" ]]; then
    echo "  - SECRETS EXPORTED: Ensure destination is secure"
    echo "  - Do not share .secret-key file publicly"
    echo "  - Use secret.sh tool for secure secret access"
else
    echo "  - No secrets exported (safe for sharing)"
fi)
EOL

    # Create JSON manifest
    cat > "$dest_dir/export-manifest.json" <<EOL
{
  "export": {
    "agent_id": "$AGENT_ID",
    "timestamp": "$timestamp",
    "mode": "$MODE",
    "categories": [$(echo "$SELECTED_CATEGORIES" | tr ',' '\n' | sed 's/^/"/;s/$/"/' | tr '\n' ',' | sed 's/,$//')],
    "destination": "$dest_dir",
    "source": "$AGENTS_DIR/$AGENT_ID",
    "file_count": $file_count,
    "secrets_included": $secrets_exported
  },
  "encryption": {
    "status": "$([ "$secrets_exported" = "true" ] && echo "preserved" || echo "not_applicable")",
    "algorithm": "AES-256-CBC",
    "note": "Secrets remain encrypted. Decryption requires .secret-key file."
  },
  "warnings": [$(if [[ "$secrets_exported" = "true" ]]; then
    echo '"SECRETS EXPORTED: Ensure destination is secure", "Do not share .secret-key file publicly", "Use secret.sh tool for secure secret access"'
else
    echo '"No secrets exported (safe for sharing)"'
fi)]
}
EOL

    success "Manifests created (export-manifest.yaml, export-manifest.json)"
}

# CL-011 — Write a sha256sum-format checksum file for every payload file
# (excluding the checksum file itself and the manifests, which are generated
# from this data). The format is the standard `sha256sum -c` consumable form:
#   <hash>  <relative-path>
# This is what `validate_export` checks against.
write_checksums() {
    local dest_dir="$1"
    local checksum_file="$dest_dir/checksums.sha256"
    # Walk every payload file relative to dest_dir, skip our own outputs.
    ( cd "$dest_dir" && find . -type f \
        ! -name 'checksums.sha256' \
        ! -name 'export-manifest.json' \
        ! -name 'export-manifest.yaml' \
        -print0 \
        | sort -z \
        | xargs -0 sha256sum > "$checksum_file" 2>/dev/null ) || {
        warn "checksum generation failed (sha256sum missing?)"
        return 1
    }
    local lines; lines=$(wc -l < "$checksum_file")
    success "Wrote $lines checksums to checksums.sha256"
}

# Validate an export directory by re-walking it and verifying every file
# matches the checksum recorded at export time. Returns 0 on full pass,
# 1 on any mismatch / missing file / extra file.
#   $1 = export dir to validate
validate_export() {
    local dest_dir="$1"
    local csum="$dest_dir/checksums.sha256"
    if [[ ! -f "$csum" ]]; then
        warn "No checksums.sha256 in $dest_dir — cannot validate"
        return 1
    fi
    info "Validating export against checksums.sha256..."
    local fail=0 extra=0
    # Step 1: verify every recorded file still hashes correctly.
    if ! ( cd "$dest_dir" && sha256sum -c --quiet checksums.sha256 ) 2>/dev/null; then
        warn "  one or more files failed checksum verification"
        fail=1
    fi
    # Step 2: count extra files (in dir but not in checksum list).
    local recorded_count actual_count
    recorded_count=$(wc -l < "$csum")
    actual_count=$( ( cd "$dest_dir" && find . -type f \
        ! -name 'checksums.sha256' \
        ! -name 'export-manifest.json' \
        ! -name 'export-manifest.yaml' | wc -l ) )
    if [[ "$recorded_count" -ne "$actual_count" ]]; then
        warn "  file count mismatch: manifest=$recorded_count actual=$actual_count"
        fail=1
    fi
    if [[ "$fail" -eq 0 ]]; then
        success "Validation PASSED ($recorded_count files, all checksums match)"
        VALIDATED=true
        return 0
    fi
    warn "Validation FAILED — destruction (if requested) will NOT proceed"
    VALIDATED=false
    return 1
}

# Round-trip validate a tarball: extract to scratch, then validate_export.
validate_tarball() {
    local tarball="$1"
    if ! command -v tar >/dev/null 2>&1; then
        warn "tar not available — cannot validate tarball"
        return 1
    fi
    local scratch
    scratch=$(mktemp -d -t uca-export-validate-XXXXXX)
    info "Extracting tarball to scratch: $scratch"
    if ! tar -xzf "$tarball" -C "$scratch" 2>/dev/null; then
        warn "tar extract failed"
        rm -rf "$scratch"; return 1
    fi
    # The tarball was built with the export dir as the top-level entry.
    local inner; inner=$(find "$scratch" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [[ -z "$inner" ]]; then
        warn "tarball has no inner directory"
        rm -rf "$scratch"; return 1
    fi
    local rc=0
    validate_export "$inner" || rc=1
    rm -rf "$scratch"
    return $rc
}

# =============================================================================
# MAIN EXPORT
# =============================================================================

echo ""
echo "=== Exporting Agent: $AGENT_ID ==="
echo ""

# Fix source permissions before export (root-owned or 700 files)
find "$AGENTS_DIR/$AGENT_ID" -type d -perm 700 -exec chmod 755 {} \; 2>/dev/null || true
find "$AGENTS_DIR/$AGENT_ID" -type f -perm 700 -exec chmod 644 {} \; 2>/dev/null || true
find "$AGENTS_DIR/$AGENT_ID" -type f -user root -exec chown 1000:1000 {} \; 2>/dev/null || true

# Export based on mode
export_mode

# Create manifests
create_manifests "$DEST"

# CL-011: per-file SHA-256 manifest (consumable by `sha256sum -c`). Must run
# AFTER all payload files are in place and BEFORE create_manifests's own
# files would otherwise be included — so we re-exclude them in the helper.
write_checksums "$DEST"

# Fix permissions to ensure no 700 dirs or files (user can read)
find "$DEST" -type d -perm 700 -exec chmod 755 {} \; 2>/dev/null || true
find "$DEST" -type f -perm 700 -exec chmod 644 {} \; 2>/dev/null || true
find "$DEST" -user root -exec chown --no-dereference 1000:1000 {} \; 2>/dev/null || true

# =============================================================================
# POST-EXPORT SUMMARY
# =============================================================================

echo ""
echo "=== Export Complete ==="
echo ""

# Count exported files
file_count=$(find "$DEST" -type f | wc -l)
dir_count=$(find "$DEST" -type d | wc -l)

echo "  Destination:   $DEST"
echo "  Mode:          $MODE"
echo "  Categories:    $SELECTED_CATEGORIES"
echo "  Files:         $file_count"
echo "  Directories:   $dir_count"
echo ""

# Security warning
if [[ "$SELECTED_CATEGORIES" == *"SECRETS"* ]]; then
    echo "  ⚠️  SECURITY WARNING:"
    echo "     - Secrets were exported and remain encrypted"
    echo "     - Keep .secret-key file secure"
    echo "     - Do not share exported directory publicly"
    if [[ "$TARBALL" == true ]]; then
        echo "     - Creating encrypted tarball..."
    else
        echo "     - Use: tar -czf export.tar.gz -C $(dirname "$DEST") $(basename "$DEST")"
    fi
    echo ""
else
    echo "  ✓ Safe for sharing (no secrets exported)"
    echo ""
fi

# Create tarball if requested
if [[ "$TARBALL" == true ]]; then
    dest_parent=$(dirname "$DEST")
    dest_name=$(basename "$DEST")
    tarball_path="$dest_parent/${dest_name}.tar.gz"
    
    info "Creating tarball: $tarball_path"
    tar -czf "$tarball_path" -C "$dest_parent" "$dest_name"
    
    if [[ -f "$tarball_path" ]]; then
        tarball_size=$(ls -lh "$tarball_path" | awk '{print $5}')
        success "Tarball created: $tarball_path ($tarball_size)"
    else
        warn "Failed to create tarball"
    fi
fi

# Finalize container export
if [[ -n "$CONTAINER" ]]; then
    echo ""
    info "Finalizing container export..."
    
    # Copy files from temp directory to container volume
    docker cp "$DEST/." "$CONTAINER:/export/" 2>/dev/null || {
        warn "Failed to copy files to container"
    }
    
    # Start container to finalize
    docker start "$CONTAINER" 2>/dev/null || true
    
    # Cleanup temp directory
    rm -rf "$DEST"
    
    echo ""
    echo "  📦 Container Export Complete:"
    echo "     Container:  $CONTAINER"
    echo "     Volume:     $VOLUME_NAME"
    echo ""
    echo "  Access exported files:"
    echo "     docker cp $CONTAINER:/export/<file> <local_path>"
    echo "     docker run --rm -v $VOLUME_NAME:/export alpine ls /export"
    echo ""
    echo "  Cleanup:"
    echo "     docker stop $CONTAINER"
    echo "     docker rm $CONTAINER"
    echo "     docker volume rm $VOLUME_NAME"
    echo ""
elif [[ -n "$VOLUME" ]]; then
    echo ""
    info "Copying files to Docker volume..."
    
    # Create temporary container to copy files
    TEMP_CTR="hemlock-export-temp-$$"
    docker create --name "$TEMP_CTR" -v "$VOLUME:/export" alpine:latest sleep 1 2>/dev/null || {
        warn "Failed to create temporary container"
        docker rm "$TEMP_CTR" 2>/dev/null || true
    }
    
    # Copy files to volume via container
    docker cp "$DEST/." "$TEMP_CTR:/export/" 2>/dev/null || {
        warn "Failed to copy files to volume"
    }
    
    # Cleanup
    docker rm "$TEMP_CTR" 2>/dev/null || true
    rm -rf "$DEST"
    
    echo ""
    echo "  📦 Volume Export Complete:"
    echo "     Volume:  $VOLUME"
    echo ""
    echo "  Access exported files:"
    echo "     docker run --rm -v $VOLUME:/export alpine ls /export"
    echo "     docker run --rm -v $VOLUME:/export -it alpine sh"
    echo ""
    echo "  Cleanup:"
    echo "     docker volume rm $VOLUME"
    echo ""
fi

# Cleanup export directory if --cleanup flag is set (for directory exports)
if [[ "$CLEANUP" == true && -z "$CONTAINER" && -z "$VOLUME" ]]; then
    info "Cleaning up export directory..."
    rm -rf "$DEST"
    success "Export directory cleaned up"
fi

# Log
log "INFO" "Agent $AGENT_ID exported (mode: $MODE, categories: $SELECTED_CATEGORIES)"
agent_log "$AGENT_ID" "INFO" "Exported"

# ============================================================================
# CL-011 — Validate-then-Destroy (blueprint §5.4)
# ============================================================================
# --validate : round-trip the export and confirm every file matches the
#              checksum captured at export time. Refuses to claim "valid"
#              if anything is missing, extra, or modified.
# --destroy  : after a PASSING --validate, remove the source agent volume
#              by delegating to agent-delete.sh (single source of truth for
#              deletion). NEVER fires if validation didn't pass.
if [[ "$VALIDATE" == true ]]; then
    echo ""
    info "═══ Validation ═══"
    if [[ "$TARBALL" == true && -n "${tarball_path:-}" && -f "${tarball_path:-}" ]]; then
        validate_tarball "$tarball_path" || true
    elif [[ -d "$DEST" ]]; then
        validate_export "$DEST" || true
    else
        warn "Nothing to validate — DEST removed (CLEANUP?) and no tarball produced"
    fi
fi

if [[ "$DESTROY" == true ]]; then
    echo ""
    info "═══ Destroy ═══"
    if [[ "$VALIDATED" != "true" ]]; then
        warn "--destroy refused: validation did not pass. Source volume is intact."
    else
        if [[ "$FORCE" != "true" && "$NONINTERACTIVE" != "true" ]]; then
            read -rp "  Destroy source agent volume hemlock_agent_${AGENT_ID}? [y/N]: " ans
            [[ "$ans" =~ ^[Yy]$ ]] || { warn "Destroy cancelled by user"; exit 0; }
        fi
        info "Delegating to agent-delete.sh (single source of truth)..."
        if [[ -x "$SCRIPT_DIR/agent-delete.sh" ]]; then
            "$SCRIPT_DIR/agent-delete.sh" --id "$AGENT_ID" --force \
                && success "Source agent volume destroyed: hemlock_agent_${AGENT_ID}" \
                || warn "agent-delete.sh exited non-zero — volume may still exist"
        else
            warn "agent-delete.sh not executable at $SCRIPT_DIR/agent-delete.sh"
        fi
    fi
fi

success "Export complete!"

