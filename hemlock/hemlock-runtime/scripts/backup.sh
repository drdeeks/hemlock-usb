#!/bin/bash
# =============================================================================
# Hemlock — backup.sh  (T16: consolidated backup & restore, TWO modes)
# =============================================================================
# ONE tool, you pick the mode:
#
#   FULL   — back up the ENTIRE persistent data state in one shot (all agents,
#            all crews, the global knowledge store, and runtime config). This is
#            the "don't-think-just-protect-everything" button.
#
#   CUSTOM — user-controlled, granular: back up ONE volume (an agent or crew,
#            or @knowledge) with a chosen destination, chosen contents, and an
#            optional schedule. You are never forced to take the whole state.
#
# Both encrypt sensitive material at rest (.secret-key / .env / auth.json) with
# AES-256-CBC / PBKDF2; per-agent .secrets/*.enc are already encrypted on disk.
# Scheduling is opt-in: a config field + `backup.sh run-due` that YOUR cron
# calls — no always-on daemon.
#
#   backup.sh init                              generate the backup encryption key
#   backup.sh full   [--dest D] [--encrypt|--no-encrypt]         ENTIRE state
#   backup.sh list-volumes                      show backup-able volumes
#   backup.sh backup <vol|--all> [--dest D] [--include a,b] [--encrypt|--no-encrypt]
#   backup.sh restore <archive> [--into <vol|--data-root DIR>] [--dry-run] [--force]
#   backup.sh status [--dest D]                 list existing backups + manifests
#   backup.sh config [get|set-default|set-volume ...]
#   backup.sh run-due                           back up volumes whose schedule is due
#
# Include categories (CUSTOM): memory identity sessions skills projects
#   knowledge tools secrets logs   (or `all`). Default: everything but caches.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/helpers.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/helpers.sh" >/dev/null 2>&1 || true
fi
: "${RUNTIME_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"
: "${AGENTS_DIR:=$RUNTIME_ROOT/agents}"
: "${CREWS_DIR:=$RUNTIME_ROOT/crews}"
: "${CONFIG_DIR:=$RUNTIME_ROOT/config}"
KNOWLEDGE_DIR="${HEMLOCK_KNOWLEDGE_DIR:-$RUNTIME_ROOT/knowledge}"

BACKUP_CONFIG="$CONFIG_DIR/backup.json"
BACKUP_KEY="$CONFIG_DIR/.backup-key"
DEFAULT_DEST="${HEMLOCK_BACKUP_DEST:-$RUNTIME_ROOT/backups}"
DEFAULT_INCLUDE="memory,identity,sessions,skills,projects,knowledge,tools,secrets"
# What "the entire persistent data state" means at the CONTAINER layer
# (override with HEMLOCK_FULL_TARGETS).
FULL_TARGETS="${HEMLOCK_FULL_TARGETS:-agents crews knowledge config}"

# ── Ventoy / USB persistence layer (the OUTER persistent data state) ─────────
# On a Ventoy USB deploy the real persistence is a set of delegated image files
# under <mount>/persistence/ — one per ISO/purpose (hemlock.dat, tooling.dat,
# models.dat, docker.dat, <os>-persistence.dat) — mapped by <mount>/ventoy/
# ventoy.json. They're separated precisely so each can be backed up / restored
# as its own unit. Refs: `@ventoy` (ventoy.json + ALL .dat = the entire USB
# state) or `dat:<name>` (one image, e.g. dat:hemlock).
VENTOY_MOUNT=""; PERSIST_DIR=""; VENTOY_JSON=""
_detect_ventoy() {
    VENTOY_MOUNT=""
    if [ -n "${HEMLOCK_VENTOY_MOUNT:-}" ] && [ -d "$HEMLOCK_VENTOY_MOUNT" ]; then
        VENTOY_MOUNT="$HEMLOCK_VENTOY_MOUNT"
    elif [ -n "${UCA_PRIMARY_PERSISTENCE:-}" ] && [ -f "${UCA_PRIMARY_PERSISTENCE:-}" ]; then
        VENTOY_MOUNT="$(dirname "$(dirname "$UCA_PRIMARY_PERSISTENCE")")"
    else
        local m
        for m in /media/*/* /run/media/*/* /mnt/*; do
            [ -d "$m" ] || continue
            if [ -f "$m/ventoy/ventoy.json" ] || ls "$m"/persistence/*.dat >/dev/null 2>&1; then
                VENTOY_MOUNT="$m"; break
            fi
        done
    fi
    [ -z "$VENTOY_MOUNT" ] && return 1
    PERSIST_DIR="$VENTOY_MOUNT/persistence"
    VENTOY_JSON="$VENTOY_MOUNT/ventoy/ventoy.json"
    [ -d "$PERSIST_DIR" ] || [ -f "$VENTOY_JSON" ]
}
_list_dats() { ls "$PERSIST_DIR"/*.dat 2>/dev/null; }

# You cannot back up the persistence image you are CURRENTLY BOOTED INTO — it is
# loop-mounted and live, so a copy would be inconsistent (or is the very fs you
# are running from). Detect an in-use .dat via losetup (best-effort).
_dat_in_use() {   # $1=path to .dat  → 0 if currently attached to a loop device
    command -v losetup >/dev/null 2>&1 || return 1
    losetup -j "$1" 2>/dev/null | grep -q . && return 0
    return 1
}
_can_detect_use() { command -v losetup >/dev/null 2>&1; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${CYAN}→${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

PY="$(command -v python3 || command -v python)"
now_ts() { date -u +%Y%m%dT%H%M%SZ; }

TAR_EXCLUDES=(--exclude='__pycache__' --exclude='*.pyc' --exclude='.git'
              --exclude='node_modules' --exclude='sessions/dumps' --exclude='*.gz'
              --exclude='*.gguf' --exclude='*.safetensors' --exclude='backups')

ENC="false"; FINAL=""
_encrypt_or_move() {   # $1=plain tarball  $2=want(yes/no) -> sets globals FINAL + ENC
    local tarball="$1" want="$2"
    ENC="false"
    if [ "$want" = "yes" ] && [ -f "$BACKUP_KEY" ]; then
        if openssl enc -aes-256-cbc -pbkdf2 -salt -in "$tarball" -out "$tarball.enc" -pass "file:$BACKUP_KEY" 2>/dev/null; then
            rm -f "$tarball"; ENC="true"; FINAL="$tarball.enc"; return
        fi
        warn "encryption failed — keeping unencrypted"
    elif [ "$want" = "yes" ]; then
        warn "encryption requested but no key — run: backup.sh init  (writing UNENCRYPTED)"
    fi
    FINAL="$tarball"
}

_write_manifest() {  # $1=manifest $2=mode $3=scope $4=include $5=enc $6=archive $7=size $8=source
    "$PY" - "$@" <<'PY'
import json, sys
mf, mode, scope, inc, enc, fname, size, src = sys.argv[1:9]
json.dump({"mode": mode, "scope": scope, "timestamp": fname.split("__")[-1].split(".")[0],
           "include": inc.split(",") if inc else [], "encrypted": enc == "true",
           "archive": fname, "size": size, "source": src},
          open(mf, "w"), indent=2)
PY
}

# ── volumes ──────────────────────────────────────────────────────────────────
_vol_path() {
    case "$1" in
        @knowledge) echo "$KNOWLEDGE_DIR" ;;
        crew:*)     echo "$CREWS_DIR/${1#crew:}" ;;
        *)          if   [ -d "$AGENTS_DIR/$1" ]; then echo "$AGENTS_DIR/$1"
                    elif [ -d "$CREWS_DIR/$1" ];  then echo "$CREWS_DIR/$1"
                    else echo ""; fi ;;
    esac
}
_all_volumes() {
    for d in "$AGENTS_DIR"/*/; do [ -d "$d" ] || continue
        case "$(basename "$d")" in active|archive|workspace-template|.*) continue ;; esac
        echo "$(basename "$d")"; done
    for d in "$CREWS_DIR"/*/; do [ -d "$d" ] || continue
        case "$(basename "$d")" in active|archive|.*) continue ;; esac
        echo "crew:$(basename "$d")"; done
}
list_volumes() {
    info "Agents:"; for v in $(_all_volumes); do [[ "$v" == crew:* ]] || echo "  $v"; done
    info "Crews (ref as crew:<name>):"; for v in $(_all_volumes); do [[ "$v" == crew:* ]] && echo "  $v"; done
    info "Global:"; [ -d "$KNOWLEDGE_DIR" ] && echo "  @knowledge   (runtime-root global knowledge store)"
    if _detect_ventoy; then
        info "Ventoy USB persistence ($VENTOY_MOUNT):  (ref as @ventoy or dat:<name>)"
        echo "  @ventoy      ventoy.json + ALL .dat = entire USB persistent state"
        local d; while IFS= read -r d; do [ -n "$d" ] && echo "  dat:$(basename "$d" .dat)   ($(du -h "$d" 2>/dev/null | cut -f1))"; done < <(_list_dats)
        [ -f "$VENTOY_JSON" ] && echo "  (ventoy.json present)"
    fi
}

_include_paths() {  # $1=include csv  $2=nameref out
    local -n _out=$2; _out=(); IFS=',' read -ra cats <<< "$1"
    for c in "${cats[@]}"; do case "$c" in
        all)       _out=(.); return ;;
        memory)    _out+=(memory MEMORY.md) ;;
        identity)  _out+=(SOUL.md IDENTITY.md USER.md AGENTS.md TOOLS.md HEARTBEAT.md) ;;
        sessions)  _out+=(sessions) ;;
        skills)    _out+=(skills) ;;
        projects)  _out+=(projects) ;;
        knowledge) _out+=(knowledge inbox links.json index.json CAPTURE-LOG.md) ;;
        tools)     _out+=(tools) ;;
        secrets)   _out+=(.secrets .secret-key) ;;
        logs)      _out+=(logs) ;;
        *)         warn "unknown include category: $c (skipped)" ;;
    esac; done
}
_has_sensitive() { case ",$1," in *,secrets,*|*,all,*) return 0 ;; esac; return 1; }

# ── config (argv-safe) ───────────────────────────────────────────────────────
_ensure_config() {
    mkdir -p "$CONFIG_DIR"; [ -f "$BACKUP_CONFIG" ] && return 0
    "$PY" - "$BACKUP_CONFIG" "$DEFAULT_DEST" "$DEFAULT_INCLUDE" <<'PY'
import json, sys
cfg, dest, inc = sys.argv[1:4]
json.dump({"version":"1.0.0","default_destination":dest,"default_include":inc.split(","),
           "encrypt_when_sensitive":True,"volumes":{}}, open(cfg,"w"), indent=2)
PY
}
_cfg_get() {
    "$PY" - "$BACKUP_CONFIG" "$1" "$2" <<'PY'
import json, sys
try: cfg = json.load(open(sys.argv[1]))
except Exception: print(""); sys.exit(0)
vol, field = sys.argv[2], sys.argv[3]
v = cfg.get("volumes", {}).get(vol, {})
val = v.get(field) if field in v else (cfg.get("default_"+field) or cfg.get(field))
print(",".join(val) if isinstance(val, list) else ("" if val is None else val))
PY
}
_cfg_set_last() {
    [ -f "$BACKUP_CONFIG" ] || return 0
    "$PY" - "$BACKUP_CONFIG" "$1" "$2" <<'PY'
import json, sys
cfg, vol, ts = sys.argv[1:4]
try: d = json.load(open(cfg))
except Exception: sys.exit(0)
d.setdefault("volumes", {}).setdefault(vol, {})["last_backup"] = ts
json.dump(d, open(cfg, "w"), indent=2)
PY
}

# ── FULL: entire persistent data state ───────────────────────────────────────
do_full() {
    local dest="$1" encrypt="$2" ventoy="${3:-auto}" vcompress="${4:-no}"
    [ -z "$dest" ] && dest="$DEFAULT_DEST"
    [ "$encrypt" = "auto" ] && encrypt="yes"    # full state always carries secrets
    mkdir -p "$dest" || { err "cannot create dest: $dest"; return 1; }

    # (1) Container layer — the /data persistent dirs.
    local -a targets=()
    for t in $FULL_TARGETS; do [ -e "$RUNTIME_ROOT/$t" ] && targets+=("$t"); done
    if [ "${#targets[@]}" -gt 0 ]; then
        local ts; ts="$(now_ts)"; local base="$dest/FULL__${ts}"; local tarball="$base.tar.gz"
        info "FULL — container persistent data [${targets[*]}] → $dest"
        if tar czf "$tarball" -C "$RUNTIME_ROOT" "${TAR_EXCLUDES[@]}" "${targets[@]}" 2>/dev/null; then
            _encrypt_or_move "$tarball" "$encrypt"; local final="$FINAL"
            local size; size="$(du -h "$final" 2>/dev/null | cut -f1)"
            _write_manifest "$base.manifest.json" "full" "persistent-data" "${FULL_TARGETS// /,}" "$ENC" "$(basename "$final")" "$size" "$RUNTIME_ROOT"
            log "FULL(container) → $(basename "$final")  ($size, encrypted=$ENC)"
        else err "tar failed"; rm -f "$tarball"; fi
    else
        info "no container data dirs under $RUNTIME_ROOT — skipping container layer"
    fi

    # (2) Ventoy/USB layer — the delegated .dat images + ventoy.json (the OUTER
    #     persistent data state). Included automatically when a USB is present.
    if [ "$ventoy" != "no" ]; then
        if _detect_ventoy; then
            info "FULL — including Ventoy USB persistence layer (@ventoy)"
            do_persistence_backup "@ventoy" "$dest" "no" "$vcompress" || true
        elif [ "$ventoy" = "yes" ]; then
            err "--with-ventoy requested but no Ventoy USB detected (set HEMLOCK_VENTOY_MOUNT)"
        fi
    fi
    [ "$encrypt" = "yes" ] && warn "keep $BACKUP_KEY backed up separately — encrypted archives need it."
}

# ── CUSTOM: one volume ───────────────────────────────────────────────────────
do_backup() {
    local vol="$1" dest="$2" include="$3" encrypt="$4"
    local vpath; vpath="$(_vol_path "$vol")"
    [ -z "$vpath" ] || [ ! -d "$vpath" ] && { err "no such volume: $vol"; return 1; }
    [ -z "$include" ] && include="$(_cfg_get "$vol" include)"; [ -z "$include" ] && include="$DEFAULT_INCLUDE"
    [ -z "$dest" ]    && dest="$(_cfg_get "$vol" destination)"; [ -z "$dest" ] && dest="$DEFAULT_DEST"

    local -a paths; _include_paths "$include" paths
    local -a present=(); for p in "${paths[@]}"; do [ -e "$vpath/$p" ] && present+=("$p"); done
    [ "${#present[@]}" -eq 0 ] && { warn "$vol: nothing to back up for include='$include'"; return 0; }

    if [ "$encrypt" = "auto" ]; then
        if _has_sensitive "$include" && [ "$(_cfg_get "$vol" encrypt_when_sensitive)" != "False" ]; then encrypt="yes"; else encrypt="no"; fi
    fi
    local safe; safe="$(echo "$vol" | tr '/:@' '___')"; local ts; ts="$(now_ts)"
    mkdir -p "$dest" || { err "cannot create dest: $dest"; return 1; }
    local base="$dest/${safe}__${ts}"; local tarball="$base.tar.gz"
    info "CUSTOM backup '$vol'  [$include]  → $dest"
    if ! tar czf "$tarball" -C "$vpath" "${TAR_EXCLUDES[@]}" "${present[@]}" 2>/dev/null; then
        err "tar failed for $vol"; rm -f "$tarball"; return 1
    fi
    _encrypt_or_move "$tarball" "$encrypt"; local final="$FINAL"
    local size; size="$(du -h "$final" 2>/dev/null | cut -f1)"
    _write_manifest "$base.manifest.json" "custom" "$vol" "$include" "$ENC" "$(basename "$final")" "$size" "$vpath"
    _cfg_set_last "$vol" "$ts"
    log "$vol → $(basename "$final")  ($size, encrypted=$ENC)"
}

# ── restore (guarded) ────────────────────────────────────────────────────────
do_restore() {
    local archive="$1" into="$2" dataroot="$3" dryrun="$4" force="$5"
    [ -f "$archive" ] || { err "no such archive: $archive"; return 1; }
    local manifest="${archive%.tar.gz}"; manifest="${manifest%.tar.gz.enc}.manifest.json"
    local mode="custom" scope=""
    if [ -f "$manifest" ]; then
        mode="$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("mode","custom"))' "$manifest" 2>/dev/null)"
        scope="$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("scope",""))' "$manifest" 2>/dev/null)"
    fi

    # decrypt if needed
    local tmp="" tarball="$archive"
    if [[ "$archive" == *.enc ]]; then
        [ -f "$BACKUP_KEY" ] || { err "encrypted archive but no key at $BACKUP_KEY"; return 1; }
        tmp="$(mktemp --suffix=.tar.gz)"
        openssl enc -d -aes-256-cbc -pbkdf2 -in "$archive" -out "$tmp" -pass "file:$BACKUP_KEY" 2>/dev/null \
            || { err "decryption failed (wrong key?)"; rm -f "$tmp"; return 1; }
        tarball="$tmp"
    fi

    # decide restore target dir
    local target_dir=""
    if [ "$mode" = "full" ]; then
        target_dir="${dataroot:-$RUNTIME_ROOT}"
        [ -z "$dataroot" ] && [ "$force" != "yes" ] && {
            err "FULL restore into $RUNTIME_ROOT is destructive — pass --data-root <dir> to stage safely, or --force to restore in place"; [ -n "$tmp" ] && rm -f "$tmp"; return 1; }
    else
        local tgt="${into:-$scope}"
        [ -z "$tgt" ] && { err "cannot determine target volume — pass --into <vol>"; [ -n "$tmp" ] && rm -f "$tmp"; return 1; }
        target_dir="$(_vol_path "$tgt")"
        [ -z "$target_dir" ] && { err "target volume not found: $tgt"; [ -n "$tmp" ] && rm -f "$tmp"; return 1; }
        [ -n "$scope" ] && [ "$scope" != "$tgt" ] && [ "$force" != "yes" ] && {
            err "archive is from '$scope' but target is '$tgt' — pass --force to cross-restore"; [ -n "$tmp" ] && rm -f "$tmp"; return 1; }
    fi

    info "mode=$mode  scope=${scope:-?}  → $target_dir"
    info "archive contents:"; tar tzf "$tarball" 2>/dev/null | head -40
    if [ "$dryrun" = "yes" ]; then info "(dry-run) no changes made"; [ -n "$tmp" ] && rm -f "$tmp"; return 0; fi
    if [ "$force" != "yes" ]; then
        printf "Restore into %s ? [y/N]: " "$target_dir"; read -r a; case "$a" in y|Y) ;; *) info "aborted"; [ -n "$tmp" ] && rm -f "$tmp"; return 0 ;; esac
    fi
    # snapshot custom-volume before overwrite (full is too large — stage instead)
    if [ "$mode" != "full" ]; then
        local snap="$target_dir/.archive/pre-restore-$(now_ts)"
        mkdir -p "$snap" 2>/dev/null && cp -a "$target_dir/." "$snap/" 2>/dev/null && info "snapshotted current → $snap"
    fi
    mkdir -p "$target_dir" 2>/dev/null
    local rc=0
    if tar xzf "$tarball" -C "$target_dir" 2>/dev/null; then log "restored → $target_dir"; else err "extraction failed"; rc=1; fi
    [ -n "$tmp" ] && rm -f "$tmp"
    return $rc
}

# ── PERSISTENCE: Ventoy .dat images + ventoy.json ────────────────────────────
# Persistence images can be many GB, so these are copied as FILES (sparse-aware),
# optionally gzip-compressed and/or encrypted per-file, into a backup directory
# with a manifest — NOT tarred. Restore copies them back (guarded).
do_persistence_backup() {   # $1=ref(@ventoy|dat:name) $2=dest $3=encrypt $4=compress
    local ref="$1" dest="$2" encrypt="$3" compress="$4"
    _detect_ventoy || { err "no Ventoy USB persistence detected (boot outside it, mount the USB, or set HEMLOCK_VENTOY_MOUNT)"; return 1; }
    [ "$encrypt" = "auto" ] && encrypt="no"    # .dat images are large; encryption is opt-in
    [ -z "$dest" ] && dest="$DEFAULT_DEST"; mkdir -p "$dest" || { err "cannot create dest: $dest"; return 1; }

    local -a files=()
    if [ "$ref" = "@ventoy" ]; then
        [ -f "$VENTOY_JSON" ] && files+=("$VENTOY_JSON")
        local d; while IFS= read -r d; do [ -n "$d" ] && files+=("$d"); done < <(_list_dats)
    else
        local name="${ref#dat:}"; name="${name%.dat}"
        local f="$PERSIST_DIR/${name}.dat"
        [ -f "$f" ] || { err "no such persistence image: ${name}.dat under $PERSIST_DIR"; return 1; }
        files+=("$f"); [ -f "$VENTOY_JSON" ] && files+=("$VENTOY_JSON")   # keep mapping for restore context
    fi
    [ "${#files[@]}" -eq 0 ] && { warn "nothing to back up under $PERSIST_DIR"; return 0; }
    if [ "$encrypt" = "yes" ] && [ ! -f "$BACKUP_KEY" ]; then warn "no key — run: backup.sh init (writing UNENCRYPTED)"; encrypt="no"; fi

    local safe; safe="$(echo "$ref" | tr '/:@' '___')"; local ts; ts="$(now_ts)"
    local outdir="$dest/${safe}__${ts}"; mkdir -p "$outdir"
    info "PERSISTENCE backup '$ref' from $VENTOY_MOUNT → $outdir  (encrypt=$encrypt compress=$compress)"
    # ── the constraint the user MUST understand ──────────────────────────────
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}NOTE:${NC} You cannot back up a persistence image you are booted INTO —"
    echo    "      you can't copy the filesystem you're currently running from."
    echo    "      Run this from the HOST or another boot (i.e. OUTSIDE Ventoy)."
    if _can_detect_use; then
        echo  "      In-use images are auto-detected and SKIPPED below."
    else
        echo -e "      ${YELLOW}(losetup unavailable — cannot verify which images are live; make${NC}"
        echo -e "      ${YELLOW} sure you are NOT booted into the one(s) you back up.)${NC}"
    fi
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}"
    local -a stored=(); local skipped=0; local f bn out
    for f in "${files[@]}"; do
        bn="$(basename "$f")"; out="$outdir/$bn"
        if [[ "$bn" == *.dat ]] && _dat_in_use "$f"; then
            warn "SKIPPING $bn — it is CURRENTLY IN USE (mounted/booted). You cannot"
            warn "  back up the persistence you are running inside. Do it from outside Ventoy."
            skipped=$((skipped+1)); continue
        fi
        info "  copying $bn ($(du -h "$f" 2>/dev/null | cut -f1))"
        if [[ "$bn" == *.dat ]] && [ "$compress" = "yes" ]; then
            gzip -c "$f" > "$out.gz" 2>/dev/null && out="$out.gz" || { err "copy failed: $bn"; continue; }
        else
            cp --sparse=always "$f" "$out" 2>/dev/null || cp "$f" "$out" 2>/dev/null || { err "copy failed: $bn"; continue; }
        fi
        if [[ "$bn" == *.dat ]] && [ "$encrypt" = "yes" ]; then
            openssl enc -aes-256-cbc -pbkdf2 -salt -in "$out" -out "$out.enc" -pass "file:$BACKUP_KEY" 2>/dev/null \
                && { rm -f "$out"; out="$out.enc"; } || warn "encrypt failed: $bn (kept plain)"
        fi
        stored+=("$(basename "$out")")
    done
    # manifest (argv-safe; files list passed as trailing args)
    "$PY" - "$outdir/manifest.json" "$ref" "$ts" "$encrypt" "$compress" "$VENTOY_MOUNT" "${stored[@]}" <<'PY'
import json, sys
mf, ref, ts, enc, comp, src = sys.argv[1:7]
files = sys.argv[7:]
json.dump({"mode":"persistence","scope":ref,"timestamp":ts,
           "encrypted":enc=="yes","compressed":comp=="yes","source":src,"files":files},
          open(mf,"w"), indent=2)
PY
    if [ "${#stored[@]}" -eq 0 ]; then
        warn "NOTHING backed up for '$ref' — all target image(s) were in use. Re-run from OUTSIDE the persistence (host / another boot)."
        rmdir "$outdir" 2>/dev/null || true
        return 1
    fi
    log "$ref → $(basename "$outdir")/  (${#stored[@]} file(s)$([ "$skipped" -gt 0 ] && echo ", $skipped skipped as in-use"))"
    [ "$encrypt" = "yes" ] && warn "keep $BACKUP_KEY backed up separately."
}

do_persistence_restore() {  # $1=backup dir (has manifest.json) $2=force
    local bdir="$1" force="$2"
    [ -d "$bdir" ] || { err "not a persistence backup directory: $bdir"; return 1; }
    [ -f "$bdir/manifest.json" ] || { err "no manifest.json in $bdir"; return 1; }
    _detect_ventoy || { err "no Ventoy USB target detected — mount the USB or set HEMLOCK_VENTOY_MOUNT"; return 1; }
    warn "Restoring persistence images OVERWRITES live .dat files at $PERSIST_DIR."
    warn "NEVER restore over an image you are currently booted from — do this from the host / another boot."
    info "will restore into: $VENTOY_MOUNT  (persistence/ + ventoy/)"
    ls -la "$bdir" | sed 's/^/  /'
    if [ "$force" != "yes" ]; then
        printf "Proceed? [y/N]: "; read -r a; case "$a" in y|Y) ;; *) info "aborted"; return 0 ;; esac
    fi
    mkdir -p "$PERSIST_DIR" "$VENTOY_MOUNT/ventoy"
    local src bn target
    for src in "$bdir"/*; do
        bn="$(basename "$src")"; [ "$bn" = "manifest.json" ] && continue
        # decrypt / decompress by suffix
        local work="$src" tmp=""
        if [[ "$bn" == *.enc ]]; then
            [ -f "$BACKUP_KEY" ] || { err "encrypted $bn but no key"; continue; }
            tmp="$(mktemp)"; openssl enc -d -aes-256-cbc -pbkdf2 -in "$src" -out "$tmp" -pass "file:$BACKUP_KEY" 2>/dev/null \
                || { err "decrypt failed: $bn"; rm -f "$tmp"; continue; }
            work="$tmp"; bn="${bn%.enc}"
        fi
        if [[ "$bn" == *.gz ]]; then
            local ug; ug="$(mktemp)"; gunzip -c "$work" > "$ug" 2>/dev/null || { err "gunzip failed: $bn"; rm -f "$tmp" "$ug"; continue; }
            [ -n "$tmp" ] && rm -f "$tmp"; work="$ug"; tmp="$ug"; bn="${bn%.gz}"
        fi
        if [ "$bn" = "ventoy.json" ]; then target="$VENTOY_MOUNT/ventoy/ventoy.json"; else target="$PERSIST_DIR/$bn"; fi
        if [[ "$bn" == *.dat ]] && _dat_in_use "$target"; then
            warn "SKIPPING $bn — the target image is CURRENTLY IN USE (mounted/booted)."
            warn "  You cannot overwrite the persistence you are running inside. Restore from outside Ventoy."
            [ -n "$tmp" ] && rm -f "$tmp"; continue
        fi
        info "  restoring $bn → $target"
        cp --sparse=always "$work" "$target" 2>/dev/null || cp "$work" "$target" || err "restore failed: $bn"
        [ -n "$tmp" ] && rm -f "$tmp"
    done
    log "persistence restored into $VENTOY_MOUNT"
}

show_status() {
    local dest="${1:-$DEFAULT_DEST}"; info "backups in: $dest"
    [ -d "$dest" ] || { warn "(none — destination does not exist yet)"; return 0; }
    local found=0 m
    # tar-based (full/custom) manifests sit beside the archive; persistence
    # backups keep manifest.json inside their own directory — scan both.
    for m in "$dest"/*.manifest.json "$dest"/*/manifest.json; do [ -f "$m" ] || continue; found=1
        "$PY" -c 'import json,sys;d=json.load(open(sys.argv[1]));print("  [%s] %-22s %s  enc=%s  %s" % (d.get("mode"),d.get("scope"),d.get("timestamp"),d.get("encrypted"),d.get("size") or ("%d file(s)"%len(d.get("files",[])))))' "$m" 2>/dev/null; done
    [ "$found" -eq 0 ] && warn "(no backups found)"
}

run_due() {
    _ensure_config; local now vol sched last interval due last_s
    now="$(date -u +%s)"
    while IFS= read -r vol; do
        sched="$(_cfg_get "$vol" schedule)"
        case "$sched" in daily) interval=86400 ;; weekly) interval=604800 ;; monthly) interval=2592000 ;; *) continue ;; esac
        last="$(_cfg_get "$vol" last_backup)"
        if [ -z "$last" ]; then due=1; else
            last_s="$(date -u -d "$(echo "$last" | sed -E 's/T/ /; s/Z//; s/([0-9]{2})([0-9]{2})([0-9]{2})$/\1:\2:\3/')" +%s 2>/dev/null || echo 0)"
            [ $(( now - last_s )) -ge "$interval" ] && due=1 || due=0
        fi
        [ "$due" = "1" ] && { info "scheduled ($sched) due: $vol"; do_backup "$vol" "" "" "auto" || true; }
    done < <(_all_volumes)
}

# ── CLI ──────────────────────────────────────────────────────────────────────
cmd="${1:-}"; shift || true
case "$cmd" in
    init)
        mkdir -p "$CONFIG_DIR"
        if [ -f "$BACKUP_KEY" ]; then warn "key already exists: $BACKUP_KEY"; else
            (umask 077; openssl rand -hex 32 > "$BACKUP_KEY") && chmod 600 "$BACKUP_KEY" && log "generated key: $BACKUP_KEY"
            warn "BACK THIS KEY UP SEPARATELY — encrypted backups are unrecoverable without it."
        fi
        _ensure_config && log "config ready: $BACKUP_CONFIG" ;;
    full)
        _ensure_config; dest=""; encrypt="auto"; ventoy="auto"; vcompress="no"
        while [ $# -gt 0 ]; do case "$1" in
            --dest) dest="$2"; shift ;; --encrypt) encrypt="yes" ;; --no-encrypt) encrypt="no" ;;
            --no-ventoy) ventoy="no" ;; --with-ventoy) ventoy="yes" ;; --ventoy-compress) vcompress="yes" ;;
        esac; shift; done
        do_full "$dest" "$encrypt" "$ventoy" "$vcompress" ;;
    list-volumes) list_volumes ;;
    backup)
        _ensure_config; target=""; dest=""; include=""; encrypt="auto"; compress="no"; all=0
        while [ $# -gt 0 ]; do case "$1" in
            --all) all=1 ;; --dest) dest="$2"; shift ;; --include) include="$2"; shift ;;
            --encrypt) encrypt="yes" ;; --no-encrypt) encrypt="no" ;; --compress) compress="yes" ;; *) target="$1" ;;
        esac; shift; done
        if [ "$all" = "1" ]; then while IFS= read -r v; do do_backup "$v" "$dest" "$include" "$encrypt" || true; done < <(_all_volumes)
        elif [ -n "$target" ]; then
            case "$target" in
                @ventoy|dat:*) do_persistence_backup "$target" "$dest" "$encrypt" "$compress" ;;
                *)             do_backup "$target" "$dest" "$include" "$encrypt" ;;
            esac
        else err "specify a volume or --all (see: backup.sh list-volumes)"; exit 1; fi ;;
    restore)
        archive=""; into=""; dataroot=""; dryrun="no"; force="no"
        while [ $# -gt 0 ]; do case "$1" in
            --into) into="$2"; shift ;; --data-root) dataroot="$2"; shift ;;
            --dry-run) dryrun="yes" ;; --force) force="yes" ;; *) archive="$1" ;;
        esac; shift; done
        [ -z "$archive" ] && { err "usage: backup.sh restore <archive|persist-dir> [--into <vol>|--data-root <dir>] [--dry-run] [--force]"; exit 1; }
        if [ -d "$archive" ] && [ -f "$archive/manifest.json" ]; then
            do_persistence_restore "$archive" "$force"       # Ventoy .dat backup dir
        else
            do_restore "$archive" "$into" "$dataroot" "$dryrun" "$force"
        fi ;;
    status) show_status "${1:-}" ;;
    run-due) run_due ;;
    config)
        _ensure_config
        case "${1:-get}" in
            get) cat "$BACKUP_CONFIG" ;;
            set-default) "$PY" - "$BACKUP_CONFIG" "$2" "$3" <<'PY'
import json, sys
cfg, field, val = sys.argv[1:4]
d = json.load(open(cfg))
if field == "include": val = val.split(",")
if field == "encrypt_when_sensitive": val = val.lower() in ("1","true","yes")
d["default_"+field if field in ("destination","include") else field] = val
json.dump(d, open(cfg, "w"), indent=2); print("set default %s" % field)
PY
                ;;
            set-volume) "$PY" - "$BACKUP_CONFIG" "$2" "$3" "$4" <<'PY'
import json, sys
cfg, vol, field, val = sys.argv[1:5]
d = json.load(open(cfg))
if field == "include": val = val.split(",")
d.setdefault("volumes", {}).setdefault(vol, {})[field] = val
json.dump(d, open(cfg, "w"), indent=2); print("set %s.%s" % (vol, field))
PY
                ;;
            *) err "config: get | set-default <field> <val> | set-volume <vol> <field> <val>"; exit 1 ;;
        esac ;;
    ""|-h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) err "unknown command: $cmd (try --help)"; exit 1 ;;
esac
