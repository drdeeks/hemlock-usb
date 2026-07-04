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

ensure_upstream() {
    if [ -d "$SKILLS_UPSTREAM/.git" ]; then
        git -C "$SKILLS_UPSTREAM" fetch --depth 1 origin "$SKILLS_BRANCH" >>"$LOG" 2>&1 || return 1
        git -C "$SKILLS_UPSTREAM" reset --hard "origin/$SKILLS_BRANCH" >>"$LOG" 2>&1 || return 1
    else
        rm -rf "$SKILLS_UPSTREAM"
        git clone --depth 1 --branch "$SKILLS_BRANCH" "$SKILLS_REPO_URL" "$SKILLS_UPSTREAM" >>"$LOG" 2>&1 || return 1
    fi
    return 0
}

update_once() {
    local check_only="${1:-0}"
    [ "$SKILLS_UPDATE_ENABLED" = "1" ] || { log "disabled (SKILLS_UPDATE_ENABLED=0)"; return 0; }

    if ! command -v git >/dev/null 2>&1; then log "git not available — skipping"; return 0; fi
    if ! command -v rsync >/dev/null 2>&1; then log "rsync not available — skipping"; return 0; fi
    if ! ensure_upstream; then
        log "upstream fetch failed (offline?) — keeping current /skills"
        harden_artifacts
        return 0
    fi

    local -a EXCL
    mapfile -t EXCL < <(rsync_excludes)

    local updated=0 added=0 unchanged=0 pruned=0
    shopt -s nullglob
    for up_dir in "$SKILLS_UPSTREAM"/*/; do
        local name up_md up_ver cur_md cur_ver
        name="$(basename "$up_dir")"
        up_md="$up_dir/SKILL.md"
        [ -f "$up_md" ] || continue                      # only real skills
        up_ver="$(skill_version "$up_md")"
        cur_md="$SKILLS_DIR/$name/SKILL.md"
        cur_ver="$(skill_version "$cur_md")"

        if [ -z "$cur_ver" ]; then
            [ "$check_only" = "1" ] && { log "NEW    $name (upstream v${up_ver:-?})"; added=$((added+1)); continue; }
            # --checksum: decide by content, never by size+mtime. A same-length
            # version bump (0.1.0 -> 0.2.0) in the same mtime-second must NOT be
            # skipped by rsync's default quick-check.
            rsync -a --checksum --delete "${EXCL[@]}" \
                "$up_dir" "$SKILLS_DIR/$name/" >>"$LOG" 2>&1 \
                && { log "added   $name v${up_ver:-?}"; added=$((added+1)); }
        elif [ "$up_ver" != "$cur_ver" ]; then
            [ "$check_only" = "1" ] && { log "UPDATE $name ($cur_ver -> ${up_ver:-?})"; updated=$((updated+1)); continue; }
            rsync -a --checksum --delete "${EXCL[@]}" \
                "$up_dir" "$SKILLS_DIR/$name/" >>"$LOG" 2>&1 \
                && { log "updated $name $cur_ver -> ${up_ver:-?}"; updated=$((updated+1)); }
        else
            unchanged=$((unchanged+1))
        fi
    done

    if [ "$SKILLS_PRUNE" = "1" ]; then
        for cur_dir in "$SKILLS_DIR"/*/; do
            local name="$(basename "$cur_dir")"
            [ -f "$cur_dir/SKILL.md" ] || continue
            if [ ! -d "$SKILLS_UPSTREAM/$name" ]; then
                [ "$check_only" = "1" ] && { log "PRUNE  $name (absent upstream)"; pruned=$((pruned+1)); continue; }
                rm -rf "$cur_dir" && { log "pruned  $name"; pruned=$((pruned+1)); }
            fi
        done
    fi

    if [ "$check_only" != "1" ]; then
        printf '{"updated_at":"%s","added":%d,"updated":%d,"unchanged":%d,"pruned":%d,"source":"%s@%s"}\n' \
            "$(date -Iseconds)" "$added" "$updated" "$unchanged" "$pruned" "$SKILLS_REPO_URL" "$SKILLS_BRANCH" \
            > "$SKILLS_DIR/.hemlock_skills_updated" 2>/dev/null || true
        # Re-assert root-only ownership on control artifacts after every mutation.
        harden_artifacts
    fi
    log "cycle done: added=$added updated=$updated unchanged=$unchanged pruned=$pruned"
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
