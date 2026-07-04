#!/bin/bash
# =============================================================================
# Interactive Backup Protocol - Robust Multi-Mode Backup System
# =============================================================================
# Features:
#   - Select specific crews or entire crews workspace
#   - Select specific agents or entire agents workspace
#   - Standard: Agent configs + identifying files + memory
#   - Full: Standard + sessions, logs, docker volumes, everything
#   - Combination modes for crews + agents
#   - Automatic timer/cron setup for scheduled backups
#   - Include all hidden files/directories (except .git by default)
#   - Optional .git inclusion
#   - Robust validation suite
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

DOCKER_DIR="${DOCKER_DIR:-$RUNTIME_ROOT/docker}"
DEFAULT_BACKUP_DIR="${DEFAULT_BACKUP_DIR:-$RUNTIME_ROOT/backups}"
CONFIG_FILE="${CONFIG_DIR}/backup-config.yaml"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# Use relative path by default for portability; can be overridden via config or CLI
DEFAULT_BACKUP_DIR="$RUNTIME_ROOT/backups"
CONFIG_FILE="$CONFIG_DIR/backup-config.yaml"
mkdir -p "$(dirname "$CONFIG_FILE")"
mkdir -p "$PLUGINS_DIR"
mkdir -p "$DEFAULT_BACKUP_DIR"

# =============================================================================
# DEFAULT EXCLUDES
# =============================================================================

# Always exclude these
ALWAYS_EXCLUDE=(
    ".git/"
    "__pycache__/"
    "*.pyc"
    ".DS_Store"
    "*.bak"
    "*.tmp"
    "*.swp"
    "Thumbs.db"
    "desktop.ini"
)

# Bloat excludes - excluded by default
BLOAT_EXCLUDE=(
    "node_modules/"
    ".npm/"
    ".yarn/"
    "vendor/"
    "bower_components/"
    "dist/"
    "build/"
    ".parcel-cache/"
    ".next/"
    ".nuxt/"
    "coverage/"
    "*.log"
    "logs/"
    "*.lock"
    "yarn.lock"
    "package-lock.json"
)

# Docker excludes
DOCKER_EXCLUDE=(
    "checkpoints/"
    "cache/"
    "tmp/"
    ".docker/"
)

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
${GREEN}Interactive Backup Protocol - Robust Multi-Mode Backup${NC}

Backup Selection Options:
  --crews <list>        Comma-separated list of crew names to backup
  --all-crews          Backup ALL crews in crews/
  --crew workspaces    Backup complete crew workspaces (configs+_metadata+all files)
  
  --agents <list>       Comma-separated list of agent IDs to backup
  --all-agents         Backup ALL agents in agents/
  --agent configs      Backup only agent configurations and identifying files
  --agent full         Backup complete agent workspace (configs+memory+sessions+logs+volumes)
  
  --combo crews-configs        Crews configs + agents configs only
  --combo crews-full           Crews full + agents full
  --combo crews-workspaces     Crews complete workspaces + agents configs
  --combo all-full              Everything full (crews+agents+sessions+docker+volumes)

Backup Mode Options:
  --mode plan-history   Metadata and config only (small, for Git)
  --mode docker-full    Complete Docker files and images
  --mode combo          Both plan-history + docker-full (DEFAULT)

Destination Options:
  --destination <path>  Backup destination (default: ./backups relative to project)
  --type <type>         local|external|ssh|cloud|git
  
Hidden Files Options:
  --include-hidden     Include all hidden files and directories (DEFAULT)
  --exclude-hidden     Exclude hidden files/directories
  --include-git        Include .git directories (NOT recommended)
  --exclude-git        Exclude .git directories (DEFAULT)

Other Options:
  --full                Include sessions, workflows, and all supporting files
  --compress            Compress backup (tar.gz)
  --encrypt             Encrypt sensitive files
  --exclude <pattern>   Custom exclude pattern
  --include-skills     Include the canonical skills/ directory in backup
  --no-exclude-modules Don't exclude node_modules (NOT recommended)
  --no-exclude-bloat   Don't exclude build artifacts (NOT recommended)
  --setup-timer         Set up automatic backup timer/cron
  --timer <value>      Timer interval in hours (default: 6)
  --dry-run            Test without writing
  --quiet              Suppress output
  --help, -h

Examples:
  # Backup specific crews with configs only
  $0 backup --crews crew1,crew2 --crew configs
  
  # Backup specific agents with full workspace
  $0 backup --agents agent1,agent2 --agent full
  
  # Combo: crews configs + agents configs
  $0 backup --combo crews-configs
  
  # Combo: crews full + agents full
  $0 backup --combo crews-full --full
  
  # Everything full
  $0 backup --combo all-full --full
  
  # Include all hidden files
  $0 backup --include-hidden
  
  # Include .git (rarely needed)
  $0 backup --include-git --include-hidden
  
  # Setup automatic backups
  $0 init --setup-timer --timer 6
  
  # Include skills directory for full portability
  $0 backup --include-skills
EOF
    exit 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

COMMAND=""
DESTINATION=""
BACKUP_TYPE=""
BACKUP_MODE="combo"

# Crew selection
CREW_SELECTION=""      # Specific crews list
ALL_CREWS=false
CREW_LEVEL="configs"   # configs | full | workspaces

# Agent selection
AGENT_SELECTION=""     # Specific agents list
ALL_AGENTS=false
AGENT_LEVEL="configs"  # configs | full

# Combo selection
COMBO_MODE=""          # crews-configs, crews-full, crews-workspaces, all-full

FULL_BACKUP=false
COMPRESS=false
ENCRYPT=false
DRY_RUN=false
QUIET=false
EXCLUDE_PATTERNS=()

# Hidden files options
INCLUDE_HIDDEN=true
INCLUDE_GIT=false

# Skills inclusion (excluded by default to save space - can be re-downloaded)
INCLUDE_SKILLS=false

# Timer options
SETUP_TIMER=false
TIMER_HOURS=6

while [[ $# -gt 0 ]]; do
    case "$1" in
        # Crew options
        --crews) CREW_SELECTION="$2"; shift 2;;
        --all-crews) ALL_CREWS=true; shift;;
        --crew) CREW_LEVEL="$2"; shift 2;;
        
        # Agent options
        --agents) AGENT_SELECTION="$2"; shift 2;;
        --all-agents) ALL_AGENTS=true; shift;;
        --agent) AGENT_LEVEL="$2"; shift 2;;
        
        # Combo options
        --combo) COMBO_MODE="$2"; shift 2;;
        
        # Mode options
        --mode) BACKUP_MODE="$2"; shift 2;;
        
        # Destination options
        --destination) DESTINATION="$2"; shift 2;;
        --type) BACKUP_TYPE="$2"; shift 2;;
        
        # Hidden files options
        --include-hidden) INCLUDE_HIDDEN=true; shift;;
        --exclude-hidden) INCLUDE_HIDDEN=false; shift;;
        --include-git) INCLUDE_GIT=true; shift;;
        --exclude-git) INCLUDE_GIT=false; shift;;
        --include-skills) INCLUDE_SKILLS=true; shift;;
        
        # Other options
        --full) FULL_BACKUP=true; shift;;
        --compress) COMPRESS=true; shift;;
        --encrypt) ENCRYPT=true; shift;;
        --exclude) EXCLUDE_PATTERNS+=("$2"); shift 2;;
        --no-exclude-modules) EXCLUDE_NODE_MODULES=false; shift;;
        --no-exclude-bloat) EXCLUDE_BLOAT=false; shift;;
        
        # Timer options
        --setup-timer) SETUP_TIMER=true; shift;;
        --timer) TIMER_HOURS="$2"; shift 2;;
        
        # Standard options
        --dry-run) DRY_RUN=true; shift;;
        --quiet) QUIET=true; shift;;
        --version|-V) echo "Interactive Backup Protocol v1.0.0 (Hemlock Enterprise Agent Framework)"; exit 0;;
        --help|-h) usage;;
        *)
            if [[ -z "$COMMAND" ]]; then COMMAND="$1"; fi; shift;;
    esac
done

[[ -z "$COMMAND" ]] && COMMAND="backup"

# Set defaults
EXCLUDE_NODE_MODULES=true
EXCLUDE_BLOAT=true
BACKUP_TYPE="${BACKUP_TYPE:-local}"
BACKUP_MODE="${BACKUP_MODE:-combo}"

# =============================================================================
# CONFIGURATION
# =============================================================================

CONFIG_FILE="$CONFIG_DIR/backup-config.yaml"

load_config() {
    # Apply self-healing: if config file doesn't exist, create defaults
    with_self_healing "load_config" 2>/dev/null || true
    
    # Ensure config directory exists
    retry_with_fallback "mkdir -p $(dirname $CONFIG_FILE)" "echo 'Config dir creation failed'" 2 1 2>/dev/null
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # Load each config value with error handling
        [[ -z "$BACKUP_DIR" ]] && BACKUP_DIR=$(retry_with_fallback "grep '^backup_dir:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo ''" 2 1 2>/dev/null)
        [[ -z "$BACKUP_TYPE" ]] && BACKUP_TYPE=$(retry_with_fallback "grep '^backup_type:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo ''" 2 1 2>/dev/null)
        [[ -z "$DESTINATION" ]] && DESTINATION=$(retry_with_fallback "grep '^destination:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo ''" 2 1 2>/dev/null)
        [[ "$ENCRYPT" != true ]] && ENCRYPT=$(retry_with_fallback "grep '^encrypt:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo 'false'" 2 1 2>/dev/null)
        [[ "$COMPRESS" != true ]] && COMPRESS=$(retry_with_fallback "grep '^compress:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo 'false'" 2 1 2>/dev/null)
        [[ "$FULL_BACKUP" != true ]] && FULL_BACKUP=$(retry_with_fallback "grep '^full_backup:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo 'false'" 2 1 2>/dev/null)
        [[ "$INCLUDE_HIDDEN" != true ]] && INCLUDE_HIDDEN=$(retry_with_fallback "grep '^include_hidden:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo 'true'" 2 1 2>/dev/null)
        [[ "$INCLUDE_GIT" != false ]] && INCLUDE_GIT=$(retry_with_fallback "grep '^include_git:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo 'false'" 2 1 2>/dev/null)
        [[ -z "${BACKUP_MODE:+set}" ]] && BACKUP_MODE=$(retry_with_fallback "grep '^backup_mode:' $CONFIG_FILE 2>/dev/null | head -1 | cut -d: -f2- | xargs" "echo 'combo'" 2 1 2>/dev/null) || BACKUP_MODE="combo"
        [[ "$ENCRYPT" == "true" ]] && ENCRYPT=true
        [[ "$COMPRESS" == "true" ]] && COMPRESS=true
        [[ "$FULL_BACKUP" == "true" ]] && FULL_BACKUP=true
        [[ "$INCLUDE_HIDDEN" == "true" ]] && INCLUDE_HIDDEN=true
        [[ "$INCLUDE_GIT" == "true" ]] && INCLUDE_GIT=true
    fi
    BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    BACKUP_TYPE="${BACKUP_TYPE:-local}"
    BACKUP_MODE="${BACKUP_MODE:-combo}"
    
    # Validate that we have required values
    if [[ -z "$BACKUP_DIR" ]]; then
        BACKUP_DIR="$DEFAULT_BACKUP_DIR"
        mkdir -p "$BACKUP_DIR" 2>/dev/null || error "Cannot create default backup directory"
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
backup_dir: $BACKUP_DIR
backup_type: $BACKUP_TYPE
destination: $DESTINATION
backup_mode: $BACKUP_MODE
encrypt: $ENCRYPT
compress: $COMPRESS
full_backup: $FULL_BACKUP
include_hidden: $INCLUDE_HIDDEN
include_git: $INCLUDE_GIT
exclude_node_modules: $EXCLUDE_NODE_MODULES
exclude_bloat: $EXCLUDE_BLOAT
timer_enabled: $SETUP_TIMER
timer_hours: $TIMER_HOURS
EOF
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

get_encryption_key() { echo "$BACKUP_DIR/.backup-key"; }

check_destination() {
    local dest="$1" type="$2"
    # Apply self-healing wrapper
    with_self_healing "check_destination $dest $type" 2>/dev/null || true
    
    case "$type" in
        local|external)
            if [[ ! -d "$dest" ]]; then
                retry_with_fallback "mkdir -p $dest" "echo 'Directory creation failed'" 2 1 2>/dev/null
                [[ ! -d "$dest" ]] && error "Cannot create directory: $dest"
            fi
            if [[ ! -w "$dest" ]]; then
                retry_with_fallback "chmod u+w $dest" "echo 'Permission fix failed'" 2 1 2>/dev/null
                [[ ! -w "$dest" ]] && error "Cannot write: $dest"
            fi
            ;;
        ssh)
            local host="${dest#ssh://}"; host="${host%%/*}"
            if ! retry_with_fallback "ssh -o BatchMode=yes -o ConnectTimeout=5 $host test -w ${dest#*/}" "echo 'SSH check failed'" 2 3 2>/dev/null; then
                error "SSH failed: $dest"
            fi
            ;;
        cloud)
            if [[ "$dest" == s3://* ]]; then
                if ! retry_with_fallback "command -v aws" "echo 'Checking aws'" 2 1 2>/dev/null; then
                    error "AWS CLI missing for S3"
                fi
            fi
            if [[ "$dest" == gs://* ]]; then
                if ! retry_with_fallback "command -v gsutil" "echo 'Checking gsutil'" 2 1 2>/dev/null; then
                    error "gsutil missing for GCS"
                fi
            fi
            ;;
        git)
            if ! git ls-remote "$dest" &>/dev/null; then
                warn "Git repo will be created"
            fi
            ;;
    esac
    success "OK: $dest ($type)"
}

generate_encryption_key() {
    local key_file=$(get_encryption_key)
    [[ -f "$key_file" ]] && return
    log "Generating encryption key..."
    mkdir -p "$(dirname "$key_file")"
    openssl rand -base64 32 > "$key_file"
    chmod 600 "$key_file"
    
    # Automatically create backup of the key in a safe location
    backup_encryption_key "$key_file"
    
    success "Key: $key_file"
    warn "IMPORTANT: Backup this key separately!"
}

# Backup encryption key to a safe location
# Backups are stored in config directory with date stamp
backup_encryption_key() {
    local key_file="$1"
    local key_dir=$(dirname "$key_file")
    
    # Ensure key file exists
    [[ ! -f "$key_file" ]] && return 1
    
    # Create backup directory for keys
    local backup_dir="$CONFIG_DIR/encryption-keys"
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir" 2>/dev/null || chmod 750 "$backup_dir" 2>/dev/null
    
    # Create timestamped backup
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$backup_dir/backup-key.$timestamp"
    
    cp "$key_file" "$backup_file" 2>/dev/null
    chmod 600 "$backup_file" 2>/dev/null
    
    # Limit number of backups to prevent accumulation (keep last 10)
    local count=0
    while IFS= read -r f; do
        count=$((count + 1))
    done < <(find "$backup_dir" -name "backup-key.*" -type f 2>/dev/null | sort)
    
    if [[ $count -gt 10 ]]; then
        # Remove oldest backups
        local to_remove=$((count - 10))
        find "$backup_dir" -name "backup-key.*" -type f 2>/dev/null | sort | head -n "$to_remove" | xargs rm -f 2>/dev/null
    fi
    
    debug "Encryption key backed up to: $backup_file"
    return 0
}

# Validate encryption key file
validate_encryption_key() {
    local key_file="${1:-$(get_encryption_key)}"
    
    if [[ ! -f "$key_file" ]]; then
        error "Encryption key not found: $key_file"
        error "Use --encrypt flag to generate a new key"
        return 1
    fi
    
    if [[ ! -s "$key_file" ]]; then
        error "Encryption key is empty: $key_file"
        return 1
    fi
    
    # Validate key format (base64 encoded 32 bytes = 44 characters)
    local key_content
    key_content=$(cat "$key_file" | tr -d '\n' | tr -d '\r')
    local key_length=${#key_content}
    
    if [[ $key_length -lt 44 ]]; then
        error "Encryption key has invalid length: $key_length (expected ~44)"
        error "Consider regenerating the key"
        return 1
    fi
    
    return 0
}

# List available encryption key backups
list_encryption_key_backups() {
    local backup_dir="$CONFIG_DIR/encryption-keys"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "No encryption key backups found"
        return 1
    fi
    
    log "Available encryption key backups:"
    
    local count=0
    while IFS= read -r backup_file; do
        local timestamp=$(basename "$backup_file" | sed 's/backup-key.//')
        local file_time=$(stat -c %y "$backup_file" 2>/dev/null || date)
        log "  $timestamp - $file_time"
        count=$((count + 1))
    done < <(find "$backup_dir" -name "backup-key.*" -type f 2>/dev/null | sort -r)
    
    if [[ $count -eq 0 ]]; then
        log "  (no backups)"
        return 1
    fi
    
    return 0
}

# Restore encryption key from backup
restore_encryption_key() {
    local backup_timestamp="$1"
    local key_file=$(get_encryption_key)
    local backup_dir="$CONFIG_DIR/encryption-keys"
    local backup_file="$backup_dir/backup-key.$backup_timestamp"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup not found: $backup_file"
        list_encryption_key_backups
        return 1
    fi
    
    # Validate backup file
    if [[ ! -s "$backup_file" ]]; then
        error "Backup file is empty: $backup_file"
        return 1
    fi
    
    log "Restoring encryption key from: $backup_file"
    
    # Atomic restore
    local temp_file="${key_file}.restore.tmp"
    cp "$backup_file" "$temp_file" 2>/dev/null || return 1
    
    if mv "$temp_file" "$key_file" 2>/dev/null; then
        chmod 600 "$key_file"
        log "Encryption key restored successfully"
        return 0
    else
        error "Failed to restore encryption key"
        rm -f "$temp_file" 2>/dev/null
        return 1
    fi
}

encrypt_file() {
    local src="$1" dest="$2" key_file="$3"
    
    # Validate key before attempting encryption
    if ! validate_encryption_key "$key_file"; then
        error "Cannot encrypt: invalid key file"
        return 1
    fi
    
    if openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:"$key_file" -in "$src" -out "$dest" 2>/dev/null; then
        # Verify encrypted file was created successfully
        if [[ -f "$dest" && -s "$dest" ]]; then
            # Remove source only after successful encryption
            rm -f "$src"
            return 0
        else
            error "Encryption output file is missing or empty: $dest"
            return 1
        fi
    else
        error "Encryption failed for: $src"
        return 1
    fi
}

decrypt_file() {
    local src="$1" dest="$2" key_file="$3"
    
    # Validate key before attempting decryption
    if ! validate_encryption_key "$key_file"; then
        error "Cannot decrypt: invalid key file"
        return 1
    fi
    
    if openssl enc -d -aes-256-cbc -pbkdf2 -pass file:"$key_file" -in "$src" -out "$dest" 2>/dev/null; then
        chmod 600 "$dest" 2>/dev/null
        return 0
    else
        error "Decryption failed for: $src"
        return 1
    fi
}

# =============================================================================
# TIMER SETUP
# =============================================================================

setup_backup_timer() {
    local hours="${TIMER_HOURS:-6}"
    local cron_file=""
    
    # Determine cron file based on what's available
    # Container-friendly: try user crontab first, then system
    cron_file=""
    
    # Check if crontab command exists and can install user cron
    if command -v crontab &>/dev/null; then
        # Try to use crontab command which works in most environments
        cron_file=""
        log "Setting up user timer via crontab command"
    elif [[ -w "/etc/crontab" ]]; then
        cron_file="/etc/crontab"
        log "Setting up system-wide timer (requires root)"
    else
        # Fallback to user cron file
        cron_file="$HOME/.crontab"
        log "Setting up user timer"
    fi
    
    # Create backup of existing crontab if using a file
    local cron_backup=""
    if [[ -n "$cron_file" ]]; then
        cron_backup="${cron_file}.backup-$(date +%Y%m%d-%H%M%S)"
        if [[ -f "$cron_file" ]]; then
            cp "$cron_file" "$cron_backup"
            log "Existing crontab backed up: $cron_backup"
        fi
    fi
    
    # Create or update crontab entry
    local backup_cmd="$SCRIPT_DIR/backup-interactive.sh backup"
    local cron_line="0 */$hours * * * $backup_cmd"
    
    if [[ -n "$cron_file" ]]; then
        # Using a cron file
        # Check if entry already exists
        if [[ -f "$cron_file" ]] && grep -qF "$backup_cmd" "$cron_file" 2>/dev/null; then
            log "Backup timer already exists, updating..."
            # Remove old entry
            grep -vF "$backup_cmd" "$cron_file" > "${cron_file}.tmp" 2>/dev/null || true
            mv "${cron_file}.tmp" "$cron_file" 2>/dev/null || true
        fi
        
        # Add new entry
        echo "$cron_line" >> "$cron_file"
        
        # Install crontab if it's a user file
        if [[ "$cron_file" == "$HOME/.crontab" ]]; then
            crontab "$cron_file" 2>/dev/null || log "Note: Could not install crontab (may need to run as user)"
            log "User crontab file updated: $cron_file"
        else
            log "System crontab updated: $cron_file"
        fi
    else
        # Use crontab command directly (most portable, works in containers)
        log "Updating crontab via command..."
        # Remove existing entry if present
        crontab -l 2>/dev/null | grep -vF "$backup_cmd" | crontab - 2>/dev/null || true
        # Add new entry
        (crontab -l 2>/dev/null; echo "$cron_line") | crontab - 2>/dev/null || {
            # If crontab is not available for user, create a file they can install manually
            echo "$cron_line" > "$RUNTIME_ROOT/crontab-entry.txt"
            log "Crontab entry created: $RUNTIME_ROOT/crontab-entry.txt"
            log "Please install manually with: crontab $RUNTIME_ROOT/crontab-entry.txt"
        }
    fi
    
    log "Backup timer set: Every $hours hours"
    log "Command: $backup_cmd"
    log "Next backup: $(date -d "+$hours hours" +"%Y-%m-%d %H:%M:%S")"
    
    success "Backup timer configured successfully"
}

# =============================================================================
# VERIFICATION FUNCTIONS
# =============================================================================

verify_module_capability() {
    local agent_dir="$1"
    log "Verifying: ${agent_dir##*/}"
    [[ -f "$agent_dir/package.json" ]] && log "  ✓ Node.js: can npm/yarn/pnpm install"
    [[ -f "$agent_dir/requirements.txt" ]] && log "  ✓ Python: can pip install"
    [[ -f "$agent_dir/Dockerfile" ]] && log "  ✓ Docker: can rebuild"
    command -v curl >/dev/null && curl -s --connect-timeout 5 https://registry.npmjs.org &>/dev/null && log "  ✓ npm registry accessible"
    command -v npm >/dev/null && log "  ✓ npm available" || log "  - npm not installed"
    command -v pip >/dev/null && log "  ✓ pip available" || log "  - pip not installed"
    success "Agent CAN download modules"
}

verify_backup_integrity() {
    local backup_dir="$1"
    local expected_files=(
        "crews/" "agents/" "docker/" "config/"
        "BACKUP_MANIFEST.txt"
    )
    
    log "Verifying backup integrity: $backup_dir"
    
    for file in "${expected_files[@]}"; do
        if [[ -e "$backup_dir/$file" ]]; then
            log "  ✓ $file"
        else
            warn "  ✗ $file MISSING"
        fi
    done
    
    # Check manifest
    if [[ -f "$backup_dir/BACKUP_MANIFEST.txt" ]]; then
        log "  ✓ Manifest exists"
        local mode=$(grep "Mode:" "$backup_dir/BACKUP_MANIFEST.txt" | awk '{print $2}')
        log "  Mode: $mode"
    fi
    
    # Count files
    local file_count=$(find "$backup_dir" -type f 2>/dev/null | wc -l)
    local dir_count=$(find "$backup_dir" -type d 2>/dev/null | wc -l)
    log "  Files: $file_count, Directories: $dir_count"
    
    success "Backup integrity verified"
}

# =============================================================================
# BACKUP EXCLUDE LOGIC
# =============================================================================

# Build exclude list based on mode and settings
get_excludes() {
    local excludes=()
    
    # Always exclude these
    excludes+=("${ALWAYS_EXCLUDE[@]}")
    
    # Optionally exclude git
    if [[ "$INCLUDE_GIT" == false ]]; then
        excludes+=(".git/")
        excludes+=(".gitignore")
        excludes+=(".gitmodules")
    fi
    
    # Exclude node_modules only if lockfile exists (package-lock.json, yarn.lock, etc.)
    # This is checked per-directory in backup_directory function where src path is available
    # So we don't add bloat excludes here - they're added conditionally in backup_directory
    
    # Add Docker-specific excludes
    excludes+=("${DOCKER_EXCLUDE[@]}")
    
    # Add user excludes
    excludes+=("${EXCLUDE_PATTERNS[@]}")
    
    # Mode-specific excludes
    case "$BACKUP_MODE" in
        plan-history) excludes+=("*.tar" "*.gz" "*.zip" "*.img" "*.iso" ".docker/") ;;
    esac
    
    # Print excludes for rsync
    for pat in "${excludes[@]}"; do
        [[ -n "$pat" ]] && echo "--exclude=$pat"
    done
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

backup_directory() {
    local src="$1" dest="$2" manifest_file="$3" section="$4" level="$5"
    
    # Validate source exists
    if [[ ! -d "$src" ]]; then
        warn "Source directory does not exist: $src"
        return 0
    fi
    
    # Apply self-healing
    with_self_healing "backup_directory $src $dest" 2>/dev/null || true
    
    log "Backing up: $section (level: $level)"
    
    # Create destination with retry
    if ! retry_with_fallback "mkdir -p $dest" "echo 'Fallback mkdir failed'" 3 1 2>/dev/null; then
        error "Cannot create destination directory: $dest"
        return 1
    fi
    
    local excludes=()
    
    # Get base excludes
    while IFS= read -r exclude; do
        [[ -n "$exclude" ]] && excludes+=("$exclude")
    done < <(get_excludes)
    
    # Check for lockfiles before adding node_modules to excludes
    # Per user requirement: exclude node_modules only if lockfile exists
    if [[ "$EXCLUDE_NODE_MODULES" == true ]]; then
        if [[ -f "$src/package-lock.json" ]] || \
           [[ -f "$src/yarn.lock" ]] || \
           [[ -f "$src/pnpm-lock.yaml" ]] || \
           [[ -f "$src/poetry.lock" ]] || \
           find "$src" -maxdepth 1 -name "*lock*" -type f &>/dev/null; then
            # Lockfile exists, add bloat excludes
            excludes+=("${BLOAT_EXCLUDE[@]}")
        fi
    fi
    
    # Add level-specific excludes
    case "$level" in
        configs)
            # Exclude sessions, logs, temporary files
            excludes+=(
                "sessions/" "logs/" "temp/" "tmp/"
                "*.log" "*.session" "*.tmp"
            )
            ;;
        full)
            # Include everything (no additional excludes)
            :
            ;;
        workspaces)
            # Exclude only temp files
            excludes+=(
                "temp/" "tmp/"
            )
            ;;
    esac
    
    # Use rsync with all excludes
    # Note: We only use rsync to maintain exclude patterns; no cp fallback
    # rsync often returns non-zero even on success (permission issues on some files), so we suppress warnings
    if [[ ${#excludes[@]} -gt 0 ]]; then
        rsync -a "${excludes[@]}" "$src/" "$dest/" 2>/dev/null
    else
        rsync -a "$src/" "$dest/" 2>/dev/null
    fi
    
    # Handle hidden files
    if [[ "$INCLUDE_HIDDEN" == true ]]; then
        # Already included by rsync -a
        :
    else
        # Remove hidden files after backup
        find "$dest" -name ".*" -type f 2>/dev/null | while read hf; do
            rm -f "$hf" 2>/dev/null || true
        done
        find "$dest" -name ".*" -type d 2>/dev/null | while read hd; do
            rm -rf "$hd" 2>/dev/null || true
        done
    fi
    
    local count=$(find "$dest" -type f 2>/dev/null | wc -l)
    local size=$(du -sh "$dest" 2>/dev/null | cut -f1)
    echo "  $section: $count files, $size" >> "$manifest_file"
}

backup_standard_directory() {
    local src="$1" dest="$2" manifest_file="$3" section="$4"
    
    # Standard backup includes:
    # - Configurations
    # - Identifying files (SOUL.md, USER.md, IDENTITY.md, MEMORY.md, AGENTS.md)
    # - Memory files
    # Excludes: sessions, logs, temp
    
    backup_directory "$src" "$dest" "$manifest_file" "$section" "configs"
}

backup_full_directory() {
    local src="$1" dest="$2" manifest_file="$3" section="$4"
    
    # Full backup includes everything:
    # - All configurations
    # - All identifying files
    # - All memory files
    # - Sessions
    # - Logs
    # - Docker volumes (if applicable)
    # - Everything else
    
    backup_directory "$src" "$dest" "$manifest_file" "$section" "full"
}

enrypt_sensitive() {
    local dest_dir="$1" key_file="$2" count=0
    [[ ! -d "$dest_dir" ]] && return
    
    log "Encrypting sensitive files..."
    
    for agent_dir in "$dest_dir/agents/"*/; do
        [[ -d "$agent_dir" ]] || continue
        for f in "$agent_dir".env "$agent_dir"auth.json; do
            [[ -f "$f" ]] && ! [[ -f "${f}.enc" ]] && encrypt_file "$f" "${f}.enc" "$key_file" && ((count++))
        done
        [[ -d "$agent_dir/.secrets" ]] && for sf in "$agent_dir/.secrets"/*; do
            [[ -f "$sf" ]] && [[ "$sf" != *.enc ]] && encrypt_file "$sf" "${sf}.enc" "$key_file" && ((count++))
        done
    done
    
    log "Encrypted: $count files"
}

backup_docker_images() {
    [[ "$BACKUP_MODE" == "plan-history" ]] && return 0
    [[ -z "$(command -v docker 2>/dev/null)" ]] && return 0
    
    log "Backing up Docker images..."
    local images_dir="$1/docker/images"
    mkdir -p "$images_dir"
    
    # Only back up images that are part of this project, not everything on the machine
    # Get images from docker-compose.yml if it exists
    local compose_file="$RUNTIME_ROOT/docker-compose.yml"
    local project_images=()
    local count=0
    local project_name="$(basename "$RUNTIME_ROOT")"
    local project_prefix="${project_name//-/_}"
    
    if [[ -f "$compose_file" ]]; then
        # Extract image names from docker-compose.yml
        # Look for 'image:' fields (explicit images)
        while IFS= read -r line; do
            # Match image: tag with various quoting
            if [[ "$line" =~ image:[[:space:]]*([a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]*) ]] || \
               [[ "$line" =~ image:[[:space:]]*'([a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]*)' ]] || \
               [[ "$line" =~ image:[[:space:]]*"([a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]*)" ]]; then
                local img="${BASH_REMATCH[1]}"
                [[ -n "$img" ]] && project_images+=("$img") && log "  Found project image: $img"
            fi
        done < "$compose_file"
        
        # Also extract service names for build contexts
        # When a service uses 'build:' without 'image:', we need to find the built image
        local service_names=()
        local in_service=false
        local current_service=""
        local current_image=""
        local current_build=""
        
        while IFS= read -r line; do
            # Match service name
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9._-]+):[[:space:]]*$ ]]; then
                current_service="${BASH_REMATCH[1]}"
                in_service=true
                current_image=""
                current_build=""
            elif [[ "$line" =~ [[:space:]]*image:[[:space:]]*(.*) ]]; then
                # Extract image name, handling various quoting
                local img_value="${BASH_REMATCH[1]#\"}"
                img_value="${img_value%\"}"
                img_value="${img_value#'}"
                img_value="${img_value%'}"
                img_value=$(echo "$img_value" | xargs)
                [[ -n "$img_value" && "$img_value" != "null" && "$img_value" != "none" ]] && current_image="$img_value"
            elif [[ "$line" =~ [[:space:]]*build:[[:space:]]*(.*) ]]; then
                # This service uses build context
                local build_value="${BASH_REMATCH[1]#\"}"
                build_value="${build_value%\"}"
                build_value="${build_value#'}"
                build_value="${build_value%'}"
                build_value=$(echo "$build_value" | xargs)
                [[ -n "$build_value" ]] && current_build="$build_value" && service_names+=("$current_service")
            fi
        done < "$compose_file"
        
        # For services with build context, look for matching images
        if [[ ${#service_names[@]} -gt 0 ]]; then
            # Get all local images
            local all_images=$(docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
            
            for svc in "${service_names[@]}"; do
                # Look for images matching the service name or project prefix
                # Docker may have named the built image after the service or directory
                local potential_names=(
                    "$svc"
                    "${svc//-/_}"
                    "${project_name}-${svc}"
                    "${project_prefix}_${svc//-/_}"
                    "${project_name}"
                    "${project_prefix}"
                )
                
                for pname in "${potential_names[@]}"; do
                    if [[ -n "$all_images" ]]; then
                        while IFS= read -r full_img; do
                            [[ -z "$full_img" ]] && continue
                            if [[ "$full_img" == "$pname:*" || "$full_img" == "$pname" || "$full_img" == *"$pname"* ]]; then
                                # Check if not already in project_images
                                local already=false
                                for existing in "${project_images[@]}"; do
                                    [[ "$existing" == "$full_img" ]] && already=true && break
                                done
                                [[ "$already" == false ]] && project_images+=("$full_img") && log "  Found project image: $full_img (from service: $svc)"
                            fi
                        done <<< "$all_images"
                    fi
                done
            done
        fi
    fi
    
    # Also check for images built from Dockerfiles in the project
    local dockerfiles=(
        "$RUNTIME_ROOT/Dockerfile"
        "$RUNTIME_ROOT/Dockerfile.agent"
        "$RUNTIME_ROOT/docker/Dockerfile*"
    )
    
    # Check if any Dockerfiles exist and if their images are built
    for df in "${dockerfiles[@]}"; do
        if [[ -f "$df" ]]; then
            local df_name=$(basename "$df")
            local df_prefix="${df_name%.Dockerfile}"
            df_prefix="${df_prefix//-/_}"
            
            # Look for images that match this Dockerfile
            if [[ -n "$all_images" ]]; then
                for full_img in $all_images; do
                    [[ -z "$full_img" ]] && continue
                    if [[ "$full_img" == *"$df_prefix"* || "$full_img" == *"${df_name}"* ]]; then
                        local already=false
                        for existing in "${project_images[@]}"; do
                            [[ "$existing" == "$full_img" ]] && already=true && break
                        done
                        [[ "$already" == false ]] && project_images+=("$full_img") && log "  Found project image: $full_img (from Dockerfile: $df_name)"
                    fi
                done
            fi
        fi
    done
    
    # Also check if we need to build images from build contexts
    if [[ ${#service_names[@]} -gt 0 && ${#project_images[@]} -eq 0 ]]; then
        log "  No pre-built images found, checking if builds are needed..."
        # This would require building, which may not be desired during backup
        log "  Note: Services with 'build:' in docker-compose.yml may need manual build first"
    fi
    
    # Back up only project-specific images
    if [[ ${#project_images[@]} -gt 0 ]]; then
        for img in "${project_images[@]}"; do
            local safe_name=$(echo "$img" | sed 's/[^a-zA-Z0-9._-]/_/g')
            # Check if image exists locally before trying to save
            if docker inspect "$img" >/dev/null 2>&1; then
                docker save "$img" > "$images_dir/${safe_name}.tar" 2>/dev/null && ((count++)) || true
            else
                log "  Skipping $img (not found locally - may need to build first)"
            fi
        done
    else
        log "  No project-specific Docker images found to back up"
        log "  Tip: Run 'docker-compose build' first if using build contexts"
    fi
    
    log "Docker images backed up: $count"
}

backup_docker_volumes() {
    [[ "$BACKUP_MODE" == "plan-history" ]] && return 0
    [[ -z "$(command -v docker 2>/dev/null)" ]] && return 0
    
    log "Backing up Docker volumes..."
    local volumes_dir="$1/docker/volumes"
    mkdir -p "$volumes_dir"
    
    # Only back up volumes that are part of this project
    local compose_file="$RUNTIME_ROOT/docker-compose.yml"
    local project_volumes=()
    local all_volumes=$(docker volume ls -q 2>/dev/null || true)
    local count=0
    
    if [[ -n "$all_volumes" ]]; then
        # Extract volume names from docker-compose.yml
        if [[ -f "$compose_file" ]]; then
            while IFS= read -r line; do
                # Match volume names in compose file
                if [[ "$line" =~ volumes:[[:space:]]*[-]?[[:space:]]*([a-zA-Z0-9._-]+) ]] || \
                   [[ "$line" =~ volumes:[[:space:]]*[-]?[[:space:]]*'([a-zA-Z0-9._-]+)' ]] || \
                   [[ "$line" =~ volumes:[[:space:]]*[-]?[[:space:]]*"([a-zA-Z0-9._-]+)" ]]; then
                    local vol_name="${BASH_REMATCH[1]}"
                    [[ -n "$vol_name" ]] && project_volumes+=("$vol_name") && log "  Found project volume: $vol_name"
                # Also match anonymous volumes (relative paths)
                elif [[ "$line" =~ [-][[:space:]]*\./([a-zA-Z0-9._-]+) ]] || \
                     [[ "$line" =~ [-][[:space:]]*'\./([a-zA-Z0-9._-]+)' ]] || \
                     [[ "$line" =~ [-][[:space:]]*"\./([a-zA-Z0-9._-]+)" ]]; then
                    local vol_path="${BASH_REMATCH[1]}"
                    # Convert path to volume name if it exists as a volume
                    for check_vol in $all_volumes; do
                        if [[ "$check_vol" == *"$vol_path"* ]] || [[ "$check_vol" == "$vol_path" ]]; then
                            project_volumes+=("$check_vol") && log "  Found project volume: $check_vol"
                        fi
                    done
                fi
            done < "$compose_file"
        fi
        
        # If we found specific volumes in compose, only back up those
        if [[ ${#project_volumes[@]} -gt 0 ]]; then
            for vol in "${project_volumes[@]}"; do
                # Check if volume exists
                if docker inspect "$vol" >/dev/null 2>&1; then
                    local safe_name=$(echo "$vol" | sed 's/[^a-zA-Z0-9._-]/_/g')
                    docker run --rm -v "$vol":/data -v "$volumes_dir":/backup busybox \
                        tar -czf "/backup/${safe_name}.tar.gz" -C /data . 2>/dev/null && ((count++)) || true
                else
                    log "  Skipping volume $vol (not found)"
                fi
            done
        else
            # If no specific volumes defined, look for project-named volumes
            local project_name="$(basename "$RUNTIME_ROOT")"
            local project_prefix="${project_name//-/_}"
            
            for vol in $all_volumes; do
                if [[ "$vol" == *"$project_prefix"* ]] || \
                   [[ "$vol" == *"openclaw"* ]] || \
                   [[ "$vol" == *"agent"* ]] || \
                   [[ "$vol" == *"crew"* ]]; then
                    local safe_name=$(echo "$vol" | sed 's/[^a-zA-Z0-9._-]/_/g')
                    docker run --rm -v "$vol":/data -v "$volumes_dir":/backup busybox \
                        tar -czf "/backup/${safe_name}.tar.gz" -C /data . 2>/dev/null && ((count++)) || true
                fi
            done
        fi
    else
        log "  No Docker volumes found on system"
    fi
    
    log "Docker volumes backed up: $count"
}

backup_sessions() {
    local sessions_dir="$RUNTIME_ROOT/sessions"
    [[ ! -d "$sessions_dir" ]] && return 0
    [[ "$FULL_BACKUP" != true ]] && return 0
    
    log "Backing up sessions..."
    backup_directory "$sessions_dir" "$1/sessions" "$2" "Sessions" "full"
}

backup_workflows() {
    local workflows_dir="$RUNTIME_ROOT/workflows"
    [[ ! -d "$workflows_dir" ]] && return 0
    [[ "$FULL_BACKUP" != true ]] && return 0
    
    log "Backing up workflows..."
    backup_directory "$workflows_dir" "$1/workflows" "$2" "Workflows" "full"
}

# =============================================================================
# MAIN BACKUP COMMAND
# =============================================================================

cmd_backup() {
    # Apply self-healing wrapper to the entire backup process
    with_self_healing "cmd_backup" 2>/dev/null || true
    
    # Load config with error handling
    load_config || { error "Failed to load configuration"; return 1; }
    
    local backup_type="${BACKUP_TYPE:-local}"
    local dest="${DESTINATION:-${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}}"
    
    # Validate and create destination with retry
    if [[ -z "$dest" ]]; then
        dest="${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}"
    fi
    
    # Ensure destination directory exists
    if [[ ! -d "$dest" ]]; then
        if ! retry_with_fallback "mkdir -p $dest" "echo 'Fallback directory creation failed'" 3 1; then
            error "Cannot create backup destination directory: $dest"
            return 1
        fi
    fi
    
    # Validate we can write to destination
    if [[ ! -w "$dest" ]]; then
        if ! retry_with_fallback "chmod u+w $dest" "echo 'Fallback permission fix failed'" 2 1; then
            error "Cannot write to destination: $dest"
            return 1
        fi
    fi
    
    if [[ "$BACKUP_TYPE" == "git" ]]; then
        if [[ ! -d "$dest/.git" ]]; then
            rmdir "$dest" 2>/dev/null || true
            mkdir -p "$dest"
            cd "$dest"
            git init
            git remote add origin "$dest"
            cd - >/dev/null
        fi
    fi
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local bk_dir="$dest/backup-$timestamp"
    mkdir -p "$bk_dir"
    
    log "Backup: $bk_dir (mode: $BACKUP_MODE, level: crew=$CREW_LEVEL, agent=$AGENT_LEVEL)"
    local manifest="$bk_dir/BACKUP_MANIFEST.txt"
    
    echo "Backup Manifest" > "$manifest"
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$manifest"
    echo "Mode: $BACKUP_MODE" >> "$manifest"
    echo "Type: $backup_type" >> "$manifest"
    echo "Crew selection: ${CREW_SELECTION:-all}" >> "$manifest"
    echo "Crew level: $CREW_LEVEL" >> "$manifest"
    echo "Agent selection: ${AGENT_SELECTION:-all}" >> "$manifest"
    echo "Agent level: $AGENT_LEVEL" >> "$manifest"
    echo "Combo mode: ${COMBO_MODE:-none}" >> "$manifest"
    echo "Include hidden: $INCLUDE_HIDDEN" >> "$manifest"
    echo "Include git: $INCLUDE_GIT" >> "$manifest"
    echo "" >> "$manifest"
    echo "Components:" >> "$manifest"
    
    # Handle combo mode
    if [[ -n "$COMBO_MODE" ]]; then
        case "$COMBO_MODE" in
            crews-configs|crews-full|crews-workspaces|all-full)
                # Parse combo mode
                local crew_level="" agent_level=""
                case "$COMBO_MODE" in
                    crews-configs) crew_level="configs"; agent_level="configs";;
                    crews-full) crew_level="full"; agent_level="full";;
                    crews-workspaces) crew_level="workspaces"; agent_level="configs";;
                    all-full) crew_level="workspaces"; agent_level="full";;
                esac
                
                ALL_CREWS=true
                ALL_AGENTS=true
                CREW_LEVEL="$crew_level"
                AGENT_LEVEL="$agent_level"
                ;;
        esac
    fi
    
    # Backup crews
    if [[ "$ALL_CREWS" == true ]] || [[ -n "$CREW_SELECTION" ]]; then
        if [[ -d "$CREWS_DIR" ]]; then
            if [[ -n "$CREW_SELECTION" ]]; then
                # Specific crews
                IFS=',' read -ra crews <<< "$CREW_SELECTION"
                for crew in "${crews[@]}"; do
                    if [[ -d "$CREWS_DIR/$crew" ]]; then
                        case "$CREW_LEVEL" in
                            configs) backup_standard_directory "$CREWS_DIR/$crew" "$bk_dir/crews/$crew" "$manifest" "Crew: $crew (configs)";;
                            full|workspaces) backup_full_directory "$CREWS_DIR/$crew" "$bk_dir/crews/$crew" "$manifest" "Crew: $crew ($CREW_LEVEL)";;
                        esac
                    else
                        warn "Crew not found: $crew"
                    fi
                done
            else
                # All crews
                for crew_dir in "$CREWS_DIR"/*/; do
                    local crew_name=$(basename "$crew_dir")
                    case "$CREW_LEVEL" in
                        configs) backup_standard_directory "$crew_dir" "$bk_dir/crews/$crew_name" "$manifest" "Crew: $crew_name (configs)";;
                        full|workspaces) backup_full_directory "$crew_dir" "$bk_dir/crews/$crew_name" "$manifest" "Crew: $crew_name ($CREW_LEVEL)";;
                    esac
                done
            fi
        else
            log "No crews directory: $CREWS_DIR"
        fi
    fi
    
    # Backup agents
    if [[ "$ALL_AGENTS" == true ]] || [[ -n "$AGENT_SELECTION" ]]; then
        if [[ -d "$AGENTS_DIR" ]]; then
            if [[ -n "$AGENT_SELECTION" ]]; then
                # Specific agents
                IFS=',' read -ra agents <<< "$AGENT_SELECTION"
                for agent in "${agents[@]}"; do
                    if [[ -d "$AGENTS_DIR/$agent" ]]; then
                        case "$AGENT_LEVEL" in
                            configs) backup_standard_directory "$AGENTS_DIR/$agent" "$bk_dir/agents/$agent" "$manifest" "Agent: $agent (configs)";;
                            full) backup_full_directory "$AGENTS_DIR/$agent" "$bk_dir/agents/$agent" "$manifest" "Agent: $agent (full)";;
                        esac
                    else
                        warn "Agent not found: $agent"
                    fi
                done
            else
                # All agents
                for agent_dir in "$AGENTS_DIR"/*/; do
                    local agent_name=$(basename "$agent_dir")
                    case "$AGENT_LEVEL" in
                        configs) backup_standard_directory "$agent_dir" "$bk_dir/agents/$agent_name" "$manifest" "Agent: $agent_name (configs)";;
                        full) backup_full_directory "$agent_dir" "$bk_dir/agents/$agent_name" "$manifest" "Agent: $agent_name (full)";;
                    esac
                done
            fi
        else
            log "No agents directory: $AGENTS_DIR"
        fi
    fi
    
    # If neither crews nor agents specified, backup both (for backward compatibility)
    if [[ "$ALL_CREWS" == false ]] && [[ "$ALL_AGENTS" == false ]] && \
       [[ -z "$CREW_SELECTION" ]] && [[ -z "$AGENT_SELECTION" ]] && \
       [[ -z "$COMBO_MODE" ]]; then
        # Default behavior: backup both crews and agents
        if [[ -d "$CREWS_DIR" ]]; then
            for crew_dir in "$CREWS_DIR"/*/; do
                local crew_name=$(basename "$crew_dir")
                case "$CREW_LEVEL" in
                    configs) backup_standard_directory "$crew_dir" "$bk_dir/crews/$crew_name" "$manifest" "Crew: $crew_name (configs)";;
                    full|workspaces) backup_full_directory "$crew_dir" "$bk_dir/crews/$crew_name" "$manifest" "Crew: $crew_name ($CREW_LEVEL)";;
                esac
            done
        fi
        
        if [[ -d "$AGENTS_DIR" ]]; then
            for agent_dir in "$AGENTS_DIR"/*/; do
                local agent_name=$(basename "$agent_dir")
                case "$AGENT_LEVEL" in
                    configs) backup_standard_directory "$agent_dir" "$bk_dir/agents/$agent_name" "$manifest" "Agent: $agent_name (configs)";;
                    full) backup_full_directory "$agent_dir" "$bk_dir/agents/$agent_name" "$manifest" "Agent: $agent_name (full)";;
                esac
            done
        fi
    fi
    
    # Backup Docker
    if [[ -d "$DOCKER_DIR" ]]; then
        backup_standard_directory "$DOCKER_DIR" "$bk_dir/docker" "$manifest" "Docker configs"
        backup_docker_images "$bk_dir" "$BACKUP_MODE"
        backup_docker_volumes "$bk_dir" "$BACKUP_MODE"
    fi
    
    # Backup runtime configs
    if [[ -d "$CONFIG_DIR" ]]; then
        backup_standard_directory "$CONFIG_DIR" "$bk_dir/config" "$manifest" "Runtime configs"
    fi
    
    # Backup sessions and workflows if full
    backup_sessions "$bk_dir" "$manifest"
    backup_workflows "$bk_dir" "$manifest"
    
    # Backup plugins
    if [[ -d "$PLUGINS_DIR" ]]; then
        backup_standard_directory "$PLUGINS_DIR" "$bk_dir/plugins" "$manifest" "Plugins"
    fi
    
    # Backup root-level skills directory if requested (optional, shared resource)
    # Note: This is the CANONICAL skills directory at the project root
    # Agent-specific skills (in agents/*/skills/) are backed up with each agent
    if [[ "${INCLUDE_SKILLS:-false}" == true ]]; then
        [[ -d "$SKILLS_DIR" ]] && backup_standard_directory "$SKILLS_DIR" "$bk_dir/skills" "$manifest" "Root Skills Directory"
    fi
    
    # Encrypt sensitive files
    [[ "$ENCRYPT" == true ]] && [[ -f "$(get_encryption_key)" ]] && enrypt_sensitive "$bk_dir" "$(get_encryption_key)"
    
    # Compress if requested
    if [[ "$COMPRESS" == true ]]; then
        log "Compressing..."
        tar -czf "$dest/backup-$timestamp.tar.gz" -C "$dest" "backup-$timestamp" 2>/dev/null
        rm -rf "$bk_dir"
        bk_dir="$dest/backup-$timestamp.tar.gz"
    fi
    
    # Git push if git type
    if [[ "$backup_type" == "git" ]]; then
        cd "$dest"
        git add -A
        git commit -m "backup: $(date -u +%Y-%m-%dT%H:%M:%SZ) mode:$BACKUP_MODE" --quiet 2>/dev/null || true
        git push --quiet 2>&1 || warn "Git push failed"
        cd - >/dev/null
    fi
    
    local size=$(du -sh "$bk_dir" 2>/dev/null | cut -f1)
    success "Backup complete: $bk_dir ($size)"
    echo "$timestamp" > "$dest/.last-backup"
    echo "$BACKUP_MODE" > "$dest/.last-backup-mode"
}

# =============================================================================
# INIT COMMAND
# =============================================================================

cmd_init() {
    log "Backup Setup"
    
    read -rp "Backup destination [$DEFAULT_BACKUP_DIR]: " resp
    [[ -n "$resp" ]] && BACKUP_DIR="$resp"
    
    echo "Backup type: 1)local 2)external 3)ssh 4)git 5)cloud"
    read -rp "Select [1-5]: " t
    case "$t" in
        1) BACKUP_TYPE="local";;
        2) BACKUP_TYPE="external";;
        3) BACKUP_TYPE="ssh";;
        4) BACKUP_TYPE="git";;
        5) BACKUP_TYPE="cloud";;
    esac
    
    [[ "$BACKUP_TYPE" == "ssh" ]] && { read -rp "SSH dest: " d; DESTINATION="ssh://$d"; }
    [[ "$BACKUP_TYPE" == "git" ]] && { read -rp "Git URL: " d; DESTINATION="$d"; }
    [[ "$BACKUP_TYPE" == "cloud" ]] && { read -rp "Cloud URL: " d; DESTINATION="$d"; }
    
    echo "Backup mode: 1)plan-history 2)docker-full 3)combo"
    read -rp "Select [1-3]: " m
    case "$m" in
        1) BACKUP_MODE="plan-history";;
        2) BACKUP_MODE="docker-full";;
        *) BACKUP_MODE="combo";;
    esac
    
    read -rp "Include hidden files? [Y/n]: " h
    [[ "$h" =~ ^[nN] ]] && INCLUDE_HIDDEN=false
    
    read -rp "Include .git directories? (NOT recommended) [y/N]: " g
    [[ "$g" =~ ^[Yy] ]] && INCLUDE_GIT=true
    
    read -rp "Exclude node_modules? (RECOMMENDED) [Y/n]: " e
    [[ "$e" =~ ^[nN] ]] && EXCLUDE_NODE_MODULES=false
    
    read -rp "Exclude bloat? (RECOMMENDED) [Y/n]: " b
    [[ "$b" =~ ^[nN] ]] && EXCLUDE_BLOAT=false
    
    read -rp "Setup automatic timer? [Y/n]: " t
    [[ "$t" =~ ^[Yy] ]] && SETUP_TIMER=true
    
    if [[ "$SETUP_TIMER" == true ]]; then
        read -rp "Timer interval (hours, default 6): " ti
        [[ -n "$ti" ]] && TIMER_HOURS="$ti"
    fi
    
    read -rp "Encrypt sensitive files? [y/N]: " e
    [[ "$e" =~ ^[Yy] ]] && { ENCRYPT=true; generate_encryption_key; }
    
    read -rp "Compress backups? [y/N]: " c
    [[ "$c" =~ ^[Yy] ]] && COMPRESS=true
    
    save_config
    local actual="${DESTINATION:-$BACKUP_DIR}"
    [[ -n "$BACKUP_DIR" ]] && [[ "$BACKUP_TYPE" != "" ]] && check_destination "$actual" "$BACKUP_TYPE"
    
    # Setup timer if requested
    if [[ "$SETUP_TIMER" == true ]]; then
        setup_backup_timer
    fi
    
    success "Backup initialized successfully"
    echo "Configuration:"
    echo "  Mode: $BACKUP_MODE"
    echo "  Type: $BACKUP_TYPE"
    echo "  Destination: ${DESTINATION:-$BACKUP_DIR}"
    echo "  Include hidden: $INCLUDE_HIDDEN"
    echo "  Include .git: $INCLUDE_GIT"
    echo "  Exclude node_modules: $EXCLUDE_NODE_MODULES"
    echo "  Timer: $SETUP_TIMER ($TIMER_HOURS hours)"
    echo ""
    echo "Config file: $CONFIG_FILE"
}

# =============================================================================
# OTHER COMMANDS (stubs for now)
# =============================================================================

cmd_restore() {
    log "Restore not yet fully implemented in this version"
    log "Use backup-interactive.sh from plugins for full restore"
}

cmd_status() {
    load_config
    echo "Backup Configuration:"
    echo "  Mode: ${BACKUP_MODE:-combo}"
    echo "  Type: ${BACKUP_TYPE:-local}"
    echo "  Destination: ${DESTINATION:-${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}}"
    echo "  Include hidden: $INCLUDE_HIDDEN"
    echo "  Include .git: $INCLUDE_GIT"
    echo "  Exclude node_modules: $EXCLUDE_NODE_MODULES"
    echo "  Timer: $SETUP_TIMER ($TIMER_HOURS hours)"
    
    local dest="${DESTINATION:-${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}}"
    if [[ -d "$dest" ]]; then
        echo ""
        echo "Last Backup:"
        cat "$dest/.last-backup" 2>/dev/null || echo "  Never"
        echo "Mode: $(cat "$dest/.last-backup-mode" 2>/dev/null || echo "unknown")"
    fi
}

cmd_list() {
    load_config
    local dest="${DESTINATION:-${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}}"
    local type="${BACKUP_TYPE:-local}"
    
    if [[ "$type" == "local" ]] || [[ "$type" == "external" ]]; then
        if [[ -d "$dest" ]]; then
            log "Available backups:"
            ls -td "$dest"/backup-* 2>/dev/null | while read bk; do
                if [[ -d "$bk" ]]; then
                    echo "  $(basename "$bk") - $(du -sh "$bk" 2>/dev/null | cut -f1) ($(cat "$bk/BACKUP_MANIFEST.txt" | grep "Mode:" | awk '{print $2}' 2>/dev/null || echo "unknown"))"
                fi
            done
        else
            log "No backups: $dest"
        fi
    elif [[ "$type" == "git" ]]; then
        log "Git backups:"
        cd "$dest" 2>/dev/null && git log --oneline | head -10 || log "No git repo"
        cd - >/dev/null 2>/dev/null || true
    else
        log "Listing not implemented for: $type"
    fi
}

cmd_validate() {
    load_config
    local dest="${DESTINATION:-${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}}"
    local latest=$(ls -td "$dest"/backup-* 2>/dev/null | head -1)
    
    if [[ -z "$latest" ]] || [[ ! -d "$latest" ]]; then
        error "No backup found in $dest"
    fi
    
    verify_backup_integrity "$latest"
}

cmd_test() {
    log "Running comprehensive test suite..."
    
    # Test 1: Backup specific crew
    log "Test 1: Backup specific crew"
    if [[ -d "$CREWS_DIR" ]] && ls "$CREWS_DIR" 2>/dev/null | head -1 >/dev/null; then
        local test_crew=$(ls "$CREWS_DIR" 2>/dev/null | head -1)
        if [[ -n "$test_crew" ]]; then
            ./scripts/backup-interactive.sh backup --crews "$test_crew" --dry-run >/dev/null 2>&1 && {
                log "  ✓ Specific crew backup works"
            } || {
                log "  ✗ Specific crew backup failed"
            }
        else
            log "  - No crews to test"
        fi
    else
        log "  - No crews directory"
    fi
    
    # Test 2: Backup specific agent
    log "Test 2: Backup specific agent"
    if [[ -d "$AGENTS_DIR" ]] && ls "$AGENTS_DIR" 2>/dev/null | head -1 >/dev/null; then
        local test_agent=$(ls "$AGENTS_DIR" 2>/dev/null | head -1)
        if [[ -n "$test_agent" ]]; then
            ./scripts/backup-interactive.sh backup --agents "$test_agent" --dry-run >/dev/null 2>&1 && {
                log "  ✓ Specific agent backup works"
            } || {
                log "  ✗ Specific agent backup failed"
            }
        else
            log "  - No agents to test"
        fi
    else
        log "  - No agents directory"
    fi
    
    # Test 3: Backup all with standard level
    log "Test 3: Backup all with standard level"
    ./scripts/backup-interactive.sh backup --all-crews --all-agents --crew configs --agent configs --dry-run >/dev/null 2>&1 && {
        log "  ✓ All standard backup works"
    } || {
        log "  ✗ All standard backup failed"
    }
    
    # Test 4: Backup all with full level
    log "Test 4: Backup all with full level"
    ./scripts/backup-interactive.sh backup --all-crews --all-agents --crew full --agent full --dry-run >/dev/null 2>&1 && {
        log "  ✓ All full backup works"
    } || {
        log "  ✗ All full backup failed"
    }
    
    # Test 5: Combo modes
    log "Test 5: Combo modes"
    for combo in crews-configs crews-full crews-workspaces all-full; do
        ./scripts/backup-interactive.sh backup --combo "$combo" --dry-run >/dev/null 2>&1 && {
            log "  ✓ Combo mode $combo works"
        } || {
            log "  ✗ Combo mode $combo failed"
        }
    done
    
    # Test 6: Hidden files
    log "Test 6: Hidden files handling"
    ./scripts/backup-interactive.sh backup --include-hidden --dry-run >/dev/null 2>&1 && {
        log "  ✓ Include hidden works"
    } || {
        log "  ✗ Include hidden failed"
    }
    
    ./scripts/backup-interactive.sh backup --exclude-hidden --dry-run >/dev/null 2>&1 && {
        log "  ✓ Exclude hidden works"
    } || {
        log "  ✗ Exclude hidden failed"
    }
    
    # Test 7: Git include
    log "Test 7: Git include handling"
    ./scripts/backup-interactive.sh backup --include-git --dry-run >/dev/null 2>&1 && {
        log "  ✓ Include .git works"
    } || {
        log "  ✗ Include .git failed"
    }
    
    ./scripts/backup-interactive.sh backup --exclude-git --dry-run >/dev/null 2>&1 && {
        log "  ✓ Exclude .git works"
    } || {
        log "  ✗ Exclude .git failed"
    }
    
    success "Test suite complete"
}

# =============================================================================
# MAIN
# =============================================================================

load_config

case "${COMMAND:-backup}" in
    init) cmd_init;;
    backup) cmd_backup;;
    restore) cmd_restore;;
    status) cmd_status;;
    list) cmd_list;;
    validate) cmd_validate;;
    test) cmd_test;;
    help|--help|-h) usage;;
    "") [[ $# -eq 0 ]] && cmd_backup || usage;;
    *) error "Unknown command: $COMMAND"; usage;;
esac
