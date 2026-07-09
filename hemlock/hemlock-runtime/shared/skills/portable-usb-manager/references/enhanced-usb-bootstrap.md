# Enhanced USB Bootstrap - 27 Phase Initialize.sh

This reference documents the enhanced `config/initialize.sh` with 27 phases for comprehensive USB compute environment setup.

## Overview

The enhanced `config/initialize.sh` provides a complete Ubuntu system bootstrap for USB compute environments, with all fixes and patterns integrated.

## 27 Phases

| Phase | Component | Description |
|-------|-----------|-------------|
| 0 | Sudo Enforcement & Caching | EUID check, cache_sudo_password(), auto-cleanup |
| 1 | System Update & Essentials | ca-certificates, curl, wget, jq, build-essential |
| 2 | Node.js LTS | NodeSource with Ubuntu codename fix (noble) |
| 3 | Bun | Minimal binary install |
| 4 | Python + pip + venv | python3, python3-venv, python3-dev |
| 5 | Docker + Compose Plugin | docker, docker-compose-plugin, usermod |
| 6 | Foundry (forge) | Minimal install |
| 7 | Hardhat + Ethers | Global npm install |
| 8 | llama.cpp deps | cmake, openblas, cython |
| 9 | Tailscale | Secure remote access |
| 10 | SSH Server + Keys | Auto-enable, ed25519 keygen |
| 11 | TTS (tts-cli) | Speech synthesis |
| 12 | SQLite CLI | Database tool |
| 13 | Chromium Minimal | Headless browser |
| 14 | Lightweight GUI | LXQt + pcmanfm-qt (drag-drop), picom |
| 15 | Tauri Deps | libwebkit2gtk, libssl, libgtk |
| 16 | Transmission | Daemon + cli + gtk |
| 17 | Hugging Face CLI | ML model hub |
| 18 | dotenv-cli + npm globals | dotenv-cli global |
| 19 | Docker Compose Plugin | docker-compose-plugin |
| 20 | QEMU/KVM + libvirt | USB VM boot, virt-manager |
| 21 | Utilities | htop, neovim, fzf, ripgrep, eza, bat, ncdu |
| 22 | Environment Config | PATH exports, USB shortcuts, aliases |
| 23 | Rust/Cargo | For llama.cpp |
| 24 | Go | v1.22.5 |
| 25 | USB Automation Dirs | backups, ISOs, config, SSH hosts, aliases |
| 26 | ComfyUI (optional) | comfy-cli install, hardware check |
| 27 | Cleanup & Hardening | autoremove, autoclean, apt lists |

## Key Features Integrated

- **NodeSource 404 Fix**: Uses `$UBUNTU_CODENAME` (noble)
- **Sudo Enforcement & Caching**: EUID check + cache_sudo_password()
- **Lightweight GUI**: LXQt + pcmanfm-qt (drag-drop) + picom
- **QEMU/KVM**: USB VM boot ready
- **ComfyUI Optional**: comfy-cli install with hardware check
- **USB Automation Dirs**: backups, ISOs, config, SSH hosts, aliases
- **Environment Config**: PATH exports, USB shortcuts, aliases

## Usage

```bash
# Full bootstrap
sudo bash config/initialize.sh

# Dry run
DRY_RUN=true sudo bash config/initialize.sh
```

## Phase 14: Lightweight GUI Details

For drag-drop file viewer on USB:

```bash
# Phase 14 installs:
apt -y install --no-install-recommends \
    xorg xinit lxqt-core pcmanfm-qt lxqt-panel lxqt-runner \
    qterminal pavucontrol-qt lximage-qt
apt -y install --no-install-recommends picom

# Features:
# - pcmanfm-qt: drag-drop file manager
# - lxqt-core: lightweight desktop
# - picom: compositor for transparency
# - qterminal: terminal emulator
# - lximage-qt: lightweight image viewer
```