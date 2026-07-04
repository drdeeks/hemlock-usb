#!/bin/bash
# Hemlock System Debloat Script
# Run with: sudo bash /home/drdeek/projects/hemlock/scripts/debloat.sh

echo "━━━ System Debloat ━━━"
echo ""

# Stop non-essential services
echo "── Stopping non-essential services ──"
for svc in gnome-remote-desktop kerneloops switcheroo-control colord unattended-upgrades avahi-daemon ModemManager cups cups-browsed accounts-daemon power-profiles-daemon thermald preload rsyslog; do
    systemctl stop $svc.service 2>/dev/null && echo "  ✓ $svc stopped" || echo "  - $svc (not running or not found)"
done

echo ""
echo "── Disabling non-essential services ──"
for svc in gnome-remote-desktop kerneloops switcheroo-control colord unattended-upgrades avahi-daemon ModemManager cups cups-browsed accounts-daemon power-profiles-daemon thermald preload rsyslog; do
    systemctl disable $svc.service 2>/dev/null && echo "  ✓ $svc disabled" || echo "  - $svc (not found)"
done

echo ""
echo "── Clearing system caches ──"
# Journal logs
journalctl --vacuum-size=10M 2>/dev/null && echo "  ✓ journal vacuumed to 10M"
# APT cache
apt-get clean 2>/dev/null && echo "  ✓ apt cache cleared"
# Thumbnail cache
rm -rf /root/.cache/thumbnails/* 2>/dev/null && echo "  ✓ root thumbnails cleared"
# Systemd coredumps
coredumpctl vacuum --max-use=10M 2>/dev/null && echo "  ✓ coredumps vacuumed"

echo ""
echo "── Docker cleanup ──"
docker system prune -af --volumes 2>/dev/null && echo "  ✓ docker pruned"

echo ""
echo "── Drop system caches (kernel pagecache) ──"
sync
echo 3 > /proc/sys/vm/drop_caches && echo "  ✓ pagecache dropped"

echo ""
echo "━━━ Done ━━━"
echo "Restart with: sudo systemctl start <service> to re-enable anything needed"
