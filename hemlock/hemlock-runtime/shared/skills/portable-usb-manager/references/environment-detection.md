# Environment Detection Algorithm

## Overview
The universal portable bash configuration uses a multi-tier detection strategy to find the best location for persistent alias storage. This document details the detection algorithm, rationale, and customization points.

## Detection Priority Order

### Tier 1: Explicit Mount (`/mnt/usb-persistence`)
```bash
if [[ -d "/mnt/usb-persistence" && -w "/mnt/usb-persistence" ]]; then
    echo "/mnt/usb-persistence"
    return 0
fi
```
**Rationale**: Standard Linux convention for dedicated USB persistence partition. Highest priority because it's explicit and intentional.

### Tier 2: Systemd Mount Units
```bash
for mount in $(systemctl list-units --type=mount --no-legend 2>/dev/null | awk '$1 ~ /persistence/ {print $1}'); do
    local where=$(systemctl show "$mount" -p Where --value 2>/dev/null)
    [[ -d "$where" && -w "$where" ]] && { echo "$where"; return 0; }
done
```
**Rationale**: Modern Linux systems often auto-mount USB persistence via systemd. Queries active mount units with "persistence" in name.

### Tier 3: Media Mounts with Marker File
```bash
for media in /media/*/ /run/media/*/; do
    for m in "$media"*/; do
        [[ -d "$m" && -w "$m" && -f "$m/.usb-persistence-marker" ]] && { echo "$m"; return 0; }
    done
done
```
**Rationale**: Desktop environments auto-mount USB drives to `/media/$USER/$LABEL` or `/run/media/$USER/$LABEL`. The `.usb-persistence-marker` file is a deliberate flag placed by the user to designate this mount as the persistence root.

### Tier 4: Home Directory Flag File
```bash
if [[ -f "${HOME}/.usb-persistence-path" ]]; then
    local p=$(cat "${HOME}/.usb-persistence-path" 2>/dev/null)
    [[ -d "$p" && -w "$p" ]] && { echo "$p"; return 0; }
fi
```
**Rationale**: Allows explicit configuration without filesystem-level changes. User creates `~/.usb-persistence-path` containing the path.

### Tier 5: Home Directory Fallback
Returns empty string, triggering home directory fallback: `${HOME}/.bash_aliases_usb`

## Customization

### Adding Custom Detection Paths
```bash
_detect_persistent_storage() {
    # Add custom paths before standard checks
    if [[ -d "/custom/persistence" && -w "/custom/persistence" ]]; then
        echo "/custom/persistence"
        return 0
    fi
    
    # ... standard checks ...
}
```

### Creating Marker File on USB
```bash
# On USB root partition
touch ${USB_MOUNT}/USB_LABEL/.usb-persistence-marker
```

### Explicit Path File
```bash
# User creates this file
echo "/mnt/my-usb-persistence" > ~/.usb-persistence-path
```

## Environment Variables Set

| Variable | Description | Example |
|----------|-------------|---------|
| `USB_PERSISTENCE` | Detected persistence root or empty | `/mnt/usb-persistence` |
| `IS_USB_PERSISTENT` | `1` if USB detected, `0` otherwise | `1` |
| `USB_ALIAS_FILE` | Full path to alias file | `/mnt/usb-persistence/.bash_aliases_usb` |
| `USB_ALIAS_BACKUP_DIR` | Backup directory | `/mnt/usb-persistence/.alias_backups` |
| `USB_ALIAS_MANAGER` | Path to alias_manager.sh | `/mnt/usb-persistence/alias_manager.sh` |

## Testing Detection

```bash
# Test detection
_detect_persistent_storage

# Check all variables
alias-env

# Force re-detection
unset USB_PERSISTENCE IS_USB_PERSISTENT USB_ALIAS_FILE
source bash_enhanced.sh
```