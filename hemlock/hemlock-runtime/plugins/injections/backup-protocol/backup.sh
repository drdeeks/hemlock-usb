#!/usr/bin/env bash
# =============================================================================
# OpenClaw Backup — Full System Backup
# =============================================================================
#
# Complete backup of:
#   - <RUNTIME_ROOT>/agents/ (EVERY file, every agent, no exclusions)
#   - ~/.hermes/ (config, auth, env, hooks, cron, memories, plugins)
#   - <RUNTIME_ROOT>/docker/ (compose, Dockerfile, entrypoint)
#
# Sensitive files (.env, auth.json, .secrets/*) are encrypted at rest.
# Everything else is copied as-is.
#
# Usage:
#   ./backup.sh              # Full backup
#   ./backup.sh --init       # First-time setup (generates encryption key)
#   ./backup.sh --restore    # Restore from backup
#   ./backup.sh --status     # Show backup status
#
# =============================================================================

set -euo pipefail

BACKUP_DIR="${HOME}/.openclaw-backup"
OPENCLAW_DIR="${HOME}/.openclaw"
HERMES_DIR="${HOME}/.hermes"
KEY_FILE="${BACKUP_DIR}/.backup-key"
ENCRYPT_CMD="openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:${KEY_FILE}"
DECRYPT_CMD="openssl enc -d -aes-256-cbc -pbkdf2 -pass file:${KEY_FILE}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }
info() { echo -e "${CYAN}→${NC} $*"; }

# Git with deploy key
export GIT_SSH_COMMAND="ssh -i ${HOME}/.ssh/id_ed25519_openclaw_backup -o IdentitiesOnly=yes"

# ── Init ─────────────────────────────────────────────────────────────────────

cmd_init() {
    echo -e "${BOLD}${CYAN}OpenClaw Backup — First-Time Setup${NC}"
    echo ""

    if [ -f "$KEY_FILE" ]; then
        warn "Encryption key already exists at ${KEY_FILE}"
        return 1
    fi

    openssl rand -base64 32 > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    log "Encryption key generated: ${KEY_FILE}"
    echo ""
    echo -e "${BOLD}IMPORTANT:${NC} Back up this key separately!"
    echo "  Key location: ${KEY_FILE}"
    echo "  Key preview:  $(head -c 20 "$KEY_FILE")..."
    echo ""
    warn "Store a copy in your password manager, USB drive, or print it."
}

# ── Backup ───────────────────────────────────────────────────────────────────

cmd_backup() {
    echo -e "${BOLD}${CYAN}OpenClaw Backup — Running${NC}"
    echo ""

    if [ ! -f "$KEY_FILE" ]; then
        err "No encryption key found. Run: $0 --init"
        return 1
    fi

    cd "$BACKUP_DIR"
    git pull --rebase --quiet 2>/dev/null || true

    local changed=0

    # ── 0. Fix ownership (containers may create root-owned files) ─────────
    info "Fixing ownership on agent files..."
    local root_count
    root_count=$(find "${OPENCLAW_DIR}/agents/" -maxdepth 4 -user root -not -path '*/.git/*' 2>/dev/null | wc -l)
    if [ "$root_count" -gt 0 ]; then
        sudo chown -R "$(id -u):$(id -g)" "${OPENCLAW_DIR}/agents/" 2>/dev/null || warn "Could not fix ownership on ${root_count} file(s)"
        log "Fixed ownership on ${root_count} root-owned file(s)"
    fi

    # ── 1. Full copy of <RUNTIME_ROOT>/agents/ ──────────────────────────────
    info "Syncing agents (full copy)..."
    mkdir -p "${BACKUP_DIR}/agents"
    rsync -a --delete \
        --exclude='.git/' \
        --exclude='checkpoints/' \
        --exclude='.backups/' \
        --exclude='logs/' \
        "${OPENCLAW_DIR}/agents/" "${BACKUP_DIR}/agents/" 2>/dev/null
    log "Agents synced"

    # ── 2. Encrypt sensitive files in agents ─────────────────────────────
    info "Encrypting sensitive files..."
    local enc_count=0
    for agent_dir in "${BACKUP_DIR}"/agents/*/; do
        [ -d "$agent_dir" ] || continue
        local agent
        agent=$(basename "$agent_dir")
        [ "$agent" = ".scripts" ] && continue
        [ "$agent" = ".skills" ] && continue
        [ "$agent" = ".backups" ] && continue
        [ "$agent" = ".git" ] && continue

        # Encrypt .env
        if [ -f "${agent_dir}.env" ]; then
            $ENCRYPT_CMD -in "${agent_dir}.env" -out "${agent_dir}.env.enc" 2>/dev/null
            rm -f "${agent_dir}.env"
            enc_count=$((enc_count + 1))
        fi

        # Encrypt auth.json
        if [ -f "${agent_dir}auth.json" ]; then
            $ENCRYPT_CMD -in "${agent_dir}auth.json" -out "${agent_dir}auth.json.enc" 2>/dev/null
            rm -f "${agent_dir}auth.json"
            enc_count=$((enc_count + 1))
        fi

        # Encrypt .secrets directory contents
        if [ -d "${agent_dir}.secrets" ]; then
            for sf in "${agent_dir}.secrets"/*; do
                [ -f "$sf" ] || continue
                local sname
                sname=$(basename "$sf")
                [[ "$sname" == *.enc ]] && continue
                $ENCRYPT_CMD -in "$sf" -out "${sf}.enc" 2>/dev/null
                rm -f "$sf"
                enc_count=$((enc_count + 1))
            done
        fi
    done
    log "Encrypted ${enc_count} sensitive file(s)"

    # ── 3. Sync Docker config ───────────────────────────────────────────
    info "Syncing Docker config..."
    mkdir -p "${BACKUP_DIR}/docker"
    for f in docker-compose.yml Dockerfile entrypoint.sh; do
        if [ -f "${OPENCLAW_DIR}/docker/${f}" ]; then
            cp "${OPENCLAW_DIR}/docker/${f}" "${BACKUP_DIR}/docker/${f}"
        fi
    done
    # Copy patches and skills if they exist
    [ -d "${OPENCLAW_DIR}/docker/patches" ] && rsync -a "${OPENCLAW_DIR}/docker/patches/" "${BACKUP_DIR}/docker/patches/"
    [ -d "${OPENCLAW_DIR}/docker/skills" ] && rsync -a "${OPENCLAW_DIR}/docker/skills/" "${BACKUP_DIR}/docker/skills/"
    log "Docker config synced"

    # ── 4. Sync Hermes config ───────────────────────────────────────────
    info "Syncing Hermes config..."
    mkdir -p "${BACKUP_DIR}/hermes"

    # Config files
    for f in config.yaml auth.json .env; do
        if [ -f "${HERMES_DIR}/${f}" ]; then
            cp "${HERMES_DIR}/${f}" "${BACKUP_DIR}/hermes/${f}"
        fi
    done

    # Encrypt hermes sensitive files
    if [ -f "${BACKUP_DIR}/hermes/auth.json" ]; then
        $ENCRYPT_CMD -in "${BACKUP_DIR}/hermes/auth.json" -out "${BACKUP_DIR}/hermes/auth.json.enc" 2>/dev/null
        rm -f "${BACKUP_DIR}/hermes/auth.json"
    fi
    if [ -f "${BACKUP_DIR}/hermes/.env" ]; then
        $ENCRYPT_CMD -in "${BACKUP_DIR}/hermes/.env" -out "${BACKUP_DIR}/hermes/.env.enc" 2>/dev/null
        rm -f "${BACKUP_DIR}/hermes/.env"
    fi

    # Directories
    for d in hooks cron memories memory; do
        if [ -d "${HERMES_DIR}/${d}" ] && [ "$(ls -A "${HERMES_DIR}/${d}" 2>/dev/null)" ]; then
            mkdir -p "${BACKUP_DIR}/hermes/${d}"
            rsync -a "${HERMES_DIR}/${d}/" "${BACKUP_DIR}/hermes/${d}/"
        fi
    done

    # Plugins (full copy)
    if [ -d "${HERMES_DIR}/plugins" ]; then
        mkdir -p "${BACKUP_DIR}/hermes/plugins"
        rsync -a "${HERMES_DIR}/plugins/" "${BACKUP_DIR}/hermes/plugins/"
    fi

    log "Hermes config synced"

    # ── 5. Record timestamp ─────────────────────────────────────────────
    date -u +%Y-%m-%dT%H:%M:%SZ > "${BACKUP_DIR}/.last-backup"

    # ── 6. Commit and push ──────────────────────────────────────────────
    cd "$BACKUP_DIR"
    git add -A

    if git diff --cached --quiet 2>/dev/null; then
        log "No changes detected. Backup up to date."
        return 0
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    git commit -m "backup: ${timestamp}" --quiet

    if git push --quiet 2>&1; then
        log "Backup pushed to GitHub"
    else
        warn "Push failed — changes committed locally but not pushed"
        warn "Run 'git push' manually from ${BACKUP_DIR}"
    fi

    # ── Summary ─────────────────────────────────────────────────────────
    local total_files
    total_files=$(find "${BACKUP_DIR}" -type f | wc -l)
    local total_size
    total_size=$(du -sh "${BACKUP_DIR}" --exclude='.git' 2>/dev/null | cut -f1)

    echo ""
    log "Backup complete"
    echo "  Repo:    https://github.com/drdeeks/openclaw-backup"
    echo "  Local:   ${BACKUP_DIR}"
    echo "  Files:   ${total_files}"
    echo "  Size:    ${total_size}"
    echo "  Commit:  $(git log -1 --format='%h %s' 2>/dev/null)"
}

# ── Restore ──────────────────────────────────────────────────────────────────

cmd_restore() {
    echo -e "${BOLD}${CYAN}OpenClaw Backup — Restore${NC}"
    echo ""

    if [ ! -d "$BACKUP_DIR/agents" ]; then
        err "No backup data found at ${BACKUP_DIR}/agents/"
        return 1
    fi

    echo "Available agents:"
    for d in "${BACKUP_DIR}"/agents/*/; do
        [ -d "$d" ] || continue
        local name
        name=$(basename "$d")
        [[ "$name" == .* ]] && continue
        echo "  ${name}"
    done
    echo ""

    read -rp "Enter agent name to restore (or 'all'): " target

    if [ "$target" = "all" ]; then
        for d in "${BACKUP_DIR}"/agents/*/; do
            [ -d "$d" ] || continue
            local name
            name=$(basename "$d")
            [[ "$name" == .* ]] && continue
            _restore_agent "$name"
        done
        _restore_hermes
    else
        _restore_agent "$target"
        _restore_hermes
    fi
}

_restore_agent() {
    local agent="$1"
    local src="${BACKUP_DIR}/agents/${agent}"
    local dst="${OPENCLAW_DIR}/agents/${agent}"

    if [ ! -d "$src" ]; then
        err "No backup found for ${agent}"
        return 1
    fi

    info "Restoring ${agent}..."

    # Full copy
    mkdir -p "$dst"
    rsync -a "$src/" "$dst/"

    # Decrypt sensitive files
    if [ -f "$KEY_FILE" ]; then
        for enc in "${dst}"/*.enc; do
            [ -f "$enc" ] || continue
            local plain="${enc%.enc}"
            $DECRYPT_CMD -in "$enc" -out "$plain" 2>/dev/null && chmod 600 "$plain"
            rm -f "$enc"
        done

        if [ -d "${dst}/.secrets" ]; then
            for enc in "${dst}/.secrets"/*.enc; do
                [ -f "$enc" ] || continue
                local plain="${enc%.enc}"
                $DECRYPT_CMD -in "$enc" -out "$plain" 2>/dev/null && chmod 600 "$plain"
                rm -f "$enc"
            done
        fi
    else
        warn "No encryption key — .env, auth.json, .secrets will remain encrypted"
    fi

    log "Restored ${agent}"
}

_restore_hermes() {
    local src="${BACKUP_DIR}/hermes"
    [ -d "$src" ] || return 0

    info "Restoring Hermes config..."

    mkdir -p "${HERMES_DIR}"

    # Copy config
    [ -f "${src}/config.yaml" ] && cp "${src}/config.yaml" "${HERMES_DIR}/config.yaml"

    # Decrypt and copy sensitive files
    if [ -f "$KEY_FILE" ]; then
        for enc in "${src}"/*.enc; do
            [ -f "$enc" ] || continue
            local basename
            basename=$(basename "$enc" .enc)
            $DECRYPT_CMD -in "$enc" -out "${HERMES_DIR}/${basename}" 2>/dev/null && chmod 600 "${HERMES_DIR}/${basename}"
        done
    fi

    # Copy directories
    for d in hooks cron memories memory plugins; do
        if [ -d "${src}/${d}" ]; then
            mkdir -p "${HERMES_DIR}/${d}"
            rsync -a "${src}/${d}/" "${HERMES_DIR}/${d}/"
        fi
    done

    log "Hermes config restored"
}

# ── Status ───────────────────────────────────────────────────────────────────

cmd_status() {
    echo -e "${BOLD}${CYAN}OpenClaw Backup Status${NC}"
    echo ""

    cd "$BACKUP_DIR" 2>/dev/null || { err "Backup dir not found: ${BACKUP_DIR}"; return 1; }

    local last_backup
    last_backup=$(cat .last-backup 2>/dev/null || echo "never")

    echo "  Repo:         $(git remote get-url origin 2>/dev/null || echo 'no remote')"
    echo "  Branch:       $(git branch --show-current 2>/dev/null || echo 'unknown')"
    echo "  Last backup:  ${last_backup}"
    echo "  Last commit:  $(git log -1 --format='%h %ai %s' 2>/dev/null || echo 'no commits')"
    echo "  Encryption:   $([ -f "$KEY_FILE" ] && echo 'key present' || echo 'KEY MISSING')"
    echo ""

    echo "  Agents:"
    for d in agents/*/; do
        [ -d "$d" ] || continue
        local name
        name=$(basename "$d")
        [[ "$name" == .* ]] && continue
        local count
        count=$(find "$d" -type f 2>/dev/null | wc -l)
        local size
        size=$(du -sh "$d" 2>/dev/null | cut -f1)
        echo "    ${name}: ${count} files, ${size}"
    done

    echo ""
    echo "  Hermes config:"
    [ -d hermes ] && echo "    $(find hermes/ -type f 2>/dev/null | wc -l) files, $(du -sh hermes/ 2>/dev/null | cut -f1)" || echo "    not backed up"

    echo ""
    echo "  Docker config:"
    [ -d docker ] && echo "    $(find docker/ -type f 2>/dev/null | wc -l) files" || echo "    not backed up"

    echo ""
    echo "  Total: $(find . -type f -not -path './.git/*' 2>/dev/null | wc -l) files, $(du -sh --exclude='.git' . 2>/dev/null | cut -f1)"
}

# ── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
    --init|-i)    cmd_init ;;
    --restore|-r) cmd_restore ;;
    --status|-s)  cmd_status ;;
    --help|-h)
        echo "Usage: $0 [--init|--restore|--status]"
        echo "  (no args)    Run backup"
        echo "  --init       First-time setup"
        echo "  --restore    Restore from backup"
        echo "  --status     Show backup status"
        ;;
    *)            cmd_backup ;;
esac
