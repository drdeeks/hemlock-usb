#!/usr/bin/env bash
# launch-menu.sh — the friendly access point to the USB platform's master menu.
# Works from ANYWHERE this skill lives (on the stick, in an agent workspace,
# on a host): finds the menu, execs it, passes every argument through.
#
# Resolution order (first hit wins):
#   1. $USB_MENU — explicit override (path to menu.sh)
#   2. A menu.sh in this script's ancestor directories (skill deployed on-stick)
#   3. The root launcher or system tree on any mounted Ventoy volume
#   4. findmnt by filesystem LABEL=Ventoy
#
# Usage: bash scripts/launch-menu.sh [menu args...]   (e.g. --text, --hemlock)
set -euo pipefail

_try() {
    [ -n "${1:-}" ] || return 0
    [ -f "$1" ] || return 0
    exec bash "$1" "${ARGS[@]+"${ARGS[@]}"}"
}
ARGS=("$@")

# 1. explicit override
_try "${USB_MENU:-}"

# 2. ancestors of this script (skill sitting inside the stick's tree)
d="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
while [ "$d" != "/" ]; do
    _try "$d/menu.sh"
    _try "$d/usb-hemlock/system/menu.sh"
    d="$(dirname "$d")"
done

# 3. mounted Ventoy volumes (root launcher preferred, system tree fallback);
#    non-standard mountpoints are covered by the findmnt LABEL probe below
for m in /media/*/Ventoy /run/media/*/Ventoy; do
    _try "$m/menu.sh"
    _try "$m/usb-hemlock/system/menu.sh"
done

# 4. findmnt by label (covers non-standard mountpoints)
if command -v findmnt >/dev/null 2>&1; then
    m="$(findmnt -nr -o TARGET -S 'LABEL=Ventoy' 2>/dev/null | head -1)"
    _try "${m:+$m/menu.sh}"
    _try "${m:+$m/usb-hemlock/system/menu.sh}"
fi

echo "launch-menu: no platform menu found." >&2
echo "  Plug in / mount the USB stick, or set USB_MENU=/path/to/menu.sh" >&2
exit 1
