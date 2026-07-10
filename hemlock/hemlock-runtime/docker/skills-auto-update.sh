#!/bin/bash
# =============================================================================
# Hemlock Skills Auto-Update (runtime daily pull + self-healing supervisor)
# =============================================================================
# Keeps the container's /skills database current with the canonical upstream
# repo (drdeeks/skills) without any host coupling: it pulls over the network
# into a container-internal clone, version-checks each skill against what /skills
# already has, and copies in anything new or updated as REAL FILES (never
# symlinks). Fully fail-soft — if the network or git is unavailable, the current
# /skills set is left untouched and the next cycle retries.
#
# This replaces the build-time git clone (disabled under CL-027) with a runtime
# mechanism, so the image stays self-contained and offline-runnable while the
# skill database still refreshes daily when connectivity exists.
#
# GUARDRAIL INVARIANTS (enforced here, not optional):
#   * Control artifacts are NEVER overwritten by an upstream pull. The rsync
#     excludes cover .git, .monitor.json, .monitor-state.json, .loop.lock,
#     .loop-log.jsonl, .gate.json and __pycache__ so local watcher/gate state
#     and git history survive every sync.
#   * Control artifacts are permission-hardened to root:root, mode 600 (script
#     itself 755) after every cycle, so only root can modify the guardrail state.
#   * The daemon is SELF-HEALING: a supervisor restarts the update loop on any
#     unexpected exit. It stops ONLY on an explicit stop (the --stop flag file
#     or SIGUSR1), or on container shutdown (SIGTERM/SIGINT). It never simply
#     dies and stays dead.
#
# Modes:
#   --once        run a single update cycle and exit
#   --check       report version deltas only; change nothing
#   --daemon      run one supervised, self-healing update loop in the FOREGROUND
#                 (--once immediately, then every $SKILLS_UPDATE_INTERVAL)
#   --supervise   same as --daemon but wrapped in the restart supervisor
#                 (this is what the entrypoint launches); alias kept explicit
#   --stop        request an explicit, permanent stop of a running supervisor
#   --harden      re-apply root-only permissions to control artifacts and exit
#
# Env (all optional, sensible defaults):
#   SKILLS_UPDATE_ENABLED    1|0            default 1
#   SKILLS_REPO_URL          git URL        default https://github.com/drdeeks/skills.git
#   SKILLS_BRANCH            branch          default main
#   SKILLS_DIR               dest            default /skills
#   SKILLS_UPSTREAM          clone dir       default /opt/skills-upstream
#   SKILLS_UPDATE_INTERVAL   seconds         default 86400 (daily)
#   SKILLS_RESTART_DELAY     seconds         default 5 (supervisor backoff)
#   SKILLS_PRUNE             1|0            default 0 (do NOT delete skills absent upstream)
# =============================================================================
set -uo pipefail

SKILLS_UPDATE_ENABLED="${SKILLS_UPDATE_ENABLED:-1}"
SKILLS_REPO_URL="${SKILLS_REPO_URL:-https://github.com/drdeeks/skills.git}"
SKILLS_BRANCH="${SKILLS_BRANCH:-main}"
SKILLS_DIR="${SKILLS_DIR:-/skills}"
SKILLS_UPSTREAM="${SKILLS_UPSTREAM:-/opt/skills-upstream}"
SKILLS_UPDATE_INTERVAL="${SKILLS_UPDATE_INTERVAL:-86400}"
SKILLS_RESTART_DELAY="${SKILLS_RESTART_DELAY:-5}"
SKILLS_PRUNE="${SKILLS_PRUNE:-0}"
LOG="${SKILLS_UPDATE_LOG:-/var/log/hemlock-skills-sync.log}"
STOP_FLAG="${SKILLS_UPDATE_STOP_FLAG:-/run/hemlock-skills-update.stop}"

# ── Operator-added skill sources (multi-repo) ────────────────────────────────
# Beyond the canonical repo, operators register extra git skill repos via the
# menu ("Skill Sources"). Each is labelled by github owner ("<owner>-skills")
# and its skills sync into $SKILLS_DIR alongside the rest. Resolve order for the
# list file: env, then the volume-local file, then the mounted config file.
SKILLS_SOURCES_FILE="${SKILLS_SOURCES_FILE:-}"
resolve_sources_file() {
    local c
    for c in "$SKILLS_SOURCES_FILE" "$SKILLS_DIR/.skill-sources" "/config/skill-sources.list"; do
        [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
    done
    return 0
}
# Owner slug from a git URL. github.com/OWNER/REPO(.git) or git@host:OWNER/REPO.
source_owner() {
    local u="$1"
    u="${u%.git}"; u="${u#*://}"; u="${u#*@}"
    u="$(printf '%s' "$u" | tr ':' '/')"; u="${u%/}"; u="${u%/*}"
    local owner="${u##*/}"
    [ -n "$owner" ] && printf '%s' "$owner" || printf 'source'
}
# Emit "url<TAB>branch" for the canonical repo first, then each list-file line
# ("<url> [branch]", '#' comments and blanks ignored).
collect_sources() {
    printf '%s\t%s\n' "$SKILLS_REPO_URL" "$SKILLS_BRANCH"
    local f; f="$(resolve_sources_file)"
    [ -n "$f" ] || return 0
    local line url br
    while IFS= read -r line; do
        line="${line%%#*}"
        # shellcheck disable=SC2086
        set -- $line
        url="${1:-}"; br="${2:-$SKILLS_BRANCH}"
        [ -n "$url" ] || continue
        [ "$url" = "$SKILLS_REPO_URL" ] && continue   # de-dup the canonical repo
        printf '%s\t%s\n' "$url" "$br"
    done < "$f"
}

# Control artifacts that must never be clobbered by an upstream pull and must be
# permission-hardened to root-only. Kept in one place so the rsync excludes and
# the hardening pass can never drift apart.
CONTROL_FILES=(
    ".git"
    ".monitor.json"
    ".monitor-state.json"
    ".loop.lock"
    ".loop-log.jsonl"
    ".gate.json"
    "__pycache__"
)

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [skills-update] $*" | tee -a "$LOG" >&2; }

# Build the rsync --exclude flags from CONTROL_FILES (single source of truth).
rsync_excludes() {
    local f
    for f in "${CONTROL_FILES[@]}"; do
        printf -- '--exclude=%s\n' "$f"
    done
}

# Extract the frontmatter `version:` from a SKILL.md (portable, no deps).
skill_version() {
    local md="$1"
    [ -f "$md" ] || { echo ""; return; }
    sed -n 's/^version:[[:space:]]*["'\'']\{0,1\}\([^"'\''[:space:]]*\).*/\1/p' "$md" | head -n1
}

# Permission-harden the guardrail/monitor control artifacts so ONLY root can
# modify them. Runs after every sync cycle and can be invoked standalone
# (--harden). Fail-soft: chown/chmod best-effort (may be a rootless test env).
harden_artifacts() {
    local f
    # Root-level control files (the canonical .monitor.json / manifest live here).
    for f in "$SKILLS_DIR"/.monitor.json "$SKILLS_DIR"/.monitor-state.json \
             "$SKILLS_DIR"/.loop-log.jsonl "$SKILLS_DIR"/.gate.json \
             "$SKILLS_DIR"/.skill-manifest.json; do
        [ -e "$f" ] || continue
        chown root:root "$f" 2>/dev/null || true
        chmod 600 "$f" 2>/dev/null || true
    done
    # Per-skill control files anywhere under /skills.
    while IFS= read -r -d '' f; do
        chown root:root "$f" 2>/dev/null || true
        chmod 600 "$f" 2>/dev/null || true
    done < <(find "$SKILLS_DIR" -maxdepth 3 -type f \
                \( -name '.monitor.json'      -o -name '.monitor-state.json' \
                -o -name '.loop-log.jsonl'    -o -name '.gate.json' \) \
                -print0 2>/dev/null)
    # The upstream clone's .git: root-owned, not group/other writable.
    if [ -d "$SKILLS_UPSTREAM/.git" ]; then
        chown -R root:root "$SKILLS_UPSTREAM/.git" 2>/dev/null || true
        chmod -R go-w      "$SKILLS_UPSTREAM/.git" 2>/dev/null || true
    fi
    # The updater itself: root-owned, world-readable/executable but root-only write.
    chown root:root "$0" 2>/dev/null || true
    chmod 755       "$0" 2>/dev/null || true
}

ensure_upstream_at() {
    local url="$1" branch="$2" dir="$3"
    if [ -d "$dir/.git" ]; then
        git -C "$dir" fetch --depth 1 origin "$branch" >>"$LOG" 2>&1 || return 1
        git -C "$dir" reset --hard "origin/$branch" >>"$LOG" 2>&1 || return 1
    else
        rm -rf "$dir"
        git clone --depth 1 --branch "$branch" "$url" "$dir" >>"$LOG" 2>&1 || return 1
    fi
    return 0
}

# Sync every real skill under one upstream root into $SKILLS_DIR, version-gated.
# Accumulates into the SYNC_* globals (reset by the caller); $label tags logs.
sync_tree() {
    local up_root="$1" check_only="$2" label="$3"
    local -a EXCL; mapfile -t EXCL < <(rsync_excludes)
    shopt -s nullglob
    local up_dir name up_md up_ver cur_md cur_ver
    for up_dir in "$up_root"/*/; do
        name="$(basename "$up_dir")"
        up_md="$up_dir/SKILL.md"
        [ -f "$up_md" ] || continue                      # only real skills
        up_ver="$(skill_version "$up_md")"
        cur_md="$SKILLS_DIR/$name/SKILL.md"
        cur_ver="$(skill_version "$cur_md")"
        if [ -z "$cur_ver" ]; then
            [ "$check_only" = "1" ] && { log "NEW    $name ($label v${up_ver:-?})"; SYNC_ADDED=$((SYNC_ADDED+1)); continue; }
            # --checksum: decide by content, never size+mtime, so a same-length
            # version bump in the same mtime-second is never skipped.
            rsync -a --checksum --delete "${EXCL[@]}" \
                "$up_dir" "$SKILLS_DIR/$name/" >>"$LOG" 2>&1 \
                && { log "added   $name v${up_ver:-?} [$label]"; SYNC_ADDED=$((SYNC_ADDED+1)); }
        elif [ "$up_ver" != "$cur_ver" ]; then
            [ "$check_only" = "1" ] && { log "UPDATE $name ($cur_ver -> ${up_ver:-?}) [$label]"; SYNC_UPDATED=$((SYNC_UPDATED+1)); continue; }
            rsync -a --checksum --delete "${EXCL[@]}" \
                "$up_dir" "$SKILLS_DIR/$name/" >>"$LOG" 2>&1 \
                && { log "updated $name $cur_ver -> ${up_ver:-?} [$label]"; SYNC_UPDATED=$((SYNC_UPDATED+1)); }
        else
            SYNC_UNCHANGED=$((SYNC_UNCHANGED+1))
        fi
    done
}

update_once() {
    local check_only="${1:-0}"
    [ "$SKILLS_UPDATE_ENABLED" = "1" ] || { log "disabled (SKILLS_UPDATE_ENABLED=0)"; return 0; }

    if ! command -v git >/dev/null 2>&1; then log "git not available — skipping"; return 0; fi
    if ! command -v rsync >/dev/null 2>&1; then log "rsync not available — skipping"; return 0; fi

    SYNC_ADDED=0 SYNC_UPDATED=0 SYNC_UNCHANGED=0
    local -a SRC_URLS=() SRC_BRS=() SRC_NSS=()
    local url br n_sources=0
    while IFS=$'\t' read -r url br; do
        [ -n "$url" ] || continue
        SRC_URLS+=("$url"); SRC_BRS+=("$br"); SRC_NSS+=("$(source_owner "$url")")
        n_sources=$((n_sources+1))
    done < <(collect_sources)

    local i any_ok=0 updir ns
    for ((i=0; i<n_sources; i++)); do
        url="${SRC_URLS[$i]}"; br="${SRC_BRS[$i]}"; ns="${SRC_NSS[$i]}"
        updir="$SKILLS_UPSTREAM/$ns"
        if ! ensure_upstream_at "$url" "$br" "$updir"; then
            log "fetch failed: ${ns}-skills <$url> (offline?) — skipping"
            continue
        fi
        any_ok=1
        sync_tree "$updir" "$check_only" "${ns}-skills"
    done

    if [ "$any_ok" = "0" ]; then
        log "no sources reachable (offline?) — keeping current /skills"
        harden_artifacts
        return 0
    fi

    # Prune only makes sense against a single authoritative source; with several
    # sources a skill from one looks "absent" in the others, so we skip it.
    if [ "$SKILLS_PRUNE" = "1" ] && [ "$check_only" != "1" ]; then
        if [ "$n_sources" = "1" ]; then
            local cur_dir name
            for cur_dir in "$SKILLS_DIR"/*/; do
                name="$(basename "$cur_dir")"
                [ -f "$cur_dir/SKILL.md" ] || continue
                if [ ! -d "$SKILLS_UPSTREAM/${SRC_NSS[0]}/$name" ]; then
                    rm -rf "$cur_dir" && log "pruned  $name"
                fi
            done
        else
            log "prune skipped: multiple sources active (would misclassify cross-source skills)"
        fi
    fi

    if [ "$check_only" != "1" ]; then
        printf '{"updated_at":"%s","added":%d,"updated":%d,"unchanged":%d,"sources":%d}\n' \
            "$(date -Iseconds)" "$SYNC_ADDED" "$SYNC_UPDATED" "$SYNC_UNCHANGED" "$n_sources" \
            > "$SKILLS_DIR/.hemlock_skills_updated" 2>/dev/null || true
        # Re-assert root-only ownership on control artifacts after every mutation.
        harden_artifacts
    fi
    log "cycle done: sources=$n_sources added=$SYNC_ADDED updated=$SYNC_UPDATED unchanged=$SYNC_UNCHANGED"
    return 0
}

# ---------------------------------------------------------------------------
# Self-healing daemon.
#
# run_loop() is the actual work loop. It is deliberately crash-resistant: each
# cycle runs in a subshell so a fault in one cycle can never kill the loop, and
# the loop only leaves on an explicit stop.
#
# supervise() wraps run_loop so that even a hard crash of the loop process
# (OOM-kill of a child, unexpected exit, etc.) is caught and the loop is
# restarted. The ONLY things that stop it permanently are:
#   * the explicit stop flag ($STOP_FLAG), created by `--stop`, or
#   * SIGUSR1 (explicit programmatic stop), or
#   * SIGTERM / SIGINT (container shutdown — legitimate).
# Any other exit is treated as a fault and self-healed by restarting.
# ---------------------------------------------------------------------------

_STOP_REQUESTED=0
request_stop()      { _STOP_REQUESTED=1; log "explicit stop signal received"; }
graceful_shutdown() { _STOP_REQUESTED=1; log "shutdown signal received (container stop)"; }

run_loop() {
    log "loop start: pulling $SKILLS_REPO_URL@$SKILLS_BRANCH every ${SKILLS_UPDATE_INTERVAL}s"
    while :; do
        [ -f "$STOP_FLAG" ] && { log "stop flag present — loop exiting"; return 0; }
        [ "$_STOP_REQUESTED" = "1" ] && { log "stop requested — loop exiting"; return 0; }
        # Isolate each cycle so a crash inside never takes down the loop.
        ( update_once 0 ) || log "cycle raised an error — continuing (self-healing)"
        # Interruptible sleep so a stop is honored promptly.
        local slept=0
        while [ "$slept" -lt "$SKILLS_UPDATE_INTERVAL" ]; do
            [ -f "$STOP_FLAG" ] && return 0
            [ "$_STOP_REQUESTED" = "1" ] && return 0
            sleep 1
            slept=$((slept+1))
        done
    done
}

supervise() {
    # Explicit-stop signal (programmatic) and container-shutdown signals.
    trap request_stop USR1
    trap graceful_shutdown TERM INT

    mkdir -p "$(dirname "$STOP_FLAG")" 2>/dev/null || true
    # A fresh supervisor start clears any stale stop request.
    rm -f "$STOP_FLAG" 2>/dev/null || true

    log "supervisor start (self-healing; restart backoff ${SKILLS_RESTART_DELAY}s)"
    while :; do
        if [ -f "$STOP_FLAG" ] || [ "$_STOP_REQUESTED" = "1" ]; then
            log "supervisor exiting (explicit stop)"
            return 0
        fi
        # Run the loop in a child so we can catch its exit and restart it.
        run_loop &
        local child=$!
        wait "$child"
        local code=$?
        if [ -f "$STOP_FLAG" ] || [ "$_STOP_REQUESTED" = "1" ]; then
            log "supervisor exiting (explicit stop; loop code $code)"
            return 0
        fi
        log "loop exited unexpectedly (code $code) — restarting in ${SKILLS_RESTART_DELAY}s (self-healing)"
        sleep "$SKILLS_RESTART_DELAY"
    done
}

request_explicit_stop() {
    mkdir -p "$(dirname "$STOP_FLAG")" 2>/dev/null || true
    : > "$STOP_FLAG" 2>/dev/null || { echo "cannot write stop flag: $STOP_FLAG" >&2; exit 1; }
    log "explicit stop requested via flag: $STOP_FLAG"
}

main() {
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
    case "${1:---once}" in
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -60
            ;;
        --check)     update_once 1 ;;
        --once)      update_once 0 ;;
        --harden)    harden_artifacts; log "control artifacts hardened (root-only)" ;;
        --stop)      request_explicit_stop ;;
        --daemon|--supervise) supervise ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
}

main "$@"
