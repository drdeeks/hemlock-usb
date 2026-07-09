# USB-Hemlock Unified Compute Platform

![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-x86__64%20Linux-informational?logo=linux&logoColor=white)
![Boot](https://img.shields.io/badge/boot-Ventoy%20multi--boot%20%2B%20persistence-orange)
![Runtime](https://img.shields.io/badge/AI%20runtime-OpenClaw%20%2B%20Hermes%20%2B%20MCP-6f42c1)
![Docker](https://img.shields.io/badge/container-opt--in%20Docker-2496ED?logo=docker&logoColor=white)
![Python](https://img.shields.io/badge/tooling-Python%203.8%2B%20stdlib-blue)
![Host](https://img.shields.io/badge/host-no%20traces%20after%20bridge-critical)
![Interface](https://img.shields.io/badge/UI-whiptail%20TUI%20%2B%20text%20fallback-success)

> **Enterprise-grade portable Linux + AI agent orchestration on a single USB.**
> Boots anywhere. No traces on the host after initial bridge setup.

> **Two separate, individually owned systems live in this repo — each usable on its own, for
> more than one purpose:**
> 1. **The USB compute platform** (this root: `menu.sh`, `usb/`, `blueprint/`) — a portable
>    multi-boot Linux workstation. Works with or without any AI runtime on it.
> 2. **The Hemlock agent runtime** ([`hemlock/hemlock-runtime/`](hemlock/hemlock-runtime/)) —
>    a self-hosted multi-agent Docker runtime with its own README, docs, and lifecycle.
>    Runs on any Docker host; it does not need the USB.
>
> **Two isolated ways to run the AI runtime, your choice:** (A) deploy to a Ventoy USB via the
> bundled `portable-usb-manager` skill, or (B) just build and run the container directly
> (`hemlock/hemlock-runtime/`, `docker build`) — a purpose-built rebuild, kept fully isolated on
> your machine. Neither path depends on the other; they're designed as isolated aspects.

A self-contained compute environment that:

- **Boots from any Ventoy-formatted USB** on any x86_64 machine
- **Adapts dynamically** to whatever machine you plug into (`/media/$USER/...`, `/run/media/...`, `/mnt/...`, `/Volumes/...`)
- **Routes every install** (aliases, bash profile, antivirus state, system cleanup) to the USB rather than the host when in USB mode — the host stays untouched after the one-time boot bridge
- **Supports multi-volume persistence** (rootfs overlay + Hemlock data + models + per-project data, each as a separate `.dat` file mapped per-ISO via `ventoy.json`)
- **Reserves 256 MiB on every USB** for configs/scripts/profiles regardless of total size, enforced silently
- **Opt-in Hemlock container runtime** for AI agent orchestration (Docker, off by default)

All operations route through one interactive menu (`menu.sh`) with whiptail TUI + text fallback, dry-run at every layer, and a typed `HOST` confirmation gate for any destructive write the host filesystem.

---

## What's New (July 2026)

| Change | Headline |
|---|---|
| **17-skill validated seed** | The runtime ships 17 skills (11 new — identity, crews, kanban, knowledge, wake-up, hackathon, tool-enforcement, minimal-runtime, …), every one passing skill-creator enterprise validation; the canonical skills repo auto-commits version bumps via a guardrail monitor cron. |
| **Agent identity layer** | `workspace-template/.agent/`: identity constitution loaded at t=0 (injected right after SOUL.md), 3 internalized habits, enforcer config; `agent-create.sh` stamps a sha256 identity hash into `<agent-id>.json`. |
| **Yank-aware mount lifecycle** | Every loop mount in menu.sh/install.sh: sync-before-umount, EXIT-trap sweep (no leaked mounts on crash/Ctrl-C), `e2fsck -p` journal replay before rw mounts, startup detection of mounts orphaned by surprise removal, unconditional sync on menu exit (exFAT profile writes). |
| **Boot-profile autoload fixed + in use** | Default profile (`default: true`) in `usb-hemlock/profiles/` now correctly resolves `primary.file` against the mount; verified live with the registered `hemlock-main` profile. |
| **One installer** | `hemlock/hemlock-runtime/install.sh`: `--variant full/lean/minimal`, `--load <tar>`, `--usb`, `--native`, `--release` (pulls latest GitHub release, dynamic options); host-awareness preflight; reachable via hidden `-H` menu. |
| **Gateway port 1437** | Hemlock's gateway moved off 18789 — coexists with a host OpenClaw without collision; host env isolation (`run-native.sh` refuses foreign `OPENCLAW_*`/`HERMES_*`). |
| **validate-all-skills fixed** | Works on the host tree (`shared/skills` fallback) and no longer dies on `set -e` + `((var++))`; reports 17/17 valid. |

## What's New (Releases CL-026..CL-034, June 2026)

| Tag | Headline |
|---|---|
| **CL-026** | Menu TUI hardened — SIGINT confirm-exit, error-resilient dispatch wrapper, USB-first startup wizard, multi-volume persistence |
| **CL-030** | Top-level USB/HOST mode selector. Silent USB detection → auto-host if none, prompt if any. Every component install routes through `_uca_install_root()`. `clean-local.sh` blocked in USB mode. |
| **CL-031** | USB detection now finds *any* USB (Ventoy, blank, formatted) and classifies each. Empty card readers filtered. Root disk excluded. |
| **CL-033** | 256 MiB reservation enforced on every persistence create/resize. Pre-flight space validation with clear error messages. |
| **CL-034** | Primary persistence detection now label-aware — picks the `casper-rw` overlay over alphabetical first. Existing-state detection verified on multi-volume layouts. |

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Ideal Setup Steps](#ideal-setup-steps)
3. [Architecture](#architecture)
4. [Directory Structure](#directory-structure)
5. [The Master Menu](#the-master-menu)
6. [USB Setup Flow](#usb-setup-flow)
7. [Ventoy Persistence](#ventoy-persistence)
8. [Startup Management](#startup-management)
9. [Persistence Management](#persistence-management)
10. [Bash Profile Management](#bash-profile-management)
11. [Per-Device Configuration](#per-device-configuration)
12. [Component Reference](#component-reference)
13. [CLI Reference](#cli-reference)
14. [Environment Variables](#environment-variables)
15. [Logging](#logging)
16. [Testing Suite](#testing-suite)
17. [Feature Flags](#feature-flags)
18. [Troubleshooting](#troubleshooting)
19. [Known Limitations](#known-limitations)
20. [Development & Contributing](#development--contributing)

---

## Quick Start

```bash
# 1. Clone + cd
git clone <repo-url> usb-hemlock
cd usb-hemlock/usb-hemlock-split

# 2. Sanity-check the suite
bash usb/tests/run-all.sh

# 3. Launch the master menu (the only entry point you need)
bash menu.sh
```

On launch you'll see one of two paths:

- **No USB plugged in** → menu opens silently in **HOST mode** (local-enhancement subset only: bash profile, aliases, system manager, cleanup, validation). USB-specific options are hidden.
- **USB plugged in** → menu prompts: **`1) USB`** (install everything to the USB; host untouched after initial bridge) or **`2) HOST`** (local only, USB never touched). Default is USB.

Skip the prompt with a flag:

```bash
bash menu.sh --usb            # force USB mode
bash menu.sh --host           # force HOST mode
bash menu.sh --mode usb       # long form
UCA_MODE=usb bash menu.sh     # env-var equivalent
```

---

## Mode Selection (USB vs HOST)

The platform has one top-level switch that decides where everything lands.

### USB mode (`--mode usb`)

Every configurable install lands inside the USB persistence layout:

```
<usb-mount>/usb-hemlock/etc/uca/
  bash_aliases.sh        ← Alias Manager writes here
  bash_profile.sh        ← Bash Profile Manager copies bash_enhanced.sh here
  alias_backups/
<usb-mount>/usb-hemlock/var/log/system_toolkit/      ← Antivirus logs
<usb-mount>/usb-hemlock/var/quarantine/system_toolkit/ ← Quarantined files
<usb-mount>/usb-hemlock/profiles/*.json              ← Boot profiles
<usb-mount>/persistence/*.dat                        ← Persistence volumes
```

The **only** writes that ever touch the host filesystem in USB mode are the explicit "initial bridge" actions:

1. One `source <usb>/.../bash_profile.sh` line appended to host `~/.bashrc` so the operator's shell picks up the USB profile (added once, idempotent).
2. udev rules at `/etc/udev/rules.d/99-usb-hemlock-mount.rules` if you opt into Auto-Mount (menu option 6).
3. The `/usr/local/bin/virus` shim + apt packages if you opt into the antivirus toolkit (menu option 5 → "Install Antivirus"). Logs/quarantine still land on the USB; the toolkit binary itself has to live on the host because cron needs root.

Everything else — alias edits, SSH host changes, profile files, ventoy.json — is rewritten on the USB only.

`clean-local.sh` is **hard-blocked** in USB mode (refuses with `[BLOCKED]` exit 12). Override with `--force-host` or re-run in HOST mode if you actually want to clean the host.

### HOST mode (`--mode host`)

Local enhancements only. Same scripts, same UX, but the install root is `$XDG_CONFIG_HOME/usb-compute-automation/` (`~/.config/...`). USB-specific options (1, 2, 6, 8, 9, 11, 12, 17, 19) disappear from the menu.

---

## Dynamic USB Detection

Three-method scan — works on any Linux distro, any USB layout, any mount convention:

| Signal | What it catches |
|---|---|
| `lsblk -d -o NAME,TRAN,SIZE` (TRAN=usb, size>0) | Authoritative on Linux, standard USB sticks |
| `/sys/block/*/removable=1` (size>0, not optical) | USB-attached drives behind bridges that hide TRAN |
| `udevadm info ID_BUS=usb` (size>0) | Hot-plugged drives `/sys` hasn't fully labelled yet |

Plus filters: root disk excluded (via `findmnt /` + `lsblk PKNAME`), 0-sector devices skipped (empty card readers / hub placeholders), optical drives (`sr0`) skipped, deduplication preserves discovery order.

Each device is classified:

| Class | Meaning | What option 1 (USB Setup) does |
|---|---|---|
| `ventoy` | Has Ventoy/VTOYEFI partitions | Use as-is |
| `formatted` | Has a known FS (ext/exfat/vfat/ntfs/btrfs/xfs/f2fs) but not Ventoy | **REFORMATS** the drive |
| `blank` | No recognized FS | Fresh Ventoy install |

Mount lookup follows the same dynamic chain — `VENTOY_MOUNT` env first, then `detect_ventoy_mount`, then glob fallbacks: `/media/${user}/Ventoy`, `/run/media/${user}/Ventoy`, `/media/*/Ventoy`, `/run/media/*/Ventoy`, `/mnt/ventoy`, `/Volumes/Ventoy` (mac).

**Concrete:** plug your USB into a fresh machine where you're user `alice`, GNOME auto-mounts to `/run/media/alice/MyDrive` — the resolver finds it, computes install root as `/run/media/alice/MyDrive/usb-hemlock/etc/uca/`, your aliases/profile/configs all land there. Zero code changes.

---

## Multi-Volume Persistence

You can stack as many persistence volumes on one USB as space allows. Each is a separate `.dat` file inside `<usb>/persistence/`, formatted ext4 with its own label. Typical layout:

```
<usb>/persistence/
  ubuntu-persistence.dat   20 GiB  label=casper-rw  ← rootfs overlay (Ubuntu live boot)
  hemlock.dat               1 GiB  label=hemlock    ← Hemlock container data
  models.dat              200 GiB  label=models     ← GGUF/safetensors LLM weights
  data-1.dat               40 GiB  label=projects   ← per-project data
```

Create a new one via **Menu option 9 → 2 (Create persistence)**. The wizard:

1. Lists every existing `.dat` so you see what's already there
2. Auto-suggests a non-colliding filename (`ubuntu-persistence.dat` → `hemlock.dat` → `models.dat` → `data.dat` → `data-1.dat` …)
3. Asks for an ext4 label (refuses `casper-rw` for non-primary volumes — that's reserved)
4. Shows max available size after subtracting **the 256 MiB reservation** + every existing volume
5. **Rejects** any size below 256 MiB or above the max with a precise reason
6. `dd` + `mkfs.ext4` only after pre-flight validation passes

The 256 MiB reservation is a hard floor regardless of USB size — it keeps room for `usb-hemlock/etc/uca/` configs, `usb-hemlock/profiles/`, scripts, and `ventoy/ventoy.json` even on cramped drives. Override only by editing `UCA_RESERVED_BYTES` (not recommended; the value buys you the ability to rescue/reconfigure without erasing).

### Mapping volumes to ISOs (ventoy.json)

Ventoy reads `<usb>/ventoy/ventoy.json` at boot to decide which persistence volume to attach to each ISO. Example:

```json
{
  "persistence": [
    { "image": "/ubuntu-24.04-desktop.iso", "backend": "/persistence/ubuntu-persistence.dat" },
    { "image": "/kali-2026-live.iso",       "backend": "/persistence/hemlock.dat" },
    { "image": "/parrot-os.iso",            "backend": "/persistence/models.dat" }
  ]
}
```

Each ISO at boot mounts its mapped `.dat` as `casper-rw` automatically. Without an entry, Ventoy uses no persistence for that ISO (live read-only).

Manage this through **Menu option 9 → 9 (Ventoy.json doctor)** which validates the JSON, checks every referenced ISO + backend exists, and surfaces unmapped persistence volumes.

### Boot profiles (richer per-boot config)

Beyond raw ventoy.json mapping, USB-Hemlock can store **boot profiles** in `<usb>/usb-hemlock/profiles/`. A profile JSON describes:

```json
{
  "device":  "/dev/sdc",
  "iso":     "/ubuntu-24.04-desktop-amd64.iso",
  "primary": { "file": "/persistence/ubuntu-persistence.dat", "label": "casper-rw" },
  "data_volumes": [
    { "file": "/persistence/hemlock.dat", "mount": "/var/lib/hemlock", "role": "container-data" },
    { "file": "/persistence/models.dat",  "mount": "/srv/models",      "role": "model-cache" }
  ],
  "env":     { "HEMLOCK_ENABLED": "true", "OPENROUTER_API_KEY": "..." },
  "default": true
}
```

When `default: true`, the profile auto-loads at `menu.sh` launch and pre-populates `SELECTED_DEVICE`, mount-time options for data volumes, and `/etc/environment` entries inside the booted USB. Create/edit profiles via **Menu option 12 (Device Config)**.

---

## Ideal Setup Steps

Everything is done through the master menu. These steps show the menu path for each action.

### Step 1: Verify Host Prerequisites

```bash
# Check required tools
bash --version        # Need Bash 4+ (5.2+ recommended)
jq --version          # Need jq 1.6+ (1.7 confirmed)
docker --version      # Need Docker 20+ (29.6 confirmed)
docker compose version # Need Compose v2

# If missing, install on Ubuntu/Debian:
sudo apt update && sudo apt install -y jq docker.io docker-compose-v2 python3

# If missing, install on macOS:
brew install jq docker python3
```

### Step 2: Launch the Master Menu

```bash
bash menu.sh
# → The menu auto-detects USB devices at startup
# → If a Ventoy USB is found, it is selected automatically
# → If not found, use option 11 (USB Device Setup) to select one manually
```

### Step 3: Select Your USB Device

```
menu.sh → Option 11: USB Device Setup [USB]
```

The setup flow will:
1. Scan for block devices using `lsblk`
2. Auto-detect Ventoy-labeled partitions via `lsblk`, `blkid`, and `/proc/mounts`
3. If exactly one Ventoy device is found, prompt to confirm
4. If multiple are found, present a numbered list to choose from
5. If none are found, offer manual entry or skip

You can also set the device manually before launching:
```bash
export SELECTED_DEVICE="/dev/sdb"   # Replace with your device
bash menu.sh
```

### Step 4: Install Ventoy to USB

```
menu.sh → Option 1: USB Setup Assistant [USB]
        → Option 2: Manage Ventoy USB Drive
        → Option 1: Install Ventoy (WARNING: erases USB)
```

### Step 5: Create Persistence

```
menu.sh → Option 1: USB Setup Assistant [USB]
        → Option 2: Manage Ventoy USB Drive
        → Option 3: Create persistence
        → Enter size in GB (default: 8, recommended: 32+ for dev work)
```

### Step 6: Copy ISOs to USB

```bash
# Copy any bootable ISO to the Ventoy USB root
cp ~/Downloads/ubuntu-24.04-desktop-amd64.iso /media/$USER/Ventoy/
# Ventoy auto-detects ISOs at boot — no configuration needed
```

### Step 7: Initialize Config

```
menu.sh → Option 2: Unified CLI (usbctl) [USB]
        → Option 7: config init
        → Option 5: config host-id
```

### Step 8: Install Build Essentials (Optional)

```
menu.sh → Option 7: Build Essentials [HOST]
```

Installs llama.cpp, ollama, rust, foundry, hardhat, playwright, tauri, bun, tailscale, node, python. Requires root.

### Step 9: Deploy Hemlock (Optional)

```
menu.sh → Option 19: Hemlock Manager → Option 3: Master Deploy (DEPLOY.sh)
```

Full stack deployment: system + USB + Hemlock. Requires root.

### Step 10: Verify Everything Works

```bash
# Run the full test suite
bash usb/tests/run-all.sh
# Expected: 201 passed, 0 failed, 1 skipped

# Or via the menu:
# menu.sh → Option 13: Run Validation [ALL]
```

---

## Architecture

The system has two core subsystems that work together, bridged by a singular master menu.

### USB Compute Automation (`usb/`)

Portable Linux environment that boots from any USB drive via Ventoy. Provides:

- **Persistent workspaces** — ext4 filesystem with `casper-rw` label (Ubuntu casper convention)
- **SSH host management** — `~/.ssh/hosts_usb` pipe-delimited store with config generation
- **Alias management** — `~/.bash_aliases_usb` with full CRUD, backup, import/export
- **System health monitoring** — disk, network, services, processes, logs
- **Auto-mount** — udev rules + systemd service for automatic USB mounting
- **Build toolchain installer** — llama.cpp, ollama, rust, foundry, hardhat, playwright, tauri, bun, tailscale, node, python
- **CLI dispatcher** — `usbctl` for scripted/automated operations

### Hemlock Agent Runtime (`hemlock/`)

Dockerized AI agent orchestration platform. Provides:

- **Agent lifecycle management** — create, start, stop, monitor, import, export, delete
- **Crew management** — A2A protocol: join, leave, dissolve, start, stop, monitor
- **Runtime validation** — health checks, Hermes Doctor, Docker env validation
- **Security hardening** — apply, check status, reset
- **Staging bridge** — file transfers between host and container via `volumes/imports/.request`
- **84 agent skill packages** — pre-built capabilities for common tasks

### The Master Menu (`menu.sh`)

**The singular entry point for ALL components.** One command gives you access to every USB, Hemlock, and system feature. The menu:

- **Auto-detects USB devices** at startup — no manual `export SELECTED_DEVICE` needed
- **Provides interactive device setup** (option 11) — scans, lists, and selects Ventoy drives
- **Shows device status** at the top of every menu render — mount point, persistence size
- **Delegates to the correct component** for each task
- **Honors `--dry-run`** for safe preview of all mutations
- **Falls back to text mode** if whiptail is unavailable

### Three Execution Models

The codebase uses three distinct execution patterns:

| Model | Files | Characteristics |
|-------|-------|-----------------|
| **A: Sourceable lib/** | `usb/lib/*.sh`, `cli/usbctl`, `scripts/alias_manager.sh` | Double-source guard, overridable colors, `run_or_dry` mutations, `jq` dependency |
| **B: Self-contained monoliths** | `usb-setup-assistant.sh`, `sysman.sh`, `ssh_host_manager.sh` | Re-declare own `print_*`/`run_or_dry`/colors, do NOT source `lib/` |
| **C: In-container runtime** | `hemlock-runtime/scripts/runtime.sh`, `scripts/hemlock` | Runs inside Docker, host files not visible, staging bridge for transfers |

---

## Directory Structure

```
usb-hemlock-split/
├── menu.sh                    # ★ MASTER ENTRY POINT — auto-detects USB, 18-option menu (+1 with --hemlock)
├── README.md                  # This file
├── AGENTS.md                  # Agent instruction file
├── CHANGELOG.md               # Append-only change log
├── feature-flags.json         # Feature flag registry (29 flags, all disabled by default)
│
├── blueprint/                 # Enterprise blueprint + enforcement checklist
│   ├── blueprint.md           # Master specification (48/48 ENTERPRISE GRADE)
│   ├── checklist.md           # 8 phases, 21 modules, enforcement checklist
│   ├── project.json           # Phase registry
│   └── assignments.json       # Agent role assignments
│
├── usb/                       # USB COMPUTE AUTOMATION
│   ├── cli/usbctl             # Unified CLI dispatcher (sources all lib/)
│   ├── lib/                   # Sourceable libraries (7 modules)
│   │   ├── core.sh            # Colors, logging, confirm, run_or_dry, safe_exec, traps
│   │   ├── logging.sh         # Structured logging with file output, rotation, levels
│   │   ├── platform.sh        # OS/virtualization detection, tool selection
│   │   ├── usb.sh             # Ventoy mount (5 fallbacks), persistence helpers
│   │   ├── config.sh          # JSON config via jq + host-id generation
│   │   ├── menu.sh            # Stack-based menu_loop framework
│   │   └── validation.sh      # Health checks + self_heal
│   ├── scripts/
│   │   ├── alias_manager.sh   # ~/.bash_aliases_usb manager (uses lib/)
│   │   ├── ssh_host_manager.sh # ~/.ssh/hosts_usb manager (self-contained)
│   │   ├── setup-essentials-enhanced.sh  # Build toolchain installer (needs root)
│   │   ├── setup-usb-compute.sh          # Older standalone provisioning
│   │   ├── bash_enhanced.sh              # Enhanced .bashrc profile
│   │   ├── clean-local.sh                # System cleanup (called by sysman)
│   │   └── install-antivirus.sh          # Antivirus installer
│   ├── usb-setup-assistant.sh # Interactive Ventoy installer (self-contained)
│   ├── sysman.sh              # System health/repair dashboard (self-contained)
│   ├── hemlock-tui            # Wrapper to launch Hemlock TUI
│   ├── usb-automount/         # systemd + udev auto-mount installer
│   ├── config/initialize.sh   # Ubuntu one-time bootstrap
│   ├── volumes/ventoy/        # Bundled Ventoy tarball (20MB)
│   ├── tests/                 # Testing suite (14 scripts, 201 assertions)
│   └── README.md              # USB component documentation
│
└── hemlock/                   # HEMLOCK AGENT RUNTIME
    ├── DEPLOY.sh              # Master deploy (system + USB + Hemlock, 3-phase)
    ├── hemlock-tui            # Wrapper to launch Hemlock TUI
    ├── hemlock-runtime/       # Docker runtime
    │   ├── scripts/hemlock    # Host CLI entrypoint
    │   ├── scripts/runtime.sh # In-container TUI menu (1334 lines)
    │   ├── docker-compose.runtime.yml
    │   ├── Dockerfile.runtime
    │   └── Makefile
    ├── hemlock-minimal/
    │   └── skills/            # 84 agent skill packages
    └── README.md              # Runtime documentation
```

---

## The Master Menu

The single entry point for ALL components. Provides access to every USB and Hemlock feature through one interactive interface.

### Launching

```bash
bash menu.sh                     # Interactive menu (whiptail or text fallback)
bash menu.sh --text              # Force text-based menu
bash menu.sh --dry-run           # Preview mode — no mutations
bash menu.sh --dry-run --text    # Both flags combined
bash menu.sh --log-file PATH     # Custom log file
bash menu.sh --help              # Usage info
```

### Menu Options (18 default; 19 with --hemlock)

The menu displays the current USB device status at the top, then presents all options.

#### USB Components (Options 1-7)

| # | Component | Target | Description |
|---|-----------|--------|-------------|
| 1 | USB Setup Assistant | [USB] | Interactive Ventoy installer (14-option submenu) |
| 2 | Unified CLI (usbctl) | [USB] | USB/config/alias/validate subcommands |
| 3 | Alias Manager | [HOST] | Manage `~/.bash_aliases_usb` |
| 4 | SSH Host Manager | [HOST] | Manage `~/.ssh/hosts_usb` |
| 5 | System Manager | [HOST] | Health/network/disk/services dashboard |
| 6 | USB Auto-Mount | [HOST] | udev + systemd setup |
| 7 | Build Essentials | [HOST] | Install dev toolchain |

#### Configuration (Options 8-12)

| # | Component | Target | Description |
|---|-----------|--------|-------------|
| 8 | Startup Manager | [USB+HOST] | Boot scripts & autostart across persistence + host |
| 9 | Persistence Manager | [USB] | Create/resize/browse/check persistence partitions |
| 10 | Bash Profile Manager | [HOST] | Install/edit/view enhanced bash profile + aliases |
| 11 | USB Device Setup | [USB] | Auto-detect and select your Ventoy USB drive |
| 12 | Device/Boot Profiles | [HOST/USB] | USB-resident profiles + autoboot + manifest |

#### System (Options 13-15)

| # | Component | Target | Description |
|---|-----------|--------|-------------|
| 13 | Run Validation | [ALL] | Validate all components |
| 14 | Diagnostics | [HOST] | System info & config |
| 15 | View Logs | [HOST] | Log viewer & search |

#### Access & Configuration (Options 16-18)

| # | Component | Target | Description |
|---|-----------|--------|-------------|
| 16 | USB Paths & Environment | [HOST] | Configure the file-tree schema, paths & env vars (sourced `usb-paths.conf` / `usb-env.conf`) |
| 17 | USB Access & Boot | [USB+HOST] | Shell/chroot into persistence, edit rc.local, QEMU headless(+SSH)/GUI/ISO boot, SSH-into-VM, install tooling into USB, OS-aware autostart |
| 18 | Toggle Dry-Run | — | Enable/disable preview mode |

#### Hemlock (Option 19) — opt-in via `--hemlock` or `-H`

| # | Component | Target | Description |
|---|-----------|--------|-------------|
| 19 | Hemlock Manager | [CONTAINER] | Single submenu consolidating the former separate Hemlock TUI, Status, and Master Deploy entries. Hidden by default — pass `--hemlock` (or `-H`, or `HEMLOCK_ENABLED=true`) to reveal. |

#### Foundation (Option 20)

| # | Component | Target | Description |
|---|-----------|--------|-------------|
| 20 | Tooling Volume | [USB] | Optional toolchain bridge (`persistence/tooling.dat`): create/refresh, hf-cli, updater, model tools. Optional since CL-041 — minimal sticks run without it. |

**Install policy:** dev tooling installs onto the USB persistence by default;
host installs (e.g. QEMU/KVM for headless boot + port-forwarding) are only done
after an explained, OS-aware prompt.

### Component Targets

Each menu option is labeled with what it affects:

- **[USB]** — Operations on the USB drive itself (Ventoy, persistence, device detection)
- **[HOST]** — Operations on the host machine (aliases, SSH, system health, services)
- **[CONTAINER]** — Operations inside the Hemlock Docker container (agents, crews)
- **[ALL]** — Cross-cutting operations that touch multiple targets
- **[USB+HOST]** — Operations spanning both USB persistence and host system

---

## USB Setup Flow

### Option 1: Interactive Setup (Recommended)

```bash
bash menu.sh        # → Option 1: USB Setup Assistant
```

The USB Setup Assistant provides a 14-option menu:

1. **Setup USB Compute Automation System** — Complete setup
2. **Manage Ventoy USB Drive** → submenu:
   - Install Ventoy (WARNING: erases USB)
   - View inventory
   - Create persistence (ext4, casper-rw label)
   - Resize persistence
   - Browse persistence
3. **Setup VM Auto-Boot** — Headless configuration
4. **Install Build Essentials** — Dev toolchain
5. **Configure Network/SSH** — Network access
6. **View System Status** — Health dashboard
7. **Backup and Recovery** — Backup tools
8. **System Cleanup** — Diagnostics
9. **Manage Custom Aliases** — Alias CRUD
10. **Manage SSH Hosts** — SSH CRUD
11. **Access USB Persistent Terminal** — chroot into USB
12. **Copy File to USB** — Host→USB transfer
13. **Hemlock Agent Orchestration** — Opens Hemlock TUI
14. **Exit**

### Option 2: CLI

```bash
export SELECTED_DEVICE="/dev/sdb"    # Identify via lsblk
bash usb/cli/usbctl usb detect       # List devices
bash usb/cli/usbctl usb mount        # Mount Ventoy
bash usb/cli/usbctl config init      # Initialize config
bash usb/cli/usbctl config host-id   # Generate host ID
bash usb/cli/usbctl validate all     # Run validations
```

---

## Ventoy Persistence

### How Persistence Works

Ventoy supports persistence via a `.dat` file on the USB drive. When booting Ubuntu (or derivatives), Ventoy automatically detects a file named `casper-rw` in the `/persistence/` directory and mounts it as an overlay filesystem.

### Creating Persistence

**Method 1: Via USB Setup Assistant (Recommended)**
```bash
bash menu.sh   # → Option 1 → Option 2 → Option 3: Create persistence
```

This creates:
- `/persistence/ubuntu-persistence.dat` — ext4 filesystem with `casper-rw` label
- Default size: 8 GB (configurable)
- Automatically injects `etc/rc.local` for autostart

**Method 2: Manual Creation**
```bash
# 1. Mount the Ventoy USB
sudo mount /dev/sdb1 /mnt/ventoy

# 2. Create the persistence file
dd if=/dev/zero of=/mnt/ventoy/persistence/ubuntu-persistence.dat bs=1M count=8192

# 3. Format with ext4 and casper-rw label (required by casper)
mkfs.ext4 -F -L casper-rw /mnt/ventoy/persistence/ubuntu-persistence.dat

# 4. Loop-mount to inject rc.local
sudo mount -o loop /mnt/ventoy/persistence/ubuntu-persistence.dat /mnt/test
cat << 'EOF' | sudo tee /mnt/test/etc/rc.local
#!/bin/bash
# Auto-start script for USB persistence
exit 0
EOF
sudo chmod +x /mnt/test/etc/rc.local
sudo umount /mnt/test
```

### Ventoy Built-in Persistence Modes

Ventoy supports multiple persistence configurations:

1. **Single persistence file** (default for this system)
   - Path: `/persistence/ubuntu-persistence.dat`
   - Label: `casper-rw` (critical — casper looks for this exact label)
   - Format: ext4

2. **Multiple persistence files**
   - Ventoy supports multiple `.dat` files with different labels
   - Edit `/ventoy/ventoy.json` to configure:
   ```json
   {
     "persistence": [
       { "image": "/ubuntu.iso", "backend": "/persistence/ubuntu-persistence.dat" }
     ]
   }
   ```

3. **Custom persistence with `ventoy.json`**
   - Advanced: map specific ISOs to specific persistence files
   - Supports per-distro persistence configurations

### Resizing Persistence

```bash
bash menu.sh   # → Option 1 → Option 2 → Option 4: Resize persistence
```

Or manually:
```bash
# Unmount first if loop-mounted
sudo umount /mnt/test

# Resize the file (e.g. to 16GB)
dd if=/dev/zero of=/path/to/ubuntu-persistence.dat bs=1M count=16384

# Resize the filesystem
sudo resize2fs /path/to/ubuntu-persistence.dat
```

### Browsing Persistence

```bash
bash menu.sh   # → Option 1 → Option 2 → Option 5: Browse persistence
```

Or manually:
```bash
sudo mount -o loop /mnt/ventoy/persistence/ubuntu-persistence.dat /mnt/test
ls /mnt/test/
# Browse files, modify configs, inject scripts
sudo umount /mnt/test
```

### Persistence File Location

The system expects persistence at:
```
$VENTOY_MOUNT/persistence/ubuntu-persistence.dat
```
Where `$VENTOY_MOUNT` is typically `/mnt/ventoy` (Linux) or `/Volumes/Ventoy` (macOS).

---

## SSH, Port Forwarding, and Firewall

USB-Hemlock includes an SSH host manager + integrates with `ufw`/firewall via the antivirus installer (CL-040).

### SSH Host Manager (Menu Option 4)

Pipe-delimited store at `<install-root>/ssh_hosts.txt` (USB mode → on the USB; HOST mode → in `~/.config/usb-compute-automation/`). The manager generates a clean `~/.ssh/config` block from the store and never overwrites unrelated entries.

```bash
# Add a host non-interactively
UCA_MODE=usb bash usb/scripts/ssh_host_manager.sh --add prod-bastion bastion.example.com ops 2222

# List
bash usb/scripts/ssh_host_manager.sh --list

# Generate ~/.ssh/config block
bash usb/scripts/ssh_host_manager.sh --generate-config

# Remove
bash usb/scripts/ssh_host_manager.sh --remove prod-bastion
```

### Port Forwarding (host-side SSH tunnels)

Use the SSH manager + standard SSH `-L` / `-R`:

```bash
# Local forward — localhost:8080 → bastion:80 via prod-bastion
ssh -L 8080:localhost:80 prod-bastion

# Reverse forward — remote 9000 → your local 3000
ssh -R 9000:localhost:3000 prod-bastion

# Persistent (autossh + systemd user unit)
# Add the systemd unit via Menu option 6 → autossh integration
```

### Firewall (ufw)

The antivirus toolkit installer (`install-antivirus.sh`, Menu option 5 → "Install Antivirus") also configures:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw --force enable
```

Open specific ports after install:

```bash
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 80,443/tcp   # HTTP/HTTPS
sudo ufw allow 1437/tcp    # Hemlock gateway (only if you expose it)
sudo ufw status verbose
```

`ufw` rules live in `/etc/ufw/` on the host. In USB mode the install-antivirus.sh script still touches the host for the package + ufw rules — that's the explicit "initial bridge" allowance documented in CL-030.

---

## Auto-Boot (Headless / VM Launch)

Three ways to launch USB-Hemlock without a desktop sign-in:

### 1. Native USB boot

Plug the Ventoy USB into a machine, boot from USB (BIOS / UEFI boot menu, F12/F10/F2 depending on vendor). Ventoy menu → pick ISO. The persistence overlay (`casper-rw` or whichever `.dat` is mapped via `ventoy.json`) auto-mounts and the system comes up with your saved state. `rc.local` runs the boot orchestrator `<usb>/scripts/startup.sh` (identity log → tooling mount if present → shell/cleanup config → SSH honor → operator hooks) if you installed the hook via the Startup Manager (option 8 → 4).

### 2. Headless via VM (QEMU/KVM)

The USB Access submenu (Menu option 17) has three QEMU flavors:

| Option | Use case |
|---|---|
| **17 → 5** Headless boot + SSH | Serial console + SSH on host port `$UCA_QEMU_SSH_PORT` (default 2222). Best for scripted/CI/remote-access use. |
| **17 → 6** Desktop / GUI boot | Graphical QEMU window. Best for interactive use without rebooting the host. |
| **17 → 7** Boot ISO in QEMU | Boot a specific ISO (without persistence) for live testing. |
| **17 → 8** SSH into running headless VM | Connects to the headless VM started by option 5. |

The QEMU command shape (generated by option 17 → 5):

```bash
sudo qemu-system-x86_64 \
  -enable-kvm -m 8192 -smp 4 -cpu host \
  -drive file=/dev/sdX,format=raw,if=virtio,cache=none \
  -boot order=c -nographic -serial mon:stdio \
  -net user,hostfwd=tcp::2222-:22 -net nic,model=virtio
```

`-net user,hostfwd=tcp::2222-:22` is the port-forward that lets you `ssh -p 2222 user@localhost` into the running USB image without exposing it to your LAN.

### 3. Headless-boot autostart (host service)

**Menu option 17 → 11 (Headless-boot autostart)** is OS-aware: on systemd hosts it generates `/etc/systemd/system/usb-hemlock-autoboot.service`; on macOS it generates a LaunchDaemon plist. The service wraps option 5's QEMU command in a supervised loop.

```bash
# Inspect / control after generation
sudo systemctl status usb-hemlock-autoboot.service
journalctl -u usb-hemlock-autoboot.service -f
sudo systemctl stop usb-hemlock-autoboot.service
```

This is the closest thing to "compute-only host bridge" — the host boots, immediately launches the USB image headlessly, and from then on every interactive session lives on the USB via SSH on port 2222 (or whatever you set).

---

## Startup Management

### Startup Manager (Menu Option 8)

Manages what runs at boot across USB persistence and host system.

```bash
bash menu.sh   # → Option 8: Startup Manager
```

**Sub-options:**
1. **List startup scripts** — Shows rc.local from USB persistence, the USB boot orchestrator, host rc.local, host profile.d, and host systemd services
2. **Seed/refresh boot orchestrator** — Installs `<usb>/scripts/startup.sh` from the canonical orchestrator (only ISOs live at the USB root; operator hooks go in `usb-hemlock/etc/uca/custom-startup.sh`)
3. **View USB persistence rc.local** — Read-only inspection of the installed hook
4. **Install boot hook into persistence rc.local** — Path-agnostic hook that finds the Ventoy partition and runs `scripts/startup.sh`
5. **View host rc.local** — Shows `/etc/rc.local` on the host
6. **View host profile.d scripts** — Lists `/etc/profile.d/*.sh` login scripts
7. **View host systemd services** — Shows enabled systemd services

### Startup Chain

The system has a layered boot sequence:

```
USB Boot → Ventoy → casper-rw persistence → rc.local → scripts/startup.sh (orchestrator)
             identity log → tooling.dat mount+update (OPTIONAL — only if present, CL-041)
             → first-boot essentials → per-volume shell/cleanup config
             → SSH honor (menu-configured) → operator hooks
```

### Custom Startup

```bash
# 1. Seed the boot orchestrator onto the USB (scripts/startup.sh)
bash menu.sh   # → Option 8 → Option 2

# 2. Install the boot hook into persistence rc.local
bash menu.sh   # → Option 8 → Option 4

# 3. Verify the hook is in rc.local
bash menu.sh   # → Option 8 → Option 3

# Operator customizations: edit usb-hemlock/etc/uca/custom-startup.sh on the
# stick — the orchestrator runs it as its final step every boot.
```

---

## Persistence Management

### Persistence Manager (Menu Option 9)

Manages persistence partitions on the USB drive.

```bash
bash menu.sh   # → Option 9: Persistence Manager
```

**Sub-options:**
1. **View persistence status** — Device layout, persistence file size, label, type
2. **Create persistence** — `dd` + `mkfs.ext4 -F -L casper-rw` (configurable size)
3. **Resize persistence** — Destructive resize with `dd` + `resize2fs`
4. **Browse persistence** — Loop-mount read-only to inspect contents
5. **Check persistence health** — `fsck.ext4 -f` on the persistence file
6. **View Ventoy partition layout** — `lsblk` with full partition details

### Yank-aware mount lifecycle

All persistence loop mounts go through safe helpers (`_uca_safe_loop_mount` /
`_uca_safe_umount`):

- **Self-unmounting** — a mount registry plus an EXIT/TERM trap guarantees the menu unmounts
  everything it mounted, even if it dies mid-operation; every unmount syncs first and falls back
  to lazy detach rather than wedging.
- **Surprise-removal recovery** — before any read-write mount of an ext4 `.dat`, `e2fsck -p`
  replays a dirty journal (no-op when clean), so a stick yanked mid-write self-heals on its next
  use. At startup the menu detects mounts whose backing device vanished, lazy-detaches them, and
  points you at the health check.
- **exFAT flush** — the menu ends with an unconditional `sync`, so profile/config writes to the
  (non-journaled) Ventoy partition are on the metal before you pull the stick.

Residual truth: yanking during an active rw copy still loses that in-flight file — the volume
stays consistent and the interrupted file is re-copied, never silently trusted.

---

## Bash Profile Management

### Bash Profile Manager (Menu Option 10)

Installs and manages the enhanced bash profile.

```bash
bash menu.sh   # → Option 10: Bash Profile Manager
```

**Sub-options:**
1. **Install enhanced bash profile** — Copies `bash_enhanced.sh` to `~/.bash_profile_enhanced`, adds source line to `~/.bashrc`
2. **View current ~/.bashrc** — Shows first 50 lines with line count
3. **View enhanced profile** — Preview `bash_enhanced.sh` contents
4. **Source aliases** — Load `~/.bash_aliases_usb` into current shell
5. **Show all alias sources** — Counts aliases from `.bashrc`, `.bash_aliases_usb`, and checks profile status

### Enhanced Profile Features

The `bash_enhanced.sh` profile provides:
- Custom PS1 prompt with git branch, exit codes
- `showstartup` — List all startup services
- `svcstatus/svcenable/svcdisable/svcrestart` — systemctl wrappers
- `_detect_persistent_storage()` — Auto-detect USB persistence
- Aliases: `reload`, `update`, `ami` (import aliases)
- PATH management for `~/.local/bin`, `~/.bun/bin`, `~/.foundry/bin`

---

## Per-Device Configuration

### Device Config (Menu Option 12)

Manages device-specific profiles so different USB drives can have different configs.

```bash
bash menu.sh   # → Option 12: Device Config
```

**Sub-options:**
1. **Show current device config** — Full JSON config with host-id
2. **List all saved device profiles** — Profiles stored in `~/.config/usb-compute-automation/profiles/`
3. **Save current device profile** — Stamps device path into config, saves as `<device>.json`
4. **Load/switch device profile** — Select from saved profiles, updates active config
5. **Delete device profile** — Remove a saved profile
6. **Generate host-id** — Creates `usb-compute-<md5[:8]>` identity from hostname + MAC

### Config Isolation

Each USB drive gets its own profile keyed by device path:
```
~/.config/usb-compute-automation/
├── config.json              # Active config (per-user)
├── profiles/
│   ├── dev_sdb.json         # Profile for /dev/sdb
│   ├── dev_sdc.json         # Profile for /dev/sdc
│   └── dev_sdd.json         # Profile for /dev/sdd
```

The host-id embeds machine identity: `usb-compute-<md5(hostname + MAC)[:8]>`.

---

## Component Reference

### Alias Manager (`usb/scripts/alias_manager.sh`)

Manages `~/.bash_aliases_usb` with full CRUD and backup support.

```bash
# Interactive menu
bash usb/scripts/alias_manager.sh

# CLI
bash usb/scripts/alias_manager.sh --list [table|csv|json]
bash usb/scripts/alias_manager.sh --add NAME 'COMMAND' [description]
bash usb/scripts/alias_manager.sh --remove NAME
bash usb/scripts/alias_manager.sh --search QUERY
bash usb/scripts/alias_manager.sh --import [~/.bashrc]
bash usb/scripts/alias_manager.sh --export [table|csv|json]
bash usb/scripts/alias_manager.sh --dry-run --add ...   # Preview
```

**Data format:**
```bash
alias ll='ls -alF' # List files in long format
alias gs='git status' # Git status shortcut
```

**Backups:** Stored in `~/.alias_backups/` — created before every mutation.

### SSH Host Manager (`usb/scripts/ssh_host_manager.sh`)

Manages `~/.ssh/hosts_usb` (pipe-delimited: `alias|hostname|user|port|key_path|description`).

```bash
# Interactive menu
bash usb/scripts/ssh_host_manager.sh

# CLI (positional --add)
bash usb/scripts/ssh_host_manager.sh --add ALIAS HOSTNAME [USER] [PORT]
bash usb/scripts/ssh_host_manager.sh --list
bash usb/scripts/ssh_host_manager.sh --test ALIAS
bash usb/scripts/ssh_host_manager.sh --generate    # Writes ~/.ssh/config
bash usb/scripts/ssh_host_manager.sh --search QUERY
bash usb/scripts/ssh_host_manager.sh --remove ALIAS
```

**Backups:** Stored in `~/.ssh/hosts_backups/` — created before every mutation.

### System Manager (`usb/sysman.sh`)

Health/network/disk/services dashboard. Supports both whiptail and text fallback.

```bash
bash usb/sysman.sh                # Interactive menu
bash usb/sysman.sh --health       # Health snapshot (CPU, memory, disk, processes)
bash usb/sysman.sh --info         # System information
bash usb/sysman.sh --network      # Network diagnostics
bash usb/sysman.sh --disk         # Disk usage & SMART
bash usb/sysman.sh --services     # systemd/service status
bash usb/sysman.sh --process      # Process information
bash usb/sysman.sh --logs         # System logs
bash usb/sysman.sh --repair       # Automatic repairs
bash usb/sysman.sh --cleanup      # System cleanup (delegates to clean-local.sh)
bash usb/sysman.sh --startup      # Startup service management
bash usb/sysman.sh --text         # Force text mode (no whiptail)
bash usb/sysman.sh --dry-run      # Preview mode
```

### Unified CLI (`usb/cli/usbctl`)

Single dispatcher for all USB/config/alias operations.

```bash
bash usb/cli/usbctl usb detect          # List USB devices
bash usb/cli/usbctl usb mount           # Mount Ventoy (needs SELECTED_DEVICE)
bash usb/cli/usbctl usb unmount         # Unmount Ventoy
bash usb/cli/usbctl usb persistence     # Show persistence status
bash usb/cli/usbctl config host-id      # Generate host ID
bash usb/cli/usbctl config show         # Show config JSON
bash usb/cli/usbctl config init         # Initialize config
bash usb/cli/usbctl alias --list        # List aliases
bash usb/cli/usbctl validate host       # Validate host-id only
bash usb/cli/usbctl validate all        # Run all validations
```

### Hemlock Runtime TUI

Launches the Hemlock agent runtime inside a Docker container.

```bash
# Via master menu (reveal with --hemlock)
bash menu.sh --hemlock   # → Option 19: Hemlock Manager → Option 1: Launch in-container TUI

# Direct
export HEMLOCK_DIR=$(pwd)/hemlock/hemlock-runtime
bash usb/hemlock-tui

# Or via hemlock CLI
bash hemlock/hemlock-runtime/scripts/hemlock menu
```

**TUI Features:**
- Agent Management: Create, Import, Export, Delete, Start, Stop, Monitor, List
- Crew Management (A2A): Create, Import, Export, Join, Leave, List All, Start, Monitor, Dissolve
- Runtime Validation: Full validation, Hermes Doctor, Docker env check, Validate Configs
- Security Hardening: Apply, Check Status, Reset
- System Monitoring: Runtime Logs, Agent Logs, System Health
- Configuration: Edit Runtime Config, Edit Agent Config, View Current Config

### Master Deploy (`hemlock/DEPLOY.sh`)

Full stack deployment in 3 phases: System → USB → Hemlock. Requires root.

```bash
sudo bash hemlock/DEPLOY.sh              # Full deploy
sudo bash hemlock/DEPLOY.sh --dry-run    # Preview only
sudo bash hemlock/DEPLOY.sh --no-system  # Skip system bootstrap
sudo bash hemlock/DEPLOY.sh --no-usb     # Skip USB setup
sudo bash hemlock/DEPLOY.sh --no-hemlock # Skip Hemlock deploy
sudo bash hemlock/DEPLOY.sh --help       # Show all options
```

### USB Auto-Mount (`usb/usb-automount/`)

Systemd + udev auto-mount for USB devices. Requires root.

```bash
sudo bash usb/usb-automount/setup-usb-automount.sh      # Install
sudo bash usb/usb-automount/teardown-usb-automount.sh   # Remove
```

Installs:
- `/usr/local/bin/usb-mount.sh` — mount helper
- `/etc/udev/rules.d/99-usb-automount.rules` — udev trigger
- `usb-automount.service` — systemd unit (mounts to `/mnt/usb/<dev>`)

### Build Essentials (`usb/scripts/setup-essentials-enhanced.sh`)

Dev toolchain installer. Writes to `/opt`, `/var/log`. Requires root.

```bash
sudo bash usb/scripts/setup-essentials-enhanced.sh           # Full install
sudo bash usb/scripts/setup-essentials-enhanced.sh --dry-run # Preview only
sudo bash usb/scripts/setup-essentials-enhanced.sh --verbose # Verbose output
sudo bash usb/scripts/setup-essentials-enhanced.sh --cleanup # Cleanup temp files
```

Installs: llama.cpp, ollama, rust, foundry, hardhat, playwright, tauri, bun, tailscale, node, python.

---

## CLI Reference

### Non-Interactive Flags

For scripted/automated use, the master menu and individual scripts support CLI flags:

```bash
# Mode (CL-030) — picks USB vs HOST install routing
bash menu.sh --usb            # force USB mode (skip boot prompt)
bash menu.sh --host           # force HOST mode (skip boot prompt)
bash menu.sh --mode usb       # long form
bash menu.sh --mode host      # long form

# Other top-level flags
bash menu.sh --text           # Force text menu (no whiptail)
bash menu.sh --dry-run        # Preview every mutation; no writes
bash menu.sh --hemlock        # Reveal Hemlock Manager (opt-in, USB mode only)
bash menu.sh -H               # Shorthand for --hemlock
bash menu.sh --log-file PATH  # Custom log path
bash menu.sh --help           # Full usage

# Combined: dry-run preview of HOST-mode install
bash menu.sh --host --text --dry-run

# Individual scripts (UCA_MODE env-var is honored)
UCA_MODE=usb bash usb/scripts/alias_manager.sh --add deploy 'kubectl apply -f' 'k8s deploy'
UCA_MODE=host bash usb/scripts/ssh_host_manager.sh --add myhost example.com user 22
bash usb/sysman.sh --health --text
bash usb/cli/usbctl validate all

# clean-local.sh — blocked in USB mode unless overridden
UCA_MODE=usb bash usb/scripts/clean-local.sh                   # → [BLOCKED] exit 12
UCA_MODE=usb bash usb/scripts/clean-local.sh --force-host      # explicit override
bash usb/scripts/clean-local.sh                                 # OK (UCA_MODE defaults to host)
```

### Setting Environment Variables

```bash
# USB device selection
export SELECTED_DEVICE="/dev/sdb"

# Hemlock directory
export HEMLOCK_DIR="/path/to/hemlock/hemlock-runtime"

# Dry-run mode
export DRY_RUN=true

# Logging
export LOG_LEVEL=DEBUG
export LOG_FILE="/var/log/usb-hemlock.log"
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| **`UCA_MODE`** | unset (silent USB detect) | `usb` or `host`. Sets the top-level install target. Skips the boot prompt. CL-030. |
| **`UCA_PERSISTENCE_PATH`** | auto-resolved | Pre-resolved path to the primary `.dat` file. Used by child scripts so they don't have to re-run detection. Auto-exported by `menu.sh` when USB mode is chosen. |
| **`UCA_RESERVED_BYTES`** | `268435456` (256 MiB) | Floor of free space kept untouched on the USB for configs/scripts/profiles. Enforced by every persistence create/resize. CL-033. |
| `HEMLOCK_ENABLED` | `false` | Same as `--hemlock` / `-H`. Reveals Hemlock Manager (option 19). USB mode only. **Blacklisted** from profile auto-export per SPEC-T04 — must be opted into per run. |
| `DRY_RUN` | `false` | Preview mutations without executing |
| `LOG_FILE` | `/tmp/usb-hemlock-<pid>.log` | Log file path |
| `LOG_LEVEL` | `INFO` | Minimum: DEBUG, INFO, WARN, ERROR, CRITICAL |
| `LOG_MAX_SIZE` | `10485760` | Log rotation threshold (10 MB) |
| `LOG_ROTATE_COUNT` | `5` | Number of rotated logs to keep |
| `LOG_DISABLE_FILE` | `false` | Disable file logging |
| `LOG_DISABLE_COLOR` | `false` | Disable color output |
| `HEMLOCK_DIR` | auto-detected | Path to `hemlock-runtime/` |
| `SELECTED_DEVICE` | unset | USB device (e.g. `/dev/sdb`). Skip auto-detect when set. |
| `VENTOY_MOUNT` | auto-resolved | Mount point of the Ventoy partition. Recomputed each launch. |
| `USB_ROOT` | script directory | USB component root |
| `UCA_CONFIG_DIR` | `~/.config/usb-compute-automation` | **HOST-mode** install root + persistent paths config dir |
| `UCA_CONFIG_FILE` | `$UCA_CONFIG_DIR/config.json` | Config file path |
| `UCA_ENVIRONMENT` | auto-detected | `usb-boot` / `usb-mounted` / `native`. Override to skip detection prompt. |

Full reference with copy-paste examples: see `usb/env.example`.

---

## Logging

All components write structured logs with timestamps, levels, and context.

### Log Levels

| Level | Description |
|-------|-------------|
| `DEBUG` | Verbose debug information |
| `INFO` | Normal operations |
| `WARN` | Potential issues |
| `ERROR` | Failures requiring attention |
| `CRITICAL` | System-threatening failures |

### Configuration

```bash
export LOG_LEVEL=DEBUG    # Most verbose
export LOG_LEVEL=INFO     # Default
export LOG_LEVEL=ERROR    # Only errors

export LOG_FILE=/var/log/usb-hemlock.log   # Custom log path
export LOG_DISABLE_FILE=true               # Disable file logging
export LOG_DISABLE_COLOR=true              # Disable color output
```

### Log Rotation

Logs auto-rotate at 10 MB (`LOG_MAX_SIZE`). Only the last 5 rotated logs are kept.

### Viewing Logs

```bash
# Via master menu
bash menu.sh   # → Option 15: View Logs

# Direct
tail -f /tmp/usb-hemlock-*.log
grep "ERROR" /tmp/usb-hemlock-*.log
grep "WARN" /tmp/usb-hemlock-*.log | tail -20
```

---

## Testing Suite

Run the full test suite to validate all components:

```bash
# Full test suite
bash usb/tests/run-all.sh

# Specific test categories
bash usb/tests/run-all.sh --syntax      # Syntax checks only
bash usb/tests/run-all.sh --runtime     # Runtime behavior only
bash usb/tests/run-all.sh --integration # Integration tests only
bash usb/tests/run-all.sh --dry-run     # Dry-run tests only
```

### Test Categories

| Test | Description | Assertions |
|------|-------------|------------|
| `tests/00-env.sh` | Environment prerequisites (Bash, jq, Docker, Python) | 8 |
| `tests/01-syntax.sh` | Bash syntax validation for all .sh files | 97 |
| `tests/02-permissions.sh` | File permissions (readable, executable) | 180+ |
| `tests/03-lib-modules.sh` | Library loading and API exports | 35 |
| `tests/04-config.sh` | Config init, get, set, host-id generation | 12 |
| `tests/05-alias-manager.sh` | Alias CRUD cycle | 9 |
| `tests/06-ssh-manager.sh` | SSH host CRUD cycle | 7 |
| `tests/07-sysman.sh` | System manager subcommands | 10 |
| `tests/08-usbctl.sh` | CLI dispatcher | 9 |
| `tests/09-validation.sh` | Validation engine + self-heal | 8 |
| `tests/10-hemlock.sh` | Hemlock runtime detection | 14 |
| `tests/11-menu.sh` | Master menu rendering | 18 |
| `tests/12-logging.sh` | Logging framework | 14 |
| `tests/13-deploy.sh` | Deploy dry-run | 12 |

### Expected Results

- **201 passed, 0 failed, 1 skipped** (SSH interactive prompts — inherent behavior)
- All 12 usb/ scripts + menu.sh pass `bash -n` syntax check
- All file paths verified as existing
- All library functions export correctly
- Config system creates/reads/writes JSON correctly

### Test Helpers

Tests source `usb/tests/test-helpers.sh` which provides:
- `assert_exit_success` — Verify command exits 0
- `assert_exit_failure` — Verify command exits non-0
- `assert_file_exists` — Verify file exists
- `assert_output_contains` — Verify output contains string
- `assert_equal` — Verify two values are equal

---

## Feature Flags

All 29 flags are initialized to `disabled` in `feature-flags.json`. Enable them as components are validated:

| Flag | Module | Description |
|------|--------|-------------|
| `FEAT_CORE_LIB` | MOD-001 | Core library |
| `FEAT_PLATFORM` | MOD-002 | Platform detection |
| `FEAT_VENTOY` | MOD-003 | Ventoy USB management |
| `FEAT_CONFIG` | MOD-004 | JSON configuration |
| `FEAT_MENU` | MOD-005 | Menu framework |
| `FEAT_VALIDATION` | MOD-006 | Validation engine |
| `FEAT_CLI` | MOD-007 | Unified CLI |
| `FEAT_SETUP_ASSISTANT` | MOD-008 | USB setup assistant |
| `FEAT_ALIAS` | MOD-009 | Alias manager |
| `FEAT_SSH` | MOD-010 | SSH host manager |
| `FEAT_SYSMAN` | MOD-011 | System manager |
| `FEAT_ESSENTIALS` | MOD-012 | Essentials installer |
| `FEAT_AUTOMOUNT` | MOD-013 | USB auto-mount |
| `FEAT_BOOTSTRAP` | MOD-014 | System bootstrap |
| `FEAT_HEMLOCK_CLI` | MOD-015 | Hemlock host CLI |
| `FEAT_HEMLOCK_TUI` | MOD-016 | Hemlock runtime TUI |
| `FEAT_HEMLOCK_STAGING` | MOD-017 | Hemlock staging bridge |
| `FEAT_HEMLOCK_DOCKER` | MOD-018 | Hemlock Docker infra |
| `FEAT_DEPLOY` | MOD-019 | Master deployment |
| `FEAT_BRIDGE` | MOD-020 | USB-Hemlock bridge |
| `FEAT_SKILLS` | MOD-021 | Skills bundle |

---

## Troubleshooting

### Common Issues

#### "SELECTED_DEVICE not set"
```bash
# Find your USB device
lsblk

# Set the device (replace sdb with your actual device)
export SELECTED_DEVICE="/dev/sdb"

# Verify
echo $SELECTED_DEVICE
```

#### "HEMLOCK_DIR not found"
```bash
# Auto-detection should work if repo structure is intact
# If not, set manually:
export HEMLOCK_DIR=$(pwd)/hemlock/hemlock-runtime

# Verify
test -d "$HEMLOCK_DIR/scripts" && echo "OK" || echo "MISSING"
```

#### "jq: command not found"
```bash
# Ubuntu/Debian
sudo apt install jq

# macOS
brew install jq

# Verify
jq --version
```

#### "Docker daemon not running"
```bash
# Linux
sudo systemctl start docker
sudo systemctl enable docker

# macOS
open -a Docker

# Verify
docker info
```

#### "Menu falls through to interactive mode after CLI args"
This was a known bug in the original codebase. Fixed in `usb-hemlock-split/` — the `cli_args_provided`/`CLI_ARG_PROCESSED` pattern tracks whether CLI arguments were processed and prevents fallthrough.

#### "sudo blocks on password"
```bash
# Cache credentials first
sudo -v

# Or use --dry-run mode (no sudo needed)
bash menu.sh --dry-run
```

#### "Permission denied on scripts"
```bash
# Fix permissions
chmod +x usb/cli/usbctl
chmod +x usb/scripts/*.sh
chmod +x usb/sysman.sh
chmod +x usb/usb-setup-assistant.sh
chmod +x usb/hemlock-tui
chmod +x hemlock/hemlock-tui
chmod +x hemlock/DEPLOY.sh
chmod +x menu.sh
```

#### "lib/core.sh not found" when running alias_manager.sh
The alias_manager.sh sources `$SCRIPT_DIR/../lib/*.sh`. If you moved the file, ensure the relative path to `lib/` is correct. The lib/ directory must be one level up from scripts/.

#### "Ventoy tarball not found"
```bash
# Check if bundled Ventoy exists
test -f usb/volumes/ventoy/ventoy-1.0.99-linux.tar.gz && echo "OK" || echo "MISSING"

# If missing, download manually
cd usb/volumes/ventoy
wget https://github.com/ventoy/Ventoy/releases/download/v1.0.99/ventoy-1.0.99-linux.tar.gz
```

#### "Persistence file not found"
```bash
# Check if persistence exists
ls -la /mnt/ventoy/persistence/

# If missing, create it (see "Creating Persistence" section above)
```

#### "Hemlock container won't start"
```bash
# Check Docker status
docker ps -a | grep hemlock

# Check logs
docker logs hemlock_runtime

# Rebuild and restart
cd hemlock/hemlock-runtime
docker compose -f docker-compose.runtime.yml down
docker compose -f docker-compose.runtime.yml build
docker compose -f docker-compose.runtime.yml up -d
```

#### "Tests fail with 'lib/ not found'"
Tests must be run from the repo root directory:
```bash
cd usb-hemlock-split
bash usb/tests/run-all.sh
```

### Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=DEBUG
bash menu.sh --text 2>&1 | tee /tmp/debug.log

# Check the log for detailed output
grep "DEBUG" /tmp/debug.log
```

### Log File Locations

| Component | Log Location |
|-----------|-------------|
| Master menu | `/tmp/usb-hemlock-menu-*.log` |
| USB setup assistant | `/tmp/usb-setup-assistant-*.log` |
| All components | `$LOG_FILE` (if set) |

---

## Known Limitations

1. **Hardware-dependent features** — USB detection, Ventoy installation, persistence creation, and boot testing require a physical USB drive
2. **Root required** — DEPLOY.sh, auto-mount setup, build essentials, and system bootstrap require root/sudo
3. **Docker required** — Hemlock agent runtime requires Docker and Docker Compose v2
4. **jq required** — Config system and validation engine require jq
5. **Bash 4+ required** — Some features use Bash 4+ syntax (associative arrays, etc.)
6. **USB device letters change** — Device names (sdb, sdc) vary by machine. Always use `lsblk` to identify
7. **Single-user design** — Config is per-user (`~/.config/usb-compute-automation/`), not system-wide
8. **Persistence size fixed at creation** — Resizing requires destructive recreation (data loss)
9. **51K hemlock files** — The hemlock/ directory is large due to vendored node_modules in skills. Use `.gitignore` carefully

---

## Development & Contributing

### Syntax Check (MUST run after every .sh edit)

```bash
bash -n menu.sh usb/lib/*.sh usb/cli/usbctl usb/scripts/*.sh usb/sysman.sh usb/usb-setup-assistant.sh
```

### Preview Mutations

```bash
DRY_RUN=true bash menu.sh --text
bash usb/scripts/alias_manager.sh --dry-run --add test 'echo test'
bash usb/cli/usbctl config host-id   # Honors DRY_RUN
```

### Run Tests

```bash
bash usb/tests/run-all.sh           # Full suite (201 assertions)
bash usb/tests/run-all.sh --syntax  # Syntax only
```

### Validate Blueprint

```bash
python3 hemlock/hemlock-runtime/skills/enterprise-blueprint/scripts/validate_blueprint.py blueprint/blueprint.md --verbose
python3 hemlock/hemlock-runtime/skills/enterprise-blueprint/scripts/generate_checklist.py blueprint/blueprint.md --sync
```

### Code Style

- Shebang: `#!/usr/bin/env bash`
- Safety: `set -euo pipefail` on every entrypoint script
- Guard: `[[ -n "${UCA_<MODULE>_SH_SOURCED:-}" ]] && return 0` on every lib module
- Colors: Use `: "${RED:=\033[0;31m]}"` pattern (overridable defaults), never hard-assign
- Help: Every script supports `-h`/`--help`
- Logging: Structured with timestamp via `uca_log` or local equivalent
- Exit codes: 0 = success, 1 = error, 130 = interrupted (INT), 143 = terminated (TERM)
- Style: Match the file you edit. lib/ scripts use lib/ conventions. Monoliths use their own declarations.

---

## Originals Unchanged

All work is performed on copies in `usb-hemlock-split/`. The original files remain untouched:

- `usb-compute-automation/` — canonical USB code (original)
- `hemlock-complete-deployment/` — deployment bundle (original)
- `hemlock-runtime/` — Docker runtime (original)

MD5 verification confirms originals are byte-identical.

---

## License

[License information here]
