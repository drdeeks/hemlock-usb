#!/usr/bin/env bash
# =============================================================================
# startup.sh — USB-Hemlock boot orchestrator (runs as root via rc.local)
# Chain: host compute → tooling.dat (the bridge) → hemlock.
# Sequence: identity log → mount tooling (ALWAYS) → first-boot essentials
#           → continuous tooling update → operator hooks.
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

# ── 3. Mount the tooling volume — ALWAYS. It is the bridge for everything. ──
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
        log "tooling: MOUNT FAILED — downstream volumes will lack the bridge"
    fi
else
    log "tooling: $TOOLING_DAT missing — create it via the menu (Persistence Manager)"
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

# ── 6. Operator hooks (custom per-stick commands) ────────────────────────────
CUSTOM="$USB_MNT/usb-hemlock/etc/uca/custom-startup.sh"
if [ -f "$CUSTOM" ]; then
    log "custom: running usb-hemlock/etc/uca/custom-startup.sh"
    bash "$CUSTOM" >>"$BOOT_LOG" 2>&1 || log "custom: reported issues"
fi

log "=== startup complete ==="
