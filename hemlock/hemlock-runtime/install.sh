#!/usr/bin/env bash
# =============================================================================
# install.sh — Hemlock runtime installer. One script, every variation.
#
# Hemlock IS the combined runtime: control plane + cognition, bridged over MCP,
# as one system. There is no cognition-only offering — every variant below is
# the whole thing, sized differently:
#
#   full     everything baked (toolchain, ffmpeg, compilers)      ~4.2GB
#   lean     adaptable — no baked toolchain; tools from your data  ~870MB
#   minimal  gateway daemon + brain + platforms/menu/health only   ~2GB
#
# Sources:      build from this repo (default) | load a prebuilt tarball
# Destinations: local docker (default) | USB persistence (.dat) | native (no container)
#
# Informative + optional: run with no args for the interactive picker; every
# choice has a flag for non-interactive/agent use. Nothing is ever forced.
#
#   install.sh                              # interactive
#   install.sh --variant lean               # build hemlock:lean locally
#   install.sh --variant full --usb         # build + save + copy into USB persistence
#   install.sh --load hemlock.tar.gz        # docker load a prebuilt image
#   install.sh --native                     # no container — scripts/run-native.sh
#   install.sh --variant minimal --yes      # non-interactive, no prompts
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VARIANT="" ; LOAD_TAR="" ; TO_USB=0 ; NATIVE=0 ; ASSUME_YES=0
log()  { echo "[hemlock-install] $*"; }
warn() { echo "[hemlock-install][warn] $*" >&2; }
die()  { echo "[hemlock-install][error] $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --variant) VARIANT="${2:-}"; shift 2 ;;
        --load)    LOAD_TAR="${2:-}"; shift 2 ;;
        --usb)     TO_USB=1; shift ;;
        --native)  NATIVE=1; shift ;;
        --yes|-y)  ASSUME_YES=1; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown flag: $1 (see --help)" ;;
    esac
done

confirm() {  # informative, never forced — auto-yes only when asked to be
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ -t 0 ] || return 0
    read -r -p "$1 [Y/n] " a; [ -z "$a" ] || [ "${a,,}" = "y" ]
}

dockerfile_for() {
    case "$1" in
        full)    echo "Dockerfile.runtime" ;;
        lean)    echo "Dockerfile.runtime-lean" ;;
        minimal) echo "Dockerfile.runtime-minimal" ;;
        *) return 1 ;;
    esac
}
tag_for() { [ "$1" = "full" ] && echo "hemlock:latest" || echo "hemlock:$1"; }

# ── Interactive picker (TTY only, skipped when flags decide) ─────────────────
if [ -z "$VARIANT" ] && [ -z "$LOAD_TAR" ] && [ "$NATIVE" -eq 0 ] && [ -t 0 ]; then
    echo ""
    echo "  Hemlock runtime — pick your installation:"
    echo ""
    echo "    1) full     — everything baked, plug ready            (~4.2GB image)"
    echo "    2) lean     — no baked toolchain, bring your own data (~870MB image)"
    echo "    3) minimal  — daemon + brain + access/menu/health     (~2GB image)"
    echo "    4) load     — docker load a prebuilt hemlock tarball"
    echo "    5) native   — run on this machine with no container"
    echo ""
    read -r -p "  Choice [1-5]: " c
    case "$c" in
        1) VARIANT=full ;; 2) VARIANT=lean ;; 3) VARIANT=minimal ;;
        4) read -r -p "  Tarball path: " LOAD_TAR ;;
        5) NATIVE=1 ;;
        *) die "no choice made" ;;
    esac
    if [ "$NATIVE" -eq 0 ]; then
        read -r -p "  Also copy the image onto USB persistence? [y/N] " u
        [ "${u,,}" = "y" ] && TO_USB=1
    fi
fi

# ── Native path (no container) ────────────────────────────────────────────────
if [ "$NATIVE" -eq 1 ]; then
    log "native install — no container. Handing off to scripts/run-native.sh"
    exec "$SCRIPT_DIR/scripts/run-native.sh"
fi

command -v docker >/dev/null || die "docker not found (native mode works without it: --native)"

# ── Acquire the image: build a variant OR load a tarball ─────────────────────
IMAGE=""
if [ -n "$LOAD_TAR" ]; then
    [ -f "$LOAD_TAR" ] || die "tarball not found: $LOAD_TAR"
    log "loading image from $LOAD_TAR ..."
    out=$(docker load -i "$LOAD_TAR" 2>&1) || die "docker load failed: $out"
    IMAGE=$(echo "$out" | sed -n 's/^Loaded image: //p' | head -1)
    log "loaded: ${IMAGE:-<see docker images>}"
else
    DF=$(dockerfile_for "$VARIANT") || die "unknown variant '$VARIANT' (full|lean|minimal)"
    [ -f "$DF" ] || die "$DF not found — run from the hemlock-runtime repo root"
    IMAGE=$(tag_for "$VARIANT")
    log "building $IMAGE from $DF (this can take a while) ..."
    confirm "Proceed with build?" || die "aborted"
    DOCKER_BUILDKIT=0 docker build -t "$IMAGE" -f "$DF" . || die "build failed"
    log "built: $IMAGE ($(docker images "$IMAGE" --format '{{.Size}}'))"
fi

# ── USB install: the portable system lives on the USB FREE SPACE; the image
#    goes into persistence. Selecting USB means set the USB up — completely. ──
if [ "$TO_USB" -eq 1 ]; then
    [ -n "$IMAGE" ] || die "no image to deploy"

    # 1. Find the mounted USB volume (Ventoy root — where the portable system lives)
    USB_ROOT=""
    for cand in /media/*/* /run/media/*/*; do
        [ -d "$cand" ] || continue
        if [ -d "$cand/persistence" ] || [ -d "$cand/ventoy" ] || [ -f "$cand/menu.sh" ]; then
            USB_ROOT="$cand"; break
        fi
    done
    if [ -z "$USB_ROOT" ]; then
        # fall back to any mounted removable volume the user confirms
        for cand in /media/*/* /run/media/*/*; do
            [ -d "$cand" ] || continue
            confirm "Use $cand as the USB target?" && USB_ROOT="$cand" && break
        done
    fi
    [ -n "$USB_ROOT" ] || die "no mounted USB volume found — plug it in / mount it, then rerun"
    log "USB volume: $USB_ROOT"

    # 2. Portable system onto the USB FREE SPACE (source tree — the system itself,
    #    not container internals). The vendored node toolchain + openclaw dist are
    #    EXCLUDED: they already live inside the image, and their tens of thousands
    #    of tiny files explode on exFAT's large clusters. Free space is checked
    #    up front; a failed copy is removed, never left half-written.
    USB_SYS="$USB_ROOT/hemlock/hemlock-runtime"
    RSYNC_EXCLUDES=(--exclude .git --exclude '__pycache__' --exclude '*.pyc'
        --exclude .env --exclude '.secrets' --exclude 'agents/active'
        --exclude 'agents/archive' --exclude 'agents/registrar'
        --exclude data --exclude logs --exclude volumes
        --exclude 'docker/openclaw-runtime/tools' --exclude 'docker/openclaw-runtime/lib')
    if [ "$(readlink -f "$USB_SYS" 2>/dev/null)" != "$(readlink -f "$SCRIPT_DIR")" ]; then
        NEED_KB=$(du -sk "$SCRIPT_DIR" --exclude=.git --exclude=docker/openclaw-runtime/tools \
                  --exclude=docker/openclaw-runtime/lib --exclude=data --exclude=logs \
                  --exclude=volumes 2>/dev/null | cut -f1)
        FREE_KB=$(df -k --output=avail "$USB_ROOT" | tail -1 | tr -d ' ')
        # exFAT cluster overhead on many small files: demand 2x headroom
        if [ "${FREE_KB:-0}" -lt $(( ${NEED_KB:-0} * 2 )) ]; then
            warn "not enough USB free space for the system copy (need ~$((NEED_KB / 1024))MB x2 headroom, have $((FREE_KB / 1024))MB) — skipping"
        elif confirm "Copy the runtime system onto the USB free space ($USB_SYS)?"; then
            mkdir -p "$USB_SYS"
            # -rt (no -l/-p/-o): exFAT has no symlinks/perms/owners — skip, don't fail
            if rsync -rt --delete "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/" "$USB_SYS/"; then
                log "portable system on USB: $USB_SYS"
            else
                warn "system copy failed — removing the partial copy (nothing half-written)"
                rm -rf "$USB_SYS"
            fi
        fi
    fi

    # 3. Image into PERSISTENCE. If none exists yet, hand off to the USB
    #    platform's own setup (it owns persistence creation) — never a dead end.
    DAT=$(find "$USB_ROOT/persistence" -maxdepth 1 -name '*.dat' -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    if [ -z "$DAT" ]; then
        warn "no persistence .dat on $USB_ROOT yet"
        MENU="$USB_ROOT/menu.sh"; [ -f "$MENU" ] || MENU="$(dirname "$(dirname "$SCRIPT_DIR")")/menu.sh"
        if [ -f "$MENU" ] && [ -t 0 ] && confirm "Open the USB platform menu to create one now?"; then
            bash "$MENU" || true
            DAT=$(find "$USB_ROOT/persistence" -maxdepth 1 -name '*.dat' -printf '%s %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        fi
        [ -n "$DAT" ] || { warn "skipping image→persistence (create one via the USB menu, then rerun with --usb)"; DAT=""; }
    fi
    if [ -n "$DAT" ]; then
        log "target persistence: $DAT"
        confirm "Save $IMAGE and copy into $(basename "$DAT")? (needs sudo to mount)" || die "aborted"
        TAR="$(mktemp -u /tmp/hemlock-image-XXXX).tar.gz"
        log "saving + compressing image (few minutes) ..."
        docker save "$IMAGE" | gzip -1 > "$TAR" || die "docker save failed"
        log "tarball: $(du -h "$TAR" | cut -f1)"
        MNT=$(mktemp -d /tmp/hemlock-persist-XXXX)
        sudo mount -o loop "$DAT" "$MNT" || { rm -f "$TAR"; die "mount failed"; }
        sudo mkdir -p "$MNT/hemlock"
        if sudo cp "$TAR" "$MNT/hemlock/$(basename "$TAR")" && sync; then
            sudo df -h "$MNT" | tail -1
            log "copied. On the booted USB:  docker load -i /hemlock/$(basename "$TAR")"
        else
            warn "copy failed — persistence may be full"
        fi
        sudo umount "$MNT" && rmdir "$MNT"; rm -f "$TAR"
    fi
fi

log "done. Start it:  docker compose -f docker-compose.runtime.yml up   (or docker run $IMAGE)"
