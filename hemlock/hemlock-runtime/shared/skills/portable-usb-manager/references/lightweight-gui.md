# Lightweight GUI for USB Compute Environments

This reference documents the lightweight GUI setup for USB compute environments, providing drag-drop file viewing capabilities.

## Overview

For USB-based compute environments that need a graphical interface without the overhead of a full desktop environment.

## Recommended Stack

| Component | Package | Purpose |
|-----------|---------|---------|
| Window Manager | `lxqt-core` | Lightweight Qt-based desktop |
| File Manager | `pcmanfm-qt` | **Drag-drop file viewer**, Qt-based |
| Terminal | `qterminal` | Qt-based terminal emulator |
| Image Viewer | `lximage-qt` | Lightweight image viewer |
| Audio | `pavucontrol-qt` | Volume control |
| Compositor | `picom` | Transparency, shadows, effects |
| Session | `xorg xinit` | X11 display server |
| Panels | `lxqt-panel lxqt-runner` | Taskbar, app launcher |

## Installation (Phase 14 of initialize.sh)

```bash
# Install lightweight GUI
apt -y install --no-install-recommends \
    xorg xinit lxqt-core pcmanfm-qt lxqt-panel lxqt-runner \
    qterminal pavucontrol-qt lximage-qt
apt -y install --no-install-recommends picom
```

### What Each Component Provides

| Component | Feature |
|-----------|---------|
| `pcmanfm-qt` | **Drag-drop file operations**, USB drive mounting, file associations |
| `lxqt-core` | Minimal Qt desktop (panel, session, settings) |
| `picom` | Compositor for transparency, window shadows, fade effects |
| `qterminal` | Tabbed terminal emulator |
| `pavucontrol-qt` | Volume control for audio |
| `lximage-qt` | Lightweight image viewer |

## Drag-Drop Features

`pcmanfm-qt` (Qt port of PCManFM) provides:
- **Drag-drop between windows**
- **Drag-drop to/from USB drives**
- **Drag-drop to applications** (e.g., drag image to editor)
- **Copy/move context menu** on drop
- **USB auto-mount integration** via GVFS

## Auto-Start Configuration

```bash
# Option 1: Auto-login + auto-start X
# /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=-/sbin/agetty --autologin $USER --noclear %I $TERM

# ~/.xinitrc
exec startlxqt

# Option 2: Display manager (SDDM)
apt -y install sddm
systemctl enable sddm
```

## Minimal vs Full

| Profile | Packages | Size | Use Case |
|---------|----------|------|----------|
| **Minimal** | `pcmanfm-qt` only | ~20MB | Drag-drop only, no panel |
| **Standard** | LXQt core + pcmanfm-qt + picom | ~150MB | Usable desktop |
| **Full** | + themes, fonts, apps | ~400MB | Daily driver |

## USB-Specific Tweaks

```bash
# Disable compositor on VMs for performance
# (add to ~/.config/picom.conf or startup)
# backend = "glx"; vsync = false;

# USB drive auto-mount in pcmanfm-qt
# Requires: gvfs, gvfs-backends (installed as deps)

# Hide desktop icons (cleaner for kiosk)
gsettings set org.lxqt.desktop show-desktop-icons false
```

## Resource Usage

| Component | RAM (idle) | CPU (idle) |
|-----------|------------|------------|
| Xorg | ~100MB | <1% |
| LXQt panel | ~30MB | <1% |
| pcmanfm-qt | ~20MB | <1% |
| picom | ~10MB | ~1% |
| **Total** | **~160MB** | **~2%** |

## Headless Alternative (No GUI)

If no drag-drop file viewer needed, skip Phase 14 entirely and use CLI tools:

```bash
# USB file operations via CLI
ls ${USB_MOUNT}/
cp file.txt ${USB_MOUNT}/
rsync -av /src/ ${USB_MOUNT}/backup/
```

## Accessing GUI

### Local (Direct Boot)
1. Boot from USB
2. Auto-login → X11 → LXQt

### Remote (VNC)
```bash
# Install VNC server
apt -y install tigervnc-standalone-server

# Start VNC
vncserver :1 -geometry 1920x1080 -depth 24
# Connect via VNC client to IP:5901
```

### VM (QEMU)
```bash
# With GUI output
qemu-system-x86_64 -m 4G -enable-kvm \
  -drive file=/dev/sdX,format=raw,if=virtio \
  -display gtk,gl=on
```

## Related

- `initialize.sh` Phase 14: GUI installation
- `references/usb-setup-assistant-fixes.md`: Lightweight GUI pattern
- `references/universal-portable-shell-utilities.md`: Portable shell patterns