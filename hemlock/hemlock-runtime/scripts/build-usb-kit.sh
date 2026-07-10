#!/usr/bin/env bash
# =============================================================================
# build-usb-kit.sh — assemble the Hemlock USB kit (CL-047)
#
# The kit is the ACTUAL package the stick carries: the master menu (the whole
# TUI), the USB-first system, and strictly the host-side pieces needed to
# manage Hemlock — pull a release image, load it, run it, doctor it. It does
# NOT carry the runtime source tree, the vendored engine, skills, or any
# image tarball: images come from GitHub releases (menu → Hemlock Manager →
# Hemlock images → pull), which is the whole point of publishing them.
#
#   build-usb-kit.sh --out  [DIR]     # write DIR/hemlock-usb-kit-<ver>.tar.gz
#                                     # (default DIR: <repo>/dist)
#   build-usb-kit.sh --sync <DEST>    # rsync the kit tree onto DEST
#                                     # (used by menu.sh USB deploy, kit mode)
#
# One manifest, both modes — the include/exclude set below is the single
# source of truth for "what is the kit".
# =============================================================================
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# scripts/ → hemlock-runtime → hemlock → repo root
ROOT="$(cd "$here/../../.." && pwd)"
[ -f "$ROOT/menu.sh" ] || { echo "ERROR: repo root not found from $here" >&2; exit 1; }

MODE="${1:---out}"
ARG="${2:-}"

# ── The kit manifest ─────────────────────────────────────────────────────────
# rsync include/exclude, applied to the repo root. Order matters: includes
# for the hemlock-runtime subset come before the excludes that drop the rest.
RS_RULES=(
  # master menu + USB-first system
  --include '/menu.sh'
  --include '/README.md'
  --include '/CHANGELOG.md'
  --include '/blueprint/'
  --include '/blueprint/ventoy-reference.md'
  --exclude '/blueprint/*'
  --include '/usb/***'
  --exclude '/usb/volumes/'
  --exclude '/usb/tests/'
  # hemlock management subset — strictly what the menu drives on the host
  --include '/hemlock/'
  --include '/hemlock/README.md'
  --include '/hemlock/hemlock-tui'
  --include '/hemlock/hemlock-runtime/'
  --include '/hemlock/hemlock-runtime/install.sh'
  --include '/hemlock/hemlock-runtime/docker-compose.runtime.yml'
  --include '/hemlock/hemlock-runtime/README.md'
  --include '/hemlock/hemlock-runtime/scripts/***'
  --exclude '/hemlock/hemlock-runtime/*'
  --exclude '/hemlock/*'
  # nothing else from the root
  --exclude '/*'
  # never, in any subtree
  --exclude '.git/' --exclude '.env' --exclude '.secrets/'
  --exclude '*.log' --exclude '*.db' --exclude 'node_modules/'
  --exclude '__pycache__/' --exclude '.trash/'
)

kit_version() {
  git -C "$ROOT" describe --tags --always 2>/dev/null || date +%Y%m%d
}

sync_kit() {  # $1 = destination dir
  local dest="$1"
  mkdir -p "$dest"
  rsync -a --delete "${RS_RULES[@]}" "$ROOT/" "$dest/"
}

case "$MODE" in
  --sync)
    [ -n "$ARG" ] || { echo "usage: $0 --sync <DEST>" >&2; exit 1; }
    sync_kit "$ARG"
    echo "kit synced -> $ARG ($(du -sh "$ARG" | cut -f1))"
    ;;
  --out)
    OUT="${ARG:-$ROOT/dist}"
    VER="$(kit_version)"
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    sync_kit "$STAGE/hemlock-usb-kit"
    mkdir -p "$OUT"
    TARBALL="$OUT/hemlock-usb-kit-$VER.tar.gz"
    tar -C "$STAGE" -czf "$TARBALL" hemlock-usb-kit
    (cd "$OUT" && sha256sum "$(basename "$TARBALL")" > "$(basename "$TARBALL").sha256")
    echo "kit: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
    echo "     $(cat "$TARBALL.sha256" 2>/dev/null || true)"
    ;;
  *)
    echo "usage: $0 --out [DIR] | --sync <DEST>" >&2
    exit 1
    ;;
esac
