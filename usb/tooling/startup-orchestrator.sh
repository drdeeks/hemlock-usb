#!/usr/bin/env bash
# =============================================================================
# startup.sh — USB-Hemlock boot orchestrator (runs as root via rc.local)
# Chain: host compute → hemlock. The tooling volume is OPTIONAL (CL-041):
# mounted and updated only when persistence/tooling.dat exists. Minimal
# sticks (hemlock gateway + brain over MCP) ship without it.
# Sequence: identity log → tooling (if present) → first-boot essentials
#           → tooling update (if mounted) → operator hooks.
# Everything logs to the USB itself: usb-hemlock/logs/.
# =============================================================================
set -u

# ── 1. Find the USB (label-based, path-agnostic) ─────────────────────────────
USB_MNT=""
for try in 1 2 3 4 5 6; do
    USB_MNT=$(findmnt -nr -o TARGET -S "LABEL=Ventoy" 2>/dev/null | head -1)
    [ -n "$USB_MNT" ] && break
    sleep 2
done
if [ -z "$USB_MNT" ]; then
    # Live-boot case: the Ventoy partition may not be auto-mounted yet.
    dev=$(lsblk -nro NAME,LABEL | awk '$2=="Ventoy"{print "/dev/"$1; exit}')
    if [ -n "${dev:-}" ]; then
        mkdir -p /mnt/ventoy && mount "$dev" /mnt/ventoy 2>/dev/null && USB_MNT=/mnt/ventoy
    fi
fi
[ -z "$USB_MNT" ] && { echo "[startup] Ventoy partition not found — aborting" >&2; exit 0; }

LOG_DIR="$USB_MNT/usb-hemlock/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/var/log"
BOOT_LOG="$LOG_DIR/boot-$(date +%Y%m%d).log"
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$BOOT_LOG"; }

# ── 2. Identity layer — recognize this system + this stick, on the stick ─────
DEVICE_ID_FILE="$USB_MNT/usb-hemlock/etc/uca/device-identity.json"
STICK_ID="unregistered"
[ -f "$DEVICE_ID_FILE" ] && STICK_ID=$(python3 -c "import json;print(json.load(open('$DEVICE_ID_FILE')).get('stick_id','unregistered'))" 2>/dev/null || echo unregistered)
log "=== boot: stick=$STICK_ID host=$(hostname) kernel=$(uname -r) hw=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown) ==="

# ── 3. Mount the tooling volume — only if this stick carries one (CL-041) ───
TOOLING_DAT="$USB_MNT/persistence/tooling.dat"
TOOLING_MNT="/opt/tooling"
if [ -f "$TOOLING_DAT" ]; then
    # journal recovery after any surprise removal, then mount
    e2fsck -p "$TOOLING_DAT" >/dev/null 2>&1 || true
    mkdir -p "$TOOLING_MNT"
    if mountpoint -q "$TOOLING_MNT" || mount -o loop "$TOOLING_DAT" "$TOOLING_MNT" 2>>"$BOOT_LOG"; then
        log "tooling: mounted at $TOOLING_MNT"
        # expose the volume's toolchain system-wide (hf, jq, node, npm, env)
        ln -sf "$TOOLING_MNT/bin/hf" /usr/local/bin/hf 2>/dev/null || true
        ln -sf "$TOOLING_MNT/bin/jq" /usr/local/bin/jq 2>/dev/null || true
        for b in node npm npx; do ln -sf "$TOOLING_MNT/node/bin/$b" "/usr/local/bin/$b" 2>/dev/null || true; done
        grep -q "opt/tooling/env.sh" /etc/profile.d/tooling.sh 2>/dev/null || \
            printf '[ -f /opt/tooling/env.sh ] && . /opt/tooling/env.sh\n' > /etc/profile.d/tooling.sh 2>/dev/null || true
    else
        log "tooling: MOUNT FAILED — toolchain unavailable this boot"
    fi
else
    log "tooling: not present — skipping (optional; create via Persistence Manager if wanted)"
fi

# ── 4. First-boot essentials (once, marker-guarded, correct path) ────────────
MARKER="/var/lib/uca-essentials-done"
ESSENTIALS="$USB_MNT/scripts/setup-essentials.sh"
if [ ! -f "$MARKER" ] && [ -f "$ESSENTIALS" ]; then
    log "essentials: first boot — installing (log: $LOG_DIR/essentials.log)"
    if bash "$ESSENTIALS" >>"$LOG_DIR/essentials.log" 2>&1; then
        touch "$MARKER"; log "essentials: done"
    else
        log "essentials: FAILED — will retry next boot (see essentials.log)"
    fi
fi

# ── 5. Continuous tooling update (background; full log on the stick) ─────────
if [ -x "$TOOLING_MNT/tooling-update.sh" ]; then
    log "tooling: update launched (log: $LOG_DIR/tooling-update.log)"
    TOOLING_LOG="$LOG_DIR/tooling-update.log" bash "$TOOLING_MNT/tooling-update.sh" >>"$LOG_DIR/tooling-update.log" 2>&1 &
fi

# ── 5b. Connection layer — HONOR the menu's one-time config, never mutate ────
# SSH/firewall/port-forward are configured ONCE via the menu (USB Setup →
# SSH/compute access) and persist in the overlay + usb-hemlock/etc/uca/.
# Boot only brings the already-configured service up and logs reachability.
# Strict compute-only access: no host file exposure, no rule changes here.
if [ -f "$USB_MNT/usb-hemlock/etc/uca/compute-access.conf" ] || systemctl is-enabled ssh >/dev/null 2>&1 || systemctl is-enabled sshd >/dev/null 2>&1; then
    systemctl start ssh >/dev/null 2>&1 || systemctl start sshd >/dev/null 2>&1 || true
    log "ssh: configured access honored (menu-managed; rules untouched)"
    ip -4 addr show scope global 2>/dev/null | awk '/inet /{print "  reachable at: "$2}' | tee -a "$BOOT_LOG" || true
else
    log "ssh: not configured — set up via menu: USB Setup → SSH/compute access"
fi

# ── 5c. Shell experience + cleanup tasks — menu-configured, boot-honored ─────
# The menu (Alias Manager / Bash Profile / Persistence Manager → cleanup tasks)
# writes config to usb-hemlock/etc/uca/ — shared, or volumes/<name>/ for one
# data volume. Boot wires the ACTIVE volumes' config into login shells and
# runs any enabled cleanup tasks. Menu owns the config; boot only honors it.
UCA_ETC="$USB_MNT/usb-hemlock/etc/uca"

# Active data volumes this boot = persistence/*.dat currently loop-attached
# (the casper backend chosen at the Ventoy menu appears here too).
_active_vols=""
while read -r _loopdev _backfile; do
    case "$_backfile" in
        */persistence/*.dat) _active_vols="$_active_vols $(basename "$_backfile" .dat)" ;;
    esac
done <<EOF
$(losetup -nO NAME,BACK-FILE 2>/dev/null || true)
EOF

{
    echo "# generated by startup.sh each boot — shared then per-volume shell config"
    for f in bash_profile.sh bash_aliases.sh; do
        echo "[ -f '$UCA_ETC/$f' ] && . '$UCA_ETC/$f'"
    done
    for v in $_active_vols; do
        for f in bash_profile.sh bash_aliases.sh; do
            echo "[ -f '$UCA_ETC/volumes/$v/$f' ] && . '$UCA_ETC/volumes/$v/$f'"
        done
    done
} > /etc/profile.d/uca-shell.sh 2>/dev/null \
    && log "shell: profile.d drop-in written (volumes:${_active_vols:- none})" \
    || log "shell: could not write /etc/profile.d/uca-shell.sh"

# $1 = cleanup.conf, $2 = root the tasks act on ("/" = the booted system).
_run_cleanup() {
    [ -f "$1" ] || return 0
    log "cleanup: $1 -> $2"
    while IFS='=' read -r k s; do
        [ "$s" = "on" ] || continue
        case "$k" in
            APT_CACHE)      if [ "$2" = "/" ]; then apt-get clean >/dev/null 2>&1 || true; else rm -rf "$2"/var/cache/apt/archives/*.deb 2>/dev/null || true; fi ;;
            JOURNAL_VACUUM) [ "$2" = "/" ] && journalctl --vacuum-time=7d >/dev/null 2>&1 || true ;;
            TMP_DIRS)       find "$2/tmp" -mindepth 1 -mtime +3 -delete 2>/dev/null || true ;;
            PIP_CACHE)      rm -rf "$2"/root/.cache/pip "$2"/home/*/.cache/pip 2>/dev/null || true ;;
            NPM_CACHE)      rm -rf "$2"/root/.npm/_cacache "$2"/home/*/.npm/_cacache 2>/dev/null || true ;;
            OLD_LOGS)       find "$2/var/log" \( -name '*.gz' -o -name '*.[0-9]' \) -delete 2>/dev/null || true ;;
            *)              continue ;;
        esac
        log "cleanup:   $k done"
    done < "$1"
    return 0
}
_run_cleanup "$UCA_ETC/cleanup.conf" /
for v in $_active_vols; do
    _vconf="$UCA_ETC/volumes/$v/cleanup.conf"
    [ -f "$_vconf" ] || continue
    _loopdev=$(losetup -nO NAME,BACK-FILE 2>/dev/null | awk -v b="/$v.dat" 'index($2,b){print $1; exit}')
    _mp=$(findmnt -nr -o TARGET -S "$_loopdev" 2>/dev/null | head -1)
    [ -n "$_mp" ] || continue
    _run_cleanup "$_vconf" "$_mp"
    # casper-style volumes keep the rw layer under upper/ — clean there too
    [ -d "$_mp/upper" ] && _run_cleanup "$_vconf" "$_mp/upper"
done

# ── 6. Operator hooks (custom per-stick commands) ────────────────────────────
CUSTOM="$USB_MNT/usb-hemlock/etc/uca/custom-startup.sh"
if [ -f "$CUSTOM" ]; then
    log "custom: running usb-hemlock/etc/uca/custom-startup.sh"
    bash "$CUSTOM" >>"$BOOT_LOG" 2>&1 || log "custom: reported issues"
fi

log "=== startup complete ==="
