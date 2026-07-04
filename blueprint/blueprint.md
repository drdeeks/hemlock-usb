# USB-Hemlock Unified Compute Platform — ENTERPRISE BLUEPRINT
## Version 1.0 | Document Class: MASTER SPECIFICATION
### Generated: 2026-06-25

> **READ FIRST — DOCUMENT AUTHORITY**
> This document is the single source of truth. No feature may be built,
> no schema migrated, and no API changed without this document as the
> authoritative reference. All contributors MUST read Part V (Change
> Control Protocol) before touching any file. This document's change
> log is APPEND-ONLY. Prior sections may only be updated via a formal
> amendment with a corresponding CL entry.

---

## TABLE OF CONTENTS

```
PART I    — SYSTEM OVERVIEW & ARCHITECTURE
PART II   — MODULE REGISTRY
PART III  — SCREEN & FEATURE SPECIFICATIONS
PART IV   — DATA ARCHITECTURE
PART V    — CHANGE CONTROL PROTOCOL
PART VI   — MASTER IMPLEMENTATION CHECKLIST
PART VII  — QUALITY & COMPLIANCE STANDARDS
```

---

---

# PART I — SYSTEM OVERVIEW & ARCHITECTURE

> **Rollback Tag:** `[SYS-OVERVIEW-v1]`

## 1.1 Vision Statement

A portable, enterprise-grade compute environment that boots from any USB
drive via Ventoy, provides persistent Linux workspaces with full SSH/alias
management and system health monitoring, and seamlessly launches a
Dockerized Hemlock agent runtime for AI agent orchestration — all managed
through interactive menus with safe, informative steps and dry-run
capability at every layer.

The system is composed of exactly two self-contained directories:
`usb/` (USB management) and `hemlock/` (agent runtime). Together they
deliver a complete bootable compute platform from bare metal to running
AI agents, requiring only a USB drive and a Docker-capable host.

## 1.2 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     USER ENTRY LAYER                                 │
│  menu.sh (master entry, 21 options across 5 categories)              │
│  cli/usbctl (unified CLI)                                            │
│  hemlock-tui → hemlock/scripts/hemlock menu                          │
└──────────┬──────────────────────────────┬───────────────────────────┘
           │                              │
┌──────────▼──────────────────┐ ┌────────▼────────────────────────────┐
│   USB SERVICE LAYER          │ │   HEMLOCK RUNTIME LAYER              │
│                              │ │                                      │
│  lib/core.sh     (logging)   │ │  scripts/hemlock    (host CLI)       │
│  lib/platform.sh (OS detect) │ │  scripts/runtime.sh (in-container)   │
│  lib/usb.sh      (Ventoy)    │ │  scripts/hemlock-stage.sh (staging)  │
│  lib/config.sh   (JSON/jq)   │ │  docker-compose.runtime.yml          │
│  lib/menu.sh     (menus)     │ │  docker-compose.yml                  │
│  lib/validation.sh (health)  │ │  Dockerfile.runtime + .agent + .crew │
│                              │ │                                      │
│  scripts/alias_manager.sh    │ │  Python: health.doctor_bridge        │
│  scripts/ssh_host_manager.sh │ │  Node:   openclaw gateway (:18789)   │
│  sysman.sh (system health)   │ │  Bash:   agent/crew lifecycle        │
│  setup-essentials-enhanced.sh│ │                                      │
│  usb-automount/ (udev+sysd)  │ │  volumes/imports/.request (staging)  │
└──────────┬──────────────────┘ └────────┬────────────────────────────┘
           │                              │
┌──────────▼──────────────────────────────▼───────────────────────────┐
│                     DATA / STORAGE LAYER                             │
│                                                                      │
│  USB Drive (exFAT):                                                  │
│    /ventoy/           — Ventoy bootloader config                     │
│    /*.iso             — Bootable ISO images                          │
│    /persistence/ubuntu-persistence.dat  — ext4 casper-rw volume      │
│                                                                      │
│  Host filesystem:                                                    │
│    ~/.config/usb-compute-automation/config.json  — JSON config       │
│    ~/.bash_aliases_usb                           — alias store       │
│    ~/.ssh/hosts_usb                              — SSH host store     │
│    ~/.ssh/hosts_backups/                         — SSH backups        │
│    ~/.alias_backups/                             — alias backups      │
│                                                                      │
│  Docker volumes:                                                     │
│    hemlock_runtime (container: hemlock_runtime)                       │
│    agents/, crews/, models/, skills/, config/                        │
└─────────────────────────────────────────────────────────────────────┘
```

## 1.3 Tech Stack

| Layer | Technology | Rationale |
|---|---|---|
| Shell Framework | Bash 4+ with `set -euo pipefail` | Universal Linux/macOS availability; no compilation needed |
| USB Bootloader | Ventoy 1.0.99 (bundled tarball) | Multi-ISO boot without re-formatting; persistence support |
| Persistence FS | ext4 with `casper-rw` label | Ubuntu casper convention; loop-mountable from host |
| Config Store | JSON via `jq` | Atomic read/write, structured data, CLI-friendly |
| Container Runtime | Docker + Compose v2 | Standard container orchestration; Hemlock requires it |
| Agent Runtime | Python 3 (PYTHONPATH=/opt/hermes) | Hemlock health checks, doctor bridge, agent logic |
| Gateway | Node.js (openclaw) | AI gateway server on port 18789 |
| Orchestration | Bash scripts (runtime.sh, hemlock) | In-container TUI and host-side lifecycle management |
| System UI | whiptail + text fallback | Interactive menus without heavy dependencies |
| Auto-mount | udev rules + systemd unit | Kernel-level USB detection; survives reboot |

## 1.4 Directory Contract

The system uses exactly two directories. All paths are relative to these roots.

| Directory | Root Variable | Purpose |
|---|---|---|
| `usb/` | `$USB_ROOT` | USB management: Ventoy, persistence, SSH, aliases, system health, automount |
| `hemlock/` | `$HEMLOCK_ROOT` | Agent runtime: Docker containers, TUI, import/export, skills, crews |

The `hemlock-tui` wrapper in `usb/` bridges between them. It requires
`HEMLOCK_DIR` set to the absolute path of `hemlock/hemlock-runtime/`.

---

---

# PART II — MODULE REGISTRY

> **Rollback Tag:** `[MODULE-REGISTRY-v1]`
> **Rule:** Every change log entry MUST reference at least one Module ID.

| Module ID | Name | Description | Feature Flag |
|---|---|---|---|
| MOD-001 | Core Library | Colors, logging, confirm, run_or_dry, safe_exec, traps | FEAT_CORE_LIB |
| MOD-002 | Platform Detection | OS detection (Linux/macOS/WSL/Windows), virtualization, tool selection | FEAT_PLATFORM |
| MOD-003 | Ventoy USB Management | Mount detection (5 fallbacks), unmount, persistence check/size | FEAT_VENTOY |
| MOD-004 | JSON Configuration | Config init/get/set via jq, host-ID generation (md5 of hostname+mac) | FEAT_CONFIG |
| MOD-005 | Menu Framework | Stack-based menu_loop with back/quit, UCA_MENU_STACK array | FEAT_MENU |
| MOD-006 | Validation Engine | Triple validation (host-id, USB mount, menu stack), self-heal | FEAT_VALIDATION |
| MOD-007 | Unified CLI | usbctl dispatcher: usb/config/alias/validate subcommands | FEAT_CLI |
| MOD-008 | USB Setup Assistant | 5908-line interactive installer: Ventoy, persistence, VM, essentials | FEAT_SETUP_ASSISTANT |
| MOD-009 | Alias Manager | ~/.bash_aliases_usb CRUD with menu_loop integration | FEAT_ALIAS |
| MOD-010 | SSH Host Manager | ~/.ssh/hosts_usb pipe-delimited store, config generation | FEAT_SSH |
| MOD-011 | System Manager | Health/network/disk/services/repair dashboard (whiptail+text) | FEAT_SYSMAN |
| MOD-012 | Essentials Installer | Build toolchain provisioner: llama.cpp, ollama, rust, foundry, node, python | FEAT_ESSENTIALS |
| MOD-013 | USB Auto-Mount | udev rules + systemd service for automatic USB mounting | FEAT_AUTOMOUNT |
| MOD-014 | System Bootstrap | Ubuntu one-time provisioner: apt, Node, Bun, Python, Docker, Tailscale | FEAT_BOOTSTRAP |
| MOD-015 | Hemlock Host CLI | Host-side entrypoint: container lifecycle, staging watcher, exec | FEAT_HEMLOCK_CLI |
| MOD-016 | Hemlock Runtime TUI | In-container menu: agent/crew/validation/security/monitoring/config | FEAT_HEMLOCK_TUI |
| MOD-017 | Hemlock Staging Bridge | Import/export file staging via volumes/imports/.request protocol | FEAT_HEMLOCK_STAGING |
| MOD-018 | Hemlock Docker Infra | Compose files, Dockerfiles, Makefile for runtime/agent/crew/doctor | FEAT_HEMLOCK_DOCKER |
| MOD-019 | Master Deployment | DEPLOY.sh: 3-phase deploy (system + USB + Hemlock) with --dry-run | FEAT_DEPLOY |
| MOD-020 | USB-Hemlock Bridge | hemlock-tui wrapper: connects USB menu option 8 (Hemlock TUI) to Hemlock CLI | FEAT_BRIDGE |
| MOD-021 | Skills Bundle | 84 agent skill packages for Hemlock runtime | FEAT_SKILLS |

---

---

# PART III — SCREEN & FEATURE SPECIFICATIONS

> **Rollback Tag:** `[SPECS-v1]`
> Each specification follows this format:
> ID, Module Ref, Rollback Tag, Feature Flag, Purpose,
> Components, Rules, Error States, Fallback.

## FS-001 — Master Menu (menu.sh)

**Module Ref:** MOD-008 | **Rollback Tag:** `[FS-001-v1]` | **Feature Flag:** `FEAT_SETUP_ASSISTANT`

**Purpose:** Singular interactive entry point for ALL components. 21 options across 5 categories with target labels indicating where each action runs.

**Components:**
- Text menu render function (`_main_menu_render`) with ANSI colors
- Whiptail menu function (`_main_menu_whiptail`) for GUI mode
- 21 option handler functions (`_run_*` / `_uca_*`) delegating to component scripts (see FS-008, FS-009)
- Dry-run toggle (option 19) toggling `DRY_RUN` env var
- Auto-detection of `HEMLOCK_DIR` via 5-path search
- Auto-detection of `HAS_WHIPTAIL` for menu mode selection

**Menu Options (verbatim from menu.sh `_main_menu_render`):**

```
USB Components:
  1)  USB Setup Assistant        [USB]      Interactive Ventoy installer
  2)  Unified CLI (usbctl)       [USB]      USB/config/alias/validate
  3)  Alias Manager              [HOST]     Manage ~/.bash_aliases_usb
  4)  SSH Host Manager           [HOST]     Manage ~/.ssh/hosts_usb
  5)  System Manager (sysman)    [HOST]     Health/network/disk/services
  6)  USB Auto-Mount             [HOST]     udev + systemd setup
  7)  Build Essentials           [HOST]     Install dev toolchain

Hemlock Components:
  8)  Hemlock TUI                [CONTAINER] Agent runtime menu
  9)  Hemlock Status             [CONTAINER] Check runtime status
  10) Master Deploy (DEPLOY.sh)  [ALL]      Full stack deployment

Configuration:
  11) Startup Manager            [USB+HOST] Boot scripts & autostart
  12) Persistence Manager        [USB]      Persistence partitions
  13) Bash Profile Manager       [HOST]     Shell config & aliases
  14) USB Device Setup           [USB]      Detect/select USB device
  15) Device Config              [HOST]     Per-device profiles

System:
  16) Run Validation             [ALL]      Validate all components
  17) Diagnostics                [HOST]     System info & config
  18) View Logs                  [HOST]     Log viewer & search

Access & Configuration:
  19) USB Paths & Environment    [HOST]      Configure paths, schema & env
  20) USB Access & Boot          [USB+HOST]  Terminal/chroot/QEMU/SSH
  21) Toggle Dry-Run             (toggle)
```

**Rules:**
1. Sources `usb/lib/` modules (core.sh, logging.sh, menu.sh, config.sh, validation.sh).
2. Auto-detects `HEMLOCK_DIR` via 5-path search (menu.sh:42-53).
3. Text mode drives `_main_menu_handler` via its own inline loop (NOT `lib/menu.sh`'s `menu_loop`) — `menu_loop` captures handler stdout via command substitution to read a stay/back/exit verdict, which would swallow every component's printed output. Whiptail mode renders via `_main_menu_whiptail` for GUI mode. Sub-managers invoked from the menu (e.g. `alias_manager.sh`) may still use `menu_loop` internally for their own submenus.
4. `--dry-run` flag propagates to all component runners via `DRY_RUN` env var; passed conditionally (`[[ "$DRY_RUN" == "true" ]]`), never unconditionally.
5. `--text` forces text menu (no whiptail dependency).
6. Privileged operations (DEPLOY.sh, essentials, auto-mount) use `sudo` with user confirmation.
7. EXIT/TERM traps via `set_standard_traps` from lib/core.sh. Every handler invocation is additionally guarded with `|| true` so a non-zero return from any component cannot trip `set -e` or abort the menu.
8. Text mode: `q`/`Q`/`quit`/`exit` exits the program; empty input re-prompts; EOF on `read` breaks the loop cleanly. Whiptail mode: Cancel button is relabeled "Quit" — Cancel/ESC exits the program (previously this looped forever with no way out).

**Error States:**
- No USB device detected → component prints error, returns to menu
- HEMLOCK_DIR not set → Hemlock options print error with setup instructions
- Ventoy tarball missing → `volumes/ventoy/ventoy-1.0.99-linux.tar.gz` not found error
- Persistence file exists → warns, offers skip or overwrite

**Fallback:** If whiptail is unavailable, falls back to the text-mode loop described in Rule 3.

## FS-002 — Ventoy Persistence Creation

**Module Ref:** MOD-003, MOD-008 | **Rollback Tag:** `[FS-002-v1]` | **Feature Flag:** `FEAT_VENTOY`

**Purpose:** Create a persistent ext4 filesystem on the Ventoy USB drive.

**Components:**
- Size prompt (default: 8 GB)
- `dd` command to create zero-filled .dat file
- `mkfs.ext4 -F -L casper-rw` formatting
- Loop-mount and rc.local injection

**Flow:**
1. Verify SELECTED_DEVICE is set and Ventoy is mounted (detect_ventoy_mount 5-method fallback).
2. Prompt for size in GB (default: 8 GB).
3. `dd if=/dev/zero of=$VENTOY_MOUNT/persistence/ubuntu-persistence.dat bs=1M count=$((GB*1024)) status=progress`
4. `mkfs.ext4 -F -L casper-rw` (Ubuntu casper convention).
5. Loop-mount the .dat file.
6. Inject `etc/rc.local` autostart script into persistence volume.
7. Unmount loop device.

**Rules:**
1. Requires `SELECTED_DEVICE` to be exported.
2. Requires Ventoy to be mounted (detect_ventoy_mount must succeed).
3. Destructive operation — warns before overwriting existing persistence.
4. Honors `DRY_RUN` flag.

**Error States:**
- No USB device selected → error message, returns to menu
- Ventoy not mounted → error message, suggests mounting first
- Persistence already exists → warns, offers skip or overwrite
- `dd` or `mkfs.ext4` fails → error message with diagnostic info

**Fallback:** N/A — creation is atomic; failure leaves USB in prior state.

## FS-003 — Alias Manager Interactive + CLI

**Module Ref:** MOD-009 | **Rollback Tag:** `[FS-003-v1]` | **Feature Flag:** `FEAT_ALIAS`

**Purpose:** CRUD management of `~/.bash_aliases_usb` with backup support.

**Components:**
- CLI flags: `--list`, `--add`, `--remove`, `--search`, `--import`, `--export`, `--dry-run`
- Interactive menu via `menu_loop` when no args provided
- Backup creation before every mutation
- Import from existing `~/.bashrc`
- Export in table, CSV, JSON formats

**Data Format:** `alias name='cmd' # description` (one per line)
**Backup Location:** `~/.alias_backups/`

**Rules:**
1. Sources lib/core.sh, lib/menu.sh, lib/config.sh.
2. Creates timestamped backup before every mutation.
3. Interactive mode uses `menu_loop` with back/quit navigation.
4. Honors `DRY_RUN` flag for all mutations.

**Error States:**
- lib/ not found → error message with path guidance
- Alias already exists → warns, offers overwrite
- Import file not found → error message

**Fallback:** If lib/ unavailable, script fails gracefully with error message.

## FS-004 — SSH Host Manager

**Module Ref:** MOD-010 | **Rollback Tag:** `[FS-004-v1]` | **Feature Flag:** `FEAT_SSH`

**Purpose:** Manage SSH host inventory in `~/.ssh/hosts_usb` with backup and config generation.

**Components:**
- CLI flags: `--add`, `--remove`, `--list`, `--test`, `--connect`, `--push`, `--pull`, `--sync`, `--generate`, `--search`, `--import`, `--dry-run`
- Pipe-delimited data store
- Config generation to `~/.ssh/config`
- Backup before mutations

**Data Format:** Pipe-delimited `alias|hostname|user|port|key_path|description`
**Backup Location:** `~/.ssh/hosts_backups/`

**Rules:**
1. Self-contained — does NOT source lib/. Redeclares own print_*/run_or_dry.
2. `--add` uses positional args: `--add ALIAS HOSTNAME [USER] [PORT]`.
3. `--generate` writes `~/.ssh/config` from the `hosts_usb` store.
4. Creates timestamped backup before every mutation.
5. Honors `DRY_RUN` flag.

**Error States:**
- Host already exists → warns, offers overwrite
- Generate with no hosts → warning message
- SSH config not writable → error message

**Fallback:** N/A — self-contained script.

## FS-005 — System Health Dashboard

**Module Ref:** MOD-011 | **Rollback Tag:** `[FS-005-v1]` | **Feature Flag:** `FEAT_SYSMAN`

**Purpose:** Interactive system health monitoring and repair.

**Components:**
- CLI flags: `--health`, `--info`, `--disk`, `--network`, `--services`, `--startup`, `--process`, `--logs`, `--repair`, `--cleanup`, `--text`, `--dry-run`
- Whiptail interactive menu with text fallback
- Delegates cleanup to `clean-local.sh`

**Rules:**
1. Self-contained. No args = whiptail interactive menu with text fallback.
2. `--cleanup` delegates to `clean-local.sh`.
3. `--network` uses `-N` (not `-n`, which is `--dry-run`).
4. Honors `DRY_RUN` flag.

**Error States:**
- whiptail unavailable → falls back to text menu
- Permission denied → suggests running with sudo
- Service check fails → reports individual service status

**Fallback:** Text menu when whiptail unavailable.

## FS-006 — Hemlock Runtime TUI

**Module Ref:** MOD-015, MOD-016 | **Rollback Tag:** `[FS-006-v1]` | **Feature Flag:** `FEAT_HEMLOCK_TUI`

**Purpose:** Interactive agent lifecycle management running inside the Docker container.

**Components:**
- Host-side CLI (`hemlock-runtime/scripts/hemlock`) for container lifecycle
- In-container TUI (`hemlock-runtime/scripts/runtime.sh`) for agent management
- Staging bridge for file transfers between host and container
- Background `watch_requests` loop for import/export

**Launch Sequence:**
1. Host: `hemlock-runtime/scripts/hemlock menu` (or no args, or `m`)
2. Script ensures container `hemlock_runtime` is up: `docker compose -f docker-compose.runtime.yml up -d`
3. Starts background `watch_requests` loop for import/export staging
4. Runs: `docker exec -it hemlock_runtime /scripts/runtime.sh`

**Main Menu (runtime.sh):**
1. Agent Management → Create, Import, Export, Delete, Start, Stop, Monitor, List
2. Crew Management (A2A) → Create, Import, Export, Join, Leave, List All, Start, Monitor, Dissolve
3. Runtime Validation → Full Validation, Hermes Doctor, Check Docker Env, Validate Configs
4. Security Hardening → Apply, Check Status, Reset
5. System Monitoring → Runtime Logs, Agent Logs, System Health
6. Configuration → Edit Runtime/Agent Config, View Current Config
7. Exit

**Rules:**
1. Container port 18789.
2. Host files not visible in-container — uses `hemlock import/export` staging via `volumes/imports/.request`.
3. `HEMLOCK_DIR` must be set or auto-detected.
4. Docker daemon must be running.

**Error States:**
- HEMLOCK_DIR not set → error with setup instructions
- Docker not running → error message
- Container fails to start → error with docker logs
- Staging file not found → error with import instructions

**Fallback:** N/A — container runtime requires Docker.

## FS-007 — USB Auto-Mount Service

**Module Ref:** MOD-013 | **Rollback Tag:** `[FS-007-v1]` | **Feature Flag:** `FEAT_AUTOMOUNT`

**Purpose:** Automatic USB device mounting via udev + systemd.

**Components:**
- Setup script: `usb-automount/setup-usb-automount.sh`
- Teardown script: `usb-automount/teardown-usb-automount.sh`
- Mount handler: `/usr/local/bin/usb-mount.sh`
- udev rule: `/etc/udev/rules.d/99-usb-automount.rules`
- systemd service: `/etc/systemd/system/usb-automount.service`

**Installation:** `sudo ./usb-automount/setup-usb-automount.sh`

**Installs:**
- `/usr/local/bin/usb-mount.sh` — mount handler (ext2/3/4, exfat, ntfs, vfat, btrfs, xfs, iso9660, udf)
- `/etc/udev/rules.d/99-usb-automount.rules` — udev trigger on block device add/remove
- `/etc/systemd/system/usb-automount.service` — Type=oneshot, RemainAfterExit=yes
- Mount base at `/mnt/usb/<device>[-<label>]`

**Rules:**
1. Requires root for install/removal.
2. Affects all USB devices system-wide.
3. Supports multiple filesystem types.

**Error States:**
- Not root → error message, suggests sudo
- udev not available → error message
- systemd not available → error message

**Fallback:** N/A — requires root and system services.

## FS-008 — USB Paths & Environment (menu option 19)

**Module Ref:** MOD-008, MOD-003 | **Rollback Tag:** `[FS-008-v1]` | **Feature Flag:** `FEAT_SETUP_ASSISTANT`

**Purpose:** Make the entire USB file-tree schema configurable so paths are whatever the user wants, with detected defaults.

**Components:**
- Sourced config `~/.config/usb-compute-automation/usb-paths.conf` (KEY=VALUE), loaded at startup by `_uca_load_paths_config`.
- Companion `usb-env.conf` for arbitrary env vars (sourced with `set -a`).
- Configurable keys: `UCA_VENTOY_MOUNT`, `UCA_PERSISTENCE_DIR`, `UCA_PERSISTENCE_VOLUMES` (colon-separated extras), `UCA_STARTUP_SCRIPT`, `UCA_ESSENTIALS_SCRIPT`, `UCA_RCLOCAL_PATH`, `UCA_ISO_PATH`, `UCA_QEMU_RAM`, `UCA_QEMU_CPUS`, `UCA_QEMU_SSH_PORT`, `UCA_BOOT_TARGET`, `UCA_INSTALL_TARGET`.
- Submenu: show current + resolved values, edit a setting, manage env vars, open in `$EDITOR`, save, reset to auto-detect, discover persistence volumes.

**Rules:**
1. Empty value = auto-detect (resolvers `_uca_mount`, `_uca_persistence_dir`, `_uca_startup_script` fall back to detection).
2. Writes honor `DRY_RUN`. 3. Env vars persisted with `printf %q` and exported into the live session.

**Error States:** unreadable config → warning, continue with defaults. **Fallback:** all defaults derive from the live mount.

## FS-009 — USB Access & Boot (menu option 20)

**Module Ref:** MOD-003, MOD-008, MOD-012 | **Rollback Tag:** `[FS-009-v1]` | **Feature Flag:** `FEAT_VENTOY`

**Purpose:** Single place to reach the USB by terminal, chroot, or VM — plus USB-first tooling install and OS-aware autostart.

**Components / actions:**
1. Shell at Ventoy mount. 2. Exec shell into a loop-mounted persistence volume (RW). 3. Chroot into a persistence volume (binds `/dev /proc /sys /dev/pts`, cleanup on exit via `_uca_unmount_tree`). 4. Edit rc.local on a chosen volume. 5. QEMU **headless** boot + SSH `hostfwd=tcp::PORT-:22` (snapshot by default). 6. QEMU **GUI** boot. 7. Boot a live ISO. 8. SSH into the running VM. 9. Install dev tooling **into the USB** (chroot apt). 10. OS-aware headless-boot autostart (systemd user service on Linux).
- Multi-volume via `_uca_select_volume` (auto-discovers `*.dat`/`*.img` + configured extras).

**Rules:**
1. **USB-first install policy:** tooling installs onto the USB by default; host installs only via `_uca_require_host_dep`, which explains *why* the dep is host-side and shows the OS-detected install command before prompting.
2. Every destructive/boot/install action honors `DRY_RUN`, confirms first, checks tooling, and cleans up mounts.
3. Booting the whole USB device defaults to QEMU `-snapshot` (writes discarded) because the drive is also host-mounted — persistent mode requires explicit risk acknowledgement.

**Error States:** no volume found / not a rootfs / QEMU absent / no `/dev/kvm` → explained messages, graceful return. **Fallback:** chroot/exec degrade to clear errors; VM runs without KVM (slow) if `/dev/kvm` absent.

---

---

# PART IV — DATA ARCHITECTURE

> **Rollback Tag:** `[DATA-ARCH-v1]`
> **Rule:** All configuration changes require backup before modification.
> This is a shell-based system — "schemas" are config file formats, not SQL.
> No database migration files exist; configuration changes are tracked via
> the append-only change log.

## 4.1 Core Data Stores

### JSON Configuration Store

**Path:** `~/.config/usb-compute-automation/config.json`
**Override:** `UCA_CONFIG_DIR` / `UCA_CONFIG_FILE` environment variables

```json
{
  "version": "1.0.0",
  "last_updated": "2026-06-25T00:00:00Z",
  "installations": {},
  "host_id": {
    "host_id": "usb-compute-<md5(hostname+mac)[:8]>",
    "timestamp": "ISO8601",
    "hostname": "string",
    "mac_address": "string",
    "ip_address": "string",
    "os_info": "Linux|macOS|WSL|Windows|Unknown",
    "kernel_version": "string"
  }
}
```

**Mutation rules:** All writes via `config_set` use atomic mktemp+mv. Auto-stamps `.last_updated`.

The config store acts as this system's database equivalent. Conceptual schema:

```sql
-- Conceptual schema (implemented as JSON, not SQL)
-- No database migration files; config format changes tracked via change log.
CREATE TABLE config (
  key         TEXT PRIMARY KEY,
  value       JSON NOT NULL,
  updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Alias Store

**Path:** `~/.bash_aliases_usb`
**Format:** `alias name='command' # description` (one per line)
**Backups:** `~/.alias_backups/` (timestamped copies before mutation)

### SSH Host Store

**Path:** `~/.ssh/hosts_usb`
**Format:** Pipe-delimited `alias|hostname|user|port|key_path|description`
**Backups:** `~/.ssh/hosts_backups/`
**Generated output:** `~/.ssh/config` (via `--generate` flag; NOT the primary store)

### Ventoy Persistence Volume

**Path:** `$VENTOY_MOUNT/persistence/ubuntu-persistence.dat`
**Filesystem:** ext4 with label `casper-rw`
**Default size:** 8 GB (user-overridable at creation)
**Access:** Loop-mount for host-side chroot or file injection

## 4.2 USB Partition Layout

```
USB Drive (Ventoy-managed):
├── Partition 1 (exFAT) ── host-accessible
│   ├── *.iso                          — bootable ISO images
│   ├── ventoy/                        — Ventoy bootloader config
│   └── persistence/
│       └── ubuntu-persistence.dat     — casper-rw ext4 volume
└── Partition 2 (Ventoy EFI) ── managed by Ventoy installer
```

## 4.3 Docker Volume Layout (Hemlock)

```
hemlock-runtime/
├── agents/          — agent definitions and state
├── crews/           — crew definitions and membership
├── config/          — runtime and agent configuration
├── data/            — runtime data store
├── models/          — AI model files
├── skills/          — 84 skill packages (copied from hemlock-minimal/skills/)
├── plugins/         — runtime plugins
├── shared/          — shared libraries
└── volumes/
    └── imports/
        └── .request — staging protocol file for import/export
```

## 4.4 CLI Contract Specifications (API equivalent)

The `cli/usbctl` dispatcher serves as this system's API layer:

```
POST /api/v1/usb/detect      → usbctl usb detect
POST /api/v1/usb/mount        → usbctl usb mount       (requires SELECTED_DEVICE)
POST /api/v1/usb/unmount      → usbctl usb unmount
GET  /api/v1/usb/persistence  → usbctl usb persistence
GET  /api/v1/config/show      → usbctl config show
POST /api/v1/config/init      → usbctl config init
POST /api/v1/config/host-id   → usbctl config host-id
GET  /api/v1/validate/all     → usbctl validate all
```

All CLI commands return exit code 0 on success, 1 on error, with structured
output via `print_success/error/warning/info`.

## 4.5 Port Allocations

| Port | Service | Protocol | Location |
|---|---|---|---|
| 18789 | Hemlock Gateway (openclaw) | HTTP | Docker container → host |
| 41214 | MCP Proxy | TCP | Docker container |
| 2222 | SSH Forward (host side) | TCP | Host → guest VM |
| 22 | SSH (guest side) | TCP | Guest VM |
| 8888 | Jupyter (optional) | HTTP | Container compute |
| 8080 | Web (optional) | HTTP | Container compute |
| 11434 | Ollama (optional) | HTTP | Container compute |

## 4.6 Migration Naming Convention

This is a shell-based system with no database. Migrations are file-based config changes
backed by backup/restore patterns, not SQL migrations.

**Convention for config changes (migration replacement):**
- Config files are backed up before modification: `config.json.bak.YYYYMMDD_HHMMSS`
- SSH host store backed up: `hosts_usb.bak.YYYYMMDD_HHMMSS`
- Alias file backed up: `aliases_usb.YYYYMMDD_HHMMSS.bak`
- Persistence images are immutable — resize creates new, old is kept as fallback
- Naming uses `YYYYMMDD_HHMMSS` timestamp for sortability and human readability

**Rollback mechanism:** Every `config_set` call writes atomic backup. Rollback =
`mv config.json.bak.YYYYMMDD_HHMMSS config.json`. No migration numbering needed.
Backup files older than 30 days are auto-pruned by `cleanup_backups` (MOD-018).

**Validation:** `validate_config_consistency` (MOD-016) checks config structure integrity.
If config is malformed, `self_heal` restores from most recent backup (rollback to latest YYYYMMDD file).

---

---

# PART V — CHANGE CONTROL PROTOCOL

> **Rollback Tag:** `[CHANGE-CONTROL-v1]`
> **This section is permanent and non-negotiable.**
> Every contributor must read this section before making any change.

## Change Log Entry Format

Every entry MUST include all fields below. Entries are permanent.
No entry may be modified or deleted after writing.

```
Date        : YYYY-MM-DD HH:MM UTC
Contributor : [name/handle]
Modules     : [MOD-XXX, ...]
Section Tags: [[TAG-NAME-v1], ...]
Files Changed: [every file changed]
Description : [What changed and why — minimum 3 sentences]
Tests Passing: [bash -n results, --dry-run results, or 'none — pre-build']
Phase       : [PHASE-N]
Rollback Ref: [git commit hash or file backup timestamp]
```

## Contributor Rules

1. No script modification merged without a change log entry in the same commit.
2. No destructive USB operation without `--dry-run` validation first.
3. Feature flags (DRY_RUN environment variable) required for all mutation paths.
4. Minimum: `bash -n` syntax check on every modified .sh file.
5. All backup stores (~/.alias_backups, ~/.ssh/hosts_backups) must be populated before mutation.
6. No contributor may modify or delete an existing change log entry.
7. Self-contained scripts (sysman, ssh_host_manager, setup-essentials) must not be refactored to depend on lib/ without explicit blueprint amendment.
8. Monolith scripts (usb-setup-assistant.sh) retain their own utility functions; do not assume lib/ is available.

---

---

# PART VI — MASTER IMPLEMENTATION CHECKLIST

## Phase 0: Pre-Build Environment

**Section Tag:** `[PHASE-0-v1]`
**Feature Flag:** `FEAT_PRE_BUILD_ENVIRONMENT`
**Assigned Agent:** _unassigned_

### Prerequisites

N/A — this is the first phase.

### Implementation Steps

- [ ] **Step 1:** Verify host machine has Bash 4+, `jq`, `docker`, `docker compose` v2 installed
  - _Validation:_ `bash --version`, `jq --version`, `docker info`, `docker compose version` all succeed
  - _Rollback:_ N/A — verification only
- [ ] **Step 2:** Verify `usb/` directory structure: lib/7, cli/1, scripts/7, usb-automount/, tests/16, and supporting files
  - _Validation:_ `ls usb/lib/*.sh` returns 7 files, `ls usb/cli/usbctl` exists
  - _Rollback:_ N/A — verification only
- [ ] **Step 3:** Verify `hemlock/` directory structure: DEPLOY.sh, hemlock-tui, hemlock-runtime/, hemlock-minimal/skills/
  - _Validation:_ `ls hemlock/DEPLOY.sh hemlock/hemlock-tui hemlock/hemlock-runtime/scripts/hemlock` all exist
  - _Rollback:_ N/A — verification only
- [ ] **Step 4:** Run `bash -n` on all .sh files in usb/
  - _Validation:_ `bash -n usb/cli/usbctl usb/lib/*.sh usb/scripts/*.sh usb/sysman.sh usb/usb-setup-assistant.sh` exits 0
  - _Rollback:_ N/A — verification only
- [ ] **Step 5:** Verify Docker daemon running
  - _Validation:_ `docker info` succeeds
  - _Rollback:_ N/A — verification only
- [ ] **Step 6:** Set HEMLOCK_DIR environment variable
  - _Validation:_ `test -d "$HEMLOCK_DIR/scripts"` succeeds
  - _Rollback:_ `unset HEMLOCK_DIR`

### Phase Validation Gate

> All tools installed. All syntax checks pass. Docker daemon responsive. USB drive visible. Environment variables set.

### Agent Sign-Off

```
Phase 0 Sign-Off:
  Agent     : _________________
  Date      : _________________
  Notes     : _________________
```

---

## Phase 1: USB Foundation and Ventoy

**Section Tag:** `[PHASE-1-v1]`
**Feature Flag:** `FEAT_USB_FOUNDATION_AND_VENTOY`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 0 complete. Host tools verified. USB drive connected.

### Implementation Steps

- [x] **Step 1:** Fix MOD-007 usbctl alias path bug (FIXED in usb-hemlock-split/)
  - _Validation:_ `usb/cli/usbctl alias --list` runs without "not found" error
  - _Rollback:_ Revert `$PROJECT_ROOT/scripts/alias_manager.sh` to `$PROJECT_ROOT/alias_manager.sh`
- [x] **Step 2:** Fix MOD-009 alias_manager.sh source path (FIXED in usb-hemlock-split/)
  - _Validation:_ `bash usb/scripts/alias_manager.sh --list` runs without "lib/core.sh not found" error
  - _Rollback:_ Revert `$SCRIPT_DIR/../lib/*.sh` to `$SCRIPT_DIR/lib/*.sh`
- [ ] **Step 3:** Export SELECTED_DEVICE and verify USB detection
  - _Validation:_ `lsblk` shows USB device, `cli/usbctl usb detect` returns device info
  - _Rollback:_ `unset SELECTED_DEVICE`
- [ ] **Step 4:** Install Ventoy to USB (WARNING: erases USB)
  - _Validation:_ Ventoy files present on USB root
  - _Rollback:_ Re-format USB with desired filesystem
- [ ] **Step 5:** Verify Ventoy tarball at `usb/volumes/ventoy/ventoy-1.0.99-linux.tar.gz`
  - _Validation:_ `test -f usb/volumes/ventoy/ventoy-1.0.99-linux.tar.gz`
  - _Rollback:_ N/A — file verification only
- [ ] **Step 6:** Test `detect_ventoy_mount` succeeds
  - _Validation:_ `source usb/lib/usb.sh; detect_ventoy_mount && echo "OK: $VENTOY_MOUNT"`
  - _Rollback:_ N/A — test only
- [ ] **Step 7:** Copy at least one bootable ISO to USB root
  - _Validation:_ `ls *.iso` on USB root shows at least one file
  - _Rollback:_ Delete ISO from USB
- [ ] **Step 8:** Initialize config and generate host-id
  - _Validation:_ `cli/usbctl config init` creates config.json, `cli/usbctl config host-id` generates ID
  - _Rollback:_ `rm -rf ~/.config/usb-compute-automation/`

### Phase Validation Gate

> Ventoy installed on USB. Mount detection works. Config JSON created with valid host-id. usbctl runs without errors.

### Agent Sign-Off

```
Phase 1 Sign-Off:
  Agent     : _________________
  Date      : _________________
  Notes     : _________________
```

---

## Phase 2: Persistence Layer and Partitioning

**Section Tag:** `[PHASE-2-v1]`
**Feature Flag:** `FEAT_PERSISTENCE_LAYER_AND_PARTITIONING`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 1 complete. Ventoy mounted. SELECTED_DEVICE exported.

### Implementation Steps

- [ ] **Step 1:** Create persistence file via `usb-setup-assistant.sh` option 2 → submenu option 3
  - _Validation:_ `persistence/ubuntu-persistence.dat` exists on USB
  - _Rollback:_ `rm $VENTOY_MOUNT/persistence/ubuntu-persistence.dat`
- [ ] **Step 2:** Verify ext4 with casper-rw label
  - _Validation:_ `blkid` shows LABEL=casper-rw, TYPE=ext4
  - _Rollback:_ N/A — format verification only
- [ ] **Step 3:** Test `check_persistence_exists` and `get_persistence_size`
  - _Validation:_ Both functions return 0 and correct size
  - _Rollback:_ N/A — test only
- [ ] **Step 4:** Loop-mount persistence and verify
  - _Validation:_ `sudo mount -o loop $VENTOY_MOUNT/persistence/ubuntu-persistence.dat /mnt/test` succeeds
  - _Rollback:_ `sudo umount /mnt/test`
- [ ] **Step 5:** Install USB auto-mount service
  - _Validation:_ `systemctl is-enabled usb-automount.service` returns enabled
  - _Rollback:_ `sudo usb/usb-automount/teardown-usb-automount.sh`

### Phase Validation Gate

> Persistence file exists with correct ext4/casper-rw label. Loop-mount succeeds. Auto-mount service triggers on USB insert.

### Agent Sign-Off

```
Phase 2 Sign-Off:
  Agent     : _________________
  Date      : _________________
  Notes     : _________________
```

---

## Phase 3: Service Integration

**Section Tag:** `[PHASE-3-v1]`
**Feature Flag:** `FEAT_SERVICE_INTEGRATION`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 2 complete. Persistence created. lib/ modules loadable.

### Implementation Steps

- [ ] **Step 1:** Test alias manager CLI: add → list → search → remove
  - _Validation:_ `bash usb/scripts/alias_manager.sh --dry-run --add test 'echo test' 'Test alias'` succeeds
  - _Rollback:_ `rm ~/.bash_aliases_usb; restore from ~/.alias_backups/`
- [ ] **Step 2:** Test alias import/export in all formats
  - _Validation:_ `--export table`, `--export csv`, `--export json` all produce output
  - _Rollback:_ N/A — test only
- [ ] **Step 3:** Test SSH host manager CLI: add → list → test → remove
  - _Validation:_ `bash usb/scripts/ssh_host_manager.sh --dry-run --add myhost example.com user 22` succeeds
  - _Rollback:_ `rm ~/.ssh/hosts_usb; restore from ~/.ssh/hosts_backups/`
- [ ] **Step 4:** Test SSH config generation
  - _Validation:_ `bash usb/scripts/ssh_host_manager.sh --generate` writes `~/.ssh/config`
  - _Rollback:_ `rm ~/.ssh/config`
- [ ] **Step 5:** Test usbctl alias integration
  - _Validation:_ `usb/cli/usbctl alias --list` runs without error
  - _Rollback:_ N/A — test only

### Phase Validation Gate

> Both managers complete full CRUD cycle. Backups created. Config generation works. Interactive menus navigable with b/q.

### Agent Sign-Off

```
Phase 3 Sign-Off:
  Agent     : _________________
  Date      : _________________
  Notes     : _________________
```

---

## Phase 4: System Management and Health

**Section Tag:** `[PHASE-4-v1]`
**Feature Flag:** `FEAT_SYSTEM_MANAGEMENT_AND_HEALTH`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 3 complete. SSH and alias services operational.

### Implementation Steps

- [ ] **Step 1:** Test sysman.sh interactive menu and all CLI flags
  - _Validation:_ `bash usb/sysman.sh --health` reports CPU/memory/disk/services
  - _Rollback:_ N/A — read-only operations
- [ ] **Step 2:** Test network diagnostics, disk analysis, service status
  - _Validation:_ `bash usb/sysman.sh --network`, `--disk`, `--services` all produce output
  - _Rollback:_ N/A — read-only operations
- [ ] **Step 3:** Test cleanup delegation
  - _Validation:_ `bash usb/sysman.sh --cleanup` invokes `clean-local.sh`
  - _Rollback:_ N/A — cleanup is non-destructive
- [ ] **Step 4:** Test `cli/usbctl validate all`
  - _Validation:_ Host-id validated, USB mount validated, menu stack validated
  - _Rollback:_ N/A — validation only
- [ ] **Step 5:** Test essentials installer dry-run
  - _Validation:_ `sudo bash usb/scripts/setup-essentials-enhanced.sh --dry-run` lists packages without side effects
  - _Rollback:_ N/A — dry-run only

### Phase Validation Gate

> sysman reports accurately. usbctl validate all passes. Essentials dry-run lists all packages without side effects.

### Agent Sign-Off

```
Phase 4 Sign-Off:
  Agent     : _________________
  Date      : _________________
  Notes     : _________________
```

---

## Phase 5: Hemlock Runtime Deployment

**Section Tag:** `[PHASE-5-v1]`
**Feature Flag:** `FEAT_HEMLOCK_RUNTIME_DEPLOYMENT`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 4 complete. Docker running. USB persistence active.

### Implementation Steps

- [ ] **Step 1:** Build Docker images
  - _Validation:_ `docker compose -f docker-compose.runtime.yml build` succeeds
  - _Rollback:_ `docker image prune -a --filter "label=hemlock"`
- [ ] **Step 2:** Start runtime container
  - _Validation:_ `docker ps | grep hemlock_runtime` shows running container
  - _Rollback:_ `docker compose -f docker-compose.runtime.yml down`
- [ ] **Step 3:** Verify port 18789 accessible
  - _Validation:_ `curl -s http://localhost:18789/health` responds
  - _Rollback:_ N/A — verification only
- [ ] **Step 4:** Test Hemlock CLI
  - _Validation:_ `hemlock/hemlock-runtime/scripts/hemlock status` reports status
  - _Rollback:_ N/A — read-only
- [ ] **Step 5:** Test import/export staging protocol
  - _Validation:_ Create `.request` file in volumes/imports/, verify watch_requests fulfills it
  - _Rollback:_ Remove test .request file
- [ ] **Step 6:** Test DEPLOY.sh dry-run
  - _Validation:_ `sudo bash hemlock/DEPLOY.sh --dry-run --no-system --no-usb` completes without errors
  - _Rollback:_ N/A — dry-run only

### Phase Validation Gate

> Docker containers running. Port 18789 responding. hemlock CLI reports status. Import/export staging works.

### Agent Sign-Off

```
Phase 5 Sign-Off:
  Agent     : _________________
  Date      : _________________
  Notes     : _________________
```

---

## Phase 6: USB-Hemlock Bridge and TUI Integration

**Section Tag:** `[PHASE-6-v1]`
**Feature Flag:** `FEAT_USB_HEMLOCK_BRIDGE_AND_TUI_INTEGRATION`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 5 complete. Hemlock containers running. USB system operational.

### Implementation Steps

- [ ] **Step 1:** Set HEMLOCK_DIR correctly
  - _Validation:_ `test -d "$HEMLOCK_DIR/scripts" && test -f "$HEMLOCK_DIR/scripts/hemlock"`
  - _Rollback:_ `unset HEMLOCK_DIR`
- [x] **Step 2:** Fix hemlock-tui auto-detection (FIXED in usb-hemlock-split/)
  - _Validation:_ `usb/hemlock-tui` finds hemlock-runtime without manual HEMLOCK_DIR
  - _Rollback:_ Revert to hardcoded path (not recommended)
- [ ] **Step 3:** Test Hemlock TUI launch from USB menu
  - _Validation:_ `menu.sh` option 8 opens Hemlock TUI
  - _Rollback:_ N/A — test only
- [ ] **Step 4:** Test end-to-end flow: USB menu → Hemlock TUI → create agent → export agent
  - _Validation:_ Agent created, exported, and file available on host
  - _Rollback:_ Delete test agent
- [ ] **Step 5:** Test DEPLOY.sh full execution (or validated dry-run)
  - _Validation:_ `sudo bash hemlock/DEPLOY.sh --dry-run` produces no errors
  - _Rollback:_ N/A — dry-run only
- [ ] **Step 6:** Test bidirectional file transfer
  - _Validation:_ Host file → `hemlock import` → container, container → `hemlock export` → host
  - _Rollback:_ Remove test files

### Phase Validation Gate

> Single command from USB menu launches Hemlock TUI. Agent creation/export round-trip succeeds. DEPLOY.sh dry-run produces no errors.

### Agent Sign-Off

```
Phase 6 Sign-Off:
  Agent     : _________________
  Date      : _________________
  Notes     : _________________
```

---

## Phase 7: Validation and Hardening

**Section Tag:** `[PHASE-7-v1]`
**Feature Flag:** `FEAT_VALIDATION_AND_HARDENING`
**Assigned Agent:** _unassigned_

### Prerequisites

Phase 6 complete. Full USB-to-Hemlock pipeline operational.

### Implementation Steps

- [ ] **Step 1:** Run `bash -n` on ALL .sh files in both directories
  - _Validation:_ Zero syntax errors
  - _Rollback:_ N/A — verification only
- [ ] **Step 2:** Test `--dry-run` on every mutation-capable script
  - _Validation:_ usbctl, alias_manager, ssh_host_manager, sysman, setup-essentials, DEPLOY.sh all honor dry-run
  - _Rollback:_ N/A — dry-run only
- [ ] **Step 3:** Run `cli/usbctl validate all`
  - _Validation:_ Passes without warnings
  - _Rollback:_ N/A — validation only
- [ ] **Step 4:** Run Hemlock runtime validation
  - _Validation:_ TUI → Runtime Validation → Run Full Validation passes
  - _Rollback:_ TUI → Security Hardening → Reset
- [ ] **Step 5:** Run Hemlock Hermes Doctor
  - _Validation:_ TUI → Runtime Validation → Hermes Doctor passes
  - _Rollback:_ N/A — diagnostic only
- [ ] **Step 6:** Verify all 7 known bugs are FIXED
  - _Validation:_ All bugs documented in AGENTS.md §5 are verified fixed
  - _Rollback:_ N/A — verification only
- [ ] **Step 7:** Run test suite
  - _Validation:_ `bash usb/tests/run-all.sh` passes (163+ assertions)
  - _Rollback:_ N/A — test only
- [ ] **Step 8:** Verify documentation accuracy
  - _Validation:_ README.md, AGENTS.md, blueprint.md all reflect actual file paths
  - _Rollback:_ N/A — documentation only

### Phase Validation Gate

> Zero `bash -n` failures. All dry-runs succeed. Validation engine passes. Hemlock Doctor clean. All 7 bugs verified fixed. Test suite passes. Documentation accurate.

### Agent Sign-Off

```
Phase 7 Sign-Off:
  Agent     : _________________
  Date      : _________________
  Notes     : _________________
```

---

---

# PART VII — QUALITY & COMPLIANCE STANDARDS

> **Rollback Tag:** `[QUALITY-v1]`

## Error Handling Standards

1. **Graceful degradation:** All menus return to previous level on error; traps handle INT/TERM without hard exits. `set_standard_traps` converts signals to `return`, not `exit`.
2. **User-facing messages:** Use `print_error/warning/info/success` from lib/core.sh (or local equivalents in monoliths). No raw stack traces.
3. **Internal logging:** `uca_log LEVEL MSG` with timestamp. Writes to `$LOG_FILE` when set. USB assistant logs to `/tmp/usb-setup-assistant-*.log`.
4. **Dry-run safety:** Every mutation path must honor `DRY_RUN=true` or `--dry-run`. Use `run_or_dry` for external commands, `safe_exec` for timeout-protected operations.
5. **Sudo isolation:** Never run entire scripts as root. Use per-operation `require_root` (returns 1) or sudo-caching helper with EXIT trap cleanup.
6. **Circuit breaker / retry:** External commands (USB mount, Ventoy operations, Docker calls) use `safe_exec "desc" <timeout_secs> cmd...` which enforces a timeout and captures stderr. On timeout or non-zero exit, `safe_exec` returns the exit code — callers must check and handle (typically `print_error` + `return 1`). No automatic retry — retries mask hardware issues. For transient network operations (Tailscale, apt), callers may implement manual retry with backoff (3 attempts, 2/4/8 second delays).

## Coding Standards

1. Shebang: `#!/usr/bin/env bash`
2. Safety: `set -euo pipefail` on every entrypoint script
3. Guard: `[[ -n "${UCA_<MODULE>_SH_SOURCED:-}" ]] && return 0` on every lib module
4. Colors: Use `: "${RED:=\033[0;31m}"` pattern (overridable defaults), never hard-assign
5. Help: Every script supports `-h`/`--help`
6. Logging: Structured with timestamp via `uca_log` or local equivalent
7. Exit codes: 0 = success, 1 = error, 130 = interrupted (INT), 143 = terminated (TERM)
8. Style: Match the file you edit. lib/ scripts use lib/ conventions. Monoliths (usb-setup-assistant.sh, sysman.sh, ssh_host_manager.sh) use their own declarations.

## Testing Requirements

- Syntax validation: `bash -n` on all modified .sh files (mandatory, no exceptions)
- Dry-run validation: `--dry-run` or `DRY_RUN=true` tests of all mutation paths
- Validation engine: `cli/usbctl validate all` checks host-id, USB mount, menu stack
- Hemlock validation: Runtime Validation menu (full validation + Hermes Doctor)
- Integration: End-to-end from USB menu → Hemlock TUI → agent lifecycle verified manually
- Coverage metric: Every lib/ function called by at least one test/validation path
- Target: 100% coverage of lib/ exported functions via usbctl validate + manual test

## Performance Budgets

| Metric | Budget |
|---|---|
| USB mount detection (detect_ventoy_mount) | < 5 seconds across all 5 fallback methods |
| Menu response time (interactive) | < 1 second between selections |
| Config read/write (config_get/set) p95 | < 500ms including jq parse |
| Docker container startup (hemlock_runtime) | < 30 seconds to responding state |
| Persistence creation (8 GB dd + mkfs) | < 10 minutes (hardware dependent) |
| Hemlock agent creation via TUI | < 60 seconds end-to-end |
| Full DEPLOY.sh execution | < 30 minutes (network dependent) |
| bash -n syntax check (all files) | < 5 seconds |
| Hemlock gateway response p95 | < 2 seconds on port 18789 |

---

---

# CHANGE LOG

> This section is append-only. No entry may be modified or deleted.

## CL-000 — Document Initialization

```
Date        : 2026-06-25 08:39 UTC
Contributor : OpenCode
Modules     : MOD-001 through MOD-021
Section Tags: [SYS-OVERVIEW-v1], [MODULE-REGISTRY-v1], [SPECS-v1], [DATA-ARCH-v1], [CHANGE-CONTROL-v1], [QUALITY-v1], [PHASE-0-v1] through [PHASE-7-v1]
Files Changed: blueprint.md, checklist.md, project.json
Description : Initial blueprint created via enterprise-blueprint skill and
              populated with real architecture from codebase analysis.
              837-line scaffold generated, then overwritten with complete
              content: 21 modules (MOD-001 through MOD-021), 7 screen specs
              (FS-001 through FS-007), 8 implementation phases with pre-phase
              gates and agent sign-off blocks, data architecture adapted for
              shell-based system (JSON config stores, no SQL migrations),
              quality standards with performance budgets. All 7 verified bugs
              marked as FIXED. Menu restructured from 14-option
              usb-setup-assistant.sh to 18-option menu.sh with target labels.
Tests Passing: bash -n on all lib/*.sh and cli/usbctl — PASS
Phase       : PHASE-0
Rollback Ref: N/A — initial document creation
```

## CL-001 — menu.sh Interactivity Hardening + Documentation Reconciliation

```
Date        : 2026-06-25 04:50 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-008, MOD-005
Section Tags: [SPECS-v1], [SYS-OVERVIEW-v1]
Files Changed: menu.sh, blueprint/blueprint.md, AGENTS.md
Description : Fixed 6 defects in menu.sh found during an interactivity audit
              against this blueprint's FS-001 spec. (1) Text mode silently
              swallowed all component output — menu.sh now drives its main
              handler with its own inline loop instead of lib/menu.sh's
              menu_loop, which captured handler stdout via command
              substitution. (2) Whiptail mode passed "3>&1 1>&2 2>&3" as a
              literal string argument instead of a real fd redirection,
              breaking GUI mode entirely. (3) Whiptail Cancel/ESC looped
              forever with no quit path; Cancel is now relabeled "Quit" and
              exits cleanly. (4) USB device auto-detection stripped spaces
              from lsblk output, producing a mangled device path
              (/dev/sdb1exfatVentoy) instead of the base disk
              detect_ventoy_mount() expects (/dev/sdb). (5) Alias/SSH manager
              runners used ${DRY_RUN:+--dry-run}, which expands whenever
              DRY_RUN is set to anything (including the literal string
              "false"), so they silently always ran dry. (6) All handler
              invocations are now guarded with `|| true` so a non-zero
              return from any component cannot trip set -e and abort the
              whole menu; read EOF now breaks the loop instead of busy-
              looping. Updated FS-001 in this document and AGENTS.md
              Sections 5-7 to reflect the corrected 19-option behavior
              (the menu item count was already 19 at runtime; the prose
              describing navigation mechanics was stale at 18-option/
              menu_loop-based text).
Tests Passing: bash -n on menu.sh + all usb/lib/*.sh, usb/cli/usbctl,
              usb/scripts/*.sh, usb/sysman.sh, usb/usb-setup-assistant.sh —
              PASS. usb/tests/run-all.sh — 201 passed, 0 failed, 1 skipped.
              Live verification: text-mode output now renders; invalid
              input/EOF/empty input exit or re-prompt cleanly (no hang);
              whiptail renders correctly under a real PTY and Quit/ESC exits
              with code 0; device auto-detection resolves to /dev/sdb and
              mounts Ventoy; dry-run toggle and conditional flag-passing
              verified.
Phase       : PHASE-7
Rollback Ref: Pre-fix menu.sh preserved in conversation history; revert via
              git or manual restoration of the 6 patched regions.
```

## CL-002 — Component Hardening: Stall Bounds, Dry-Run Honesty, Non-Interactive CLI, Permissions

```
Date        : 2026-06-25 05:10 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-011, MOD-009, MOD-010, MOD-007
Section Tags: [SPECS-v1], [QUALITY-v1], [PHASE-4-v1], [PHASE-7-v1]
Files Changed: usb/sysman.sh, usb/scripts/alias_manager.sh,
              usb/scripts/ssh_host_manager.sh, blueprint/checklist.md,
              CHANGELOG.md, (perms) usb/** + hemlock entry-points
Description : Hardening pass across the authored components following the
              menu.sh fixes in CL-001. (1) MOD-011 sysman.sh had two real
              stalls: `--disk` ran an unbounded `find /home -type f -exec du`
              (walks every file) and `--services` ran `journalctl -p err`
              that took 17s+ on a large journal — both could exceed 30s and
              appear hung. Added a self-contained `run_bounded` timeout helper
              and applied it to the home-tree scans (depth-limited + 10s cap),
              journalctl (15s), per-service `systemctl status` (5s), DNS
              lookups (6s), and ping (added -W 2 + 8s ceiling). Per QUALITY
              §Error-Handling.6 these informational probes now degrade with a
              warning instead of stalling. (2) MOD-009/MOD-010: alias_manager
              and ssh_host_manager asserted "Added/Removed/Updated" success
              and wrote backup files even under --dry-run, violating the
              dry-run contract; added a `say_done` helper and made
              backup_*() honor DRY_RUN so dry-run is now side-effect-free and
              honestly reported. (3) MOD-010: ssh_host_manager `--add` still
              prompted interactively for key/description and RE-PROMPTED for
              port whenever port==22 — under `set -e` an EOF on those reads
              aborted the script (CLI add produced no output). Made `--add`
              fully non-interactive per FS-004 (optional fields default
              silently in CLI mode; every read tolerates EOF). A previously
              skipped SSH test now passes as a result. (4) Normalized all
              authored shell scripts (usb/** plus the 5 hemlock entry-points)
              to 0755 per GLOBAL COMPLETION CRITERIA — hemlock-stage.sh was
              0600 (not executable). (5) Reconciled checklist.md: repaired the
              malformed Phase 3 sign-off block (a misplaced Phase 0 block with
              a broken code fence), filled Phase 0/3 sign-offs, and added a
              RECONCILIATION NOTE with honest per-phase status (hardware/
              network phases 1,2,5,6 marked BLOCKED; code-level phases 3,4,7
              COMPLETE).
Tests Passing: bash -n clean on all authored scripts. usb/tests/run-all.sh —
              202 passed, 0 failed. sysman --disk/--services/--network all
              complete < 16s (were stalling > 30s). alias/ssh --dry-run
              verified side-effect-free; ssh --add round-trip (add→verify→
              remove) verified with no TTY.
Phase       : PHASE-7
Rollback Ref: Working copy; revert via git or manual restoration of the
              patched regions in the four scripts.
```

## CL-003 — Real-Hardware Verification: Mount Resolution + set-u Submenu Crash

```
Date        : 2026-06-25 05:25 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-008, MOD-003
Section Tags: [SPECS-v1], [FS-001-v1], [FS-002-v1], [PHASE-1-v1], [PHASE-2-v1]
Files Changed: menu.sh, blueprint/checklist.md, AGENTS.md, CHANGELOG.md
Description : Verified the USB/persistence paths against a REAL Ventoy drive
              (a 233G USB, /dev/sdb -> /media/drdeek/Ventoy, Ubuntu 24.04.4
              ISO, 225G ubuntu-persistence.dat). Two real bugs surfaced that
              static + dry-run checks could not catch. (1) BUG-15: the
              Persistence Manager and Startup Manager resolved the Ventoy
              mount with a hardcoded `for mp in /mnt/ventoy /Volumes/Ventoy`
              loop (10 sites) that omits /media/$USER/Ventoy — the path
              desktop Linux (GNOME/udisks) actually auto-mounts to — so on a
              standard real drive every persistence/startup action wrongly
              reported "Ventoy not mounted." Added `_resolve_ventoy_mount`
              (prefers the library-detected $VENTOY_MOUNT, then
              detect_ventoy_mount, then scans /media/$USER/Ventoy,
              /run/media/$USER/Ventoy, glob fallbacks, /mnt/ventoy,
              /Volumes/Ventoy) and replaced all 10 loops; main() now resolves
              the mount whether the device was auto-detected or pre-set via
              SELECTED_DEVICE. (2) BUG-14: `_menu_item` read `$3`/`$4`
              unconditionally while every submenu renders its Back row as
              `_menu_item "0" "Back"` (2 args); under `set -u` opening ANY
              submenu aborted with "$3: unbound variable". Defaulted the
              optional args. Both fixes verified by driving all submenu
              renders and read-only action handlers against the live drive
              with zero crashes; the status header and Persistence Manager
              now correctly show /media/drdeek/Ventoy and the 225G state.
Tests Passing: bash -n clean. usb/tests/run-all.sh — 202 passed, 0 failed.
              Live: status header shows Mount=/media/drdeek/Ventoy,
              Persistence=225G; persistence status + partition layout +
              all 6 submenus navigate without crash; detect_ventoy_mount
              resolves /dev/sdb -> /media/drdeek/Ventoy.
Phase       : PHASE-7 (with PHASE-1/PHASE-2 read-only paths now verified)
Rollback Ref: Working copy; revert via git or restoration of the patched
              menu.sh regions (_resolve_ventoy_mount, _menu_item, main()).
```

## CL-004 — Configurable Paths/Env + USB Access & Boot + USB-First Install Policy

```
Date        : 2026-06-25 06:05 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-008, MOD-003, MOD-012 (new: FS-008, FS-009)
Section Tags: [SPECS-v1], [FS-001-v1], [SYS-OVERVIEW-v1]
Files Changed: menu.sh, blueprint/blueprint.md, blueprint/checklist.md,
              AGENTS.md, CHANGELOG.md, README.md
Description : Feature amendment adding user-requested configurability and
              access. (1) FS-008 "USB Paths & Environment" (menu option 19):
              a sourced ~/.config/usb-compute-automation/usb-paths.conf makes
              the whole file-tree schema configurable — Ventoy mount override,
              persistence dir, EXTRA persistence volumes, startup/essentials
              script paths, rc.local path, ISO path, QEMU RAM/CPUs/SSH-port,
              boot target, and install target. A companion usb-env.conf stores
              arbitrary env vars (sourced with set -a at startup). The submenu
              shows current+resolved values and supports edit/save/reset/$EDITOR
              and add/remove env vars. (2) FS-009 "USB Access & Boot" (menu
              option 20): open a shell at the Ventoy mount; exec a shell into a
              loop-mounted persistence volume (RW); chroot into a persistence
              volume (binds /dev /proc /sys /dev/pts, cleanup on exit); edit
              rc.local on a chosen volume; QEMU headless boot with SSH
              hostfwd (tcp::PORT-:22, snapshot-by-default to avoid corrupting
              the host-mounted drive); QEMU GUI boot; boot a live ISO; SSH into
              the running VM; install dev tooling INTO the USB; OS-aware
              headless-boot autostart. Multi-volume support throughout via
              _uca_select_volume (auto-discovers *.dat/*.img + configured
              extras). (3) USB-FIRST INSTALL POLICY: per user directive, dev
              tooling installs onto the USB persistence by default (chroot apt);
              the host is touched only for dependencies that genuinely cannot
              be served from the portable drive — QEMU/KVM (host CPU/RAM +
              port-forwarding) and headless-boot autostart — via
              _uca_require_host_dep, which EXPLAINS why the dep is host-side,
              shows the OS-detected install command (apt/dnf/yum/pacman/zypper/
              brew), and prompts before installing. "Build Essentials"
              (option 7) now routes to the USB install by default with an
              explained host override. Menu grew to 21 options (toggle dry-run
              moved 19->21); both text and whiptail render paths updated.
              All destructive/boot/install actions honor DRY_RUN, confirm
              first, check tooling, and clean up mounts.
Tests Passing: bash -n clean. usb/tests/run-all.sh — 202 passed, 0 failed.
              Live (real /dev/sdb Ventoy): options 19/20 + all sub-actions
              render with zero set-u crashes; headless/exec/chroot/ISO/tooling
              dry-runs print correct commands and touch nothing; volume
              discovery finds the 225G state; config save/env-var persistence
              verified; host-dep gate explains + proposes the apt command for a
              missing binary.
Phase       : PHASE-7 (feature amendment)
Rollback Ref: Working copy; revert the menu.sh additions
              (_uca_* functions, options 19/20, policy helpers).
```

## CL-005 — Comprehensive USB Essentials + OpenSSH/Services Validated & Active

```
Date        : 2026-06-25 06:30 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-012, MOD-008
Section Tags: [SPECS-v1], [FS-009-v1]
Files Changed: menu.sh, blueprint/blueprint.md, CHANGELOG.md, AGENTS.md
Description : Expanded the USB-persistence tooling installer (option 20->9)
              from a flat apt list into a comprehensive, categorized installer
              that mirrors the host toolchain, generated as an in-chroot script
              (/tmp/uca-essentials.sh) and run via chroot. Categories: core
              (build-essential/gcc/g++/make/cmake/git/curl/rsync...), editors
              (vim/nano/tmux/htop/jq/fzf/ripgrep/bat/fd), net, ssh, python,
              node (NodeSource LTS + corepack), rust (rustup), go, docker
              (docker.io + compose, Docker-in-USB), cloud (gh + tailscale), ai
              (ollama). openssh-server is installed AND enabled with a sshd_config
              drop-in and host keys generated, so SSH is active on boot. Added
              _uca_with_chroot helper and _uca_validate_services (option 20->10):
              offline check (installed + enabled) via chroot plus runtime check
              (systemctl is-active over SSH to the booted VM). Build Essentials
              (option 7) already routes here by default per the USB-first policy.
Tests Passing: bash -n clean on menu.sh AND the embedded installer script.
              202 tests pass, 0 fail. Dry-runs verified side-effect-free; new
              menu items render without set-u crashes on the live drive.
Phase       : PHASE-7 (feature amendment)
Rollback Ref: Working copy; revert the _uca_install_tooling_usb /
              _uca_validate_services / _uca_with_chroot additions in menu.sh.
```

## CL-006 — Retuned Essentials + USB-Resident Profiles + Volume Rename/Relabel + Ventoy.json Doctor + Ventoy Reference

```
Date        : 2026-06-25 09:30 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-012, MOD-008, MOD-003, MOD-004
Section Tags: [SPECS-v1], [FS-008-v1], [FS-009-v1], [PHASE-7-v1]
Files Changed: menu.sh, blueprint/blueprint.md, blueprint/ventoy-reference.md
              (new), AGENTS.md, CHANGELOG.md
Description : Five tightly-coupled changes driven by the user's brainstorm and
              real-hardware feedback. (1) Retuned the comprehensive essentials
              installer (option 20->9) to a curated dev stack: default
              'recommended' = core(+unzip/zip/tar/cmake) editors net ssh
              python(+cryptography/pynacl/web3/eth-account) node(LTS+corepack)
              crypto(openssl/age/libsodium/gnupg/pass) web3(foundry/forge/
              cast/anvil + hardhat/ethers/viem/solc) docker(in-USB) cloud(gh/
              cloudflared/wrangler/tailscale). Opt-in only: rust, go, ai
              (ollama+hf-cli), extras (ruby/socat/nmap). No ollama by default
              per user preference. Foundry installs under /opt/foundry with
              /usr/local/bin symlinks so forge/cast/anvil/chisel are on every
              user's PATH; rustup similarly under /opt/rust. Caught and fixed
              a self-introduced bug in the resolver: the in-chroot variable
              was named GROUPS, which is a bash special array (user GIDs);
              renamed to SEL — selection actually works now. (2) Phase 1 of the
              multi-state vision: device/boot profiles are now stored on the
              USB itself at /<mount>/usb-hemlock/profiles/*.json (portable,
              travel with the drive), with a host fallback when the USB is
              not writable. Added 'Set default (autoboot) profile' to
              Device/Boot Profiles (option 15->7) and _uca_autoload_profile
              wired into main() before auto-detection — a USB profile marked
              "default": true now applies its device, ISO, and env block at
              every launch. Per user clarification, the manifest carries only
              storage-routing hints; agent/crew ROLE orchestration stays on
              the Hemlock side. (3) Persistence Manager gained Rename (option
              12->7) and Relabel (12->8). Rename cross-checks ventoy.json and
              warns if the file is referenced in the boot mapping. Relabel
              guards the casper-rw label (refuses to remove it without an
              explicit boot-risk acknowledgement) and runs fsck before
              writing. (4) Ventoy.json Doctor (option 12->9): read-only
              validator — JSON parse, known plugin keys, persistence-plugin
              schema, per-row image+backend existence on disk, control
              plugin dump, ISO inventory cross-check. Reports HEALTHY or a
              count of issues+warnings. Verified live: doctor reports
              HEALTHY on the user's real Ventoy drive (ubuntu-24.04.4 ISO +
              225G persistence). (5) New blueprint/ventoy-reference.md (282
              lines): curated localized reference for the Ventoy plugins
              this project drives or validates (persistence/control/menu_*/
              auto_install/injection/conf_replace/password/image_list/etc),
              with the project's specific recipes and a clear note that
              upstream docs win when in conflict.
Tests Passing: bash -n clean on menu.sh AND the embedded installer (caught
              the GROUPS bug). 202 tests pass, 0 fail. Live: profile saved
              to /media/drdeek/Ventoy/usb-hemlock/profiles/tooling.json,
              set-default verified, autoload verified on next launch.
              Doctor reports HEALTHY on the live drive. Rename dry-run
              correctly detects ventoy.json reference.
Phase       : PHASE-7 (feature amendment — Phase-1 of multi-state work)
Rollback Ref: Working copy; revert: _uca_autoload_profile / _uca_profile_dir /
              _uca_ventoy_doctor / persistence-mgr options 7/8/9 / installer
              retune (SEL/RECO want()).
```

## CL-007 — Phase 2: Modular Profile Manifest (primary + data volumes)

```
Date        : 2026-06-25 10:00 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-008, MOD-003, MOD-019
Section Tags: [SPECS-v1], [PROFILE-SCHEMA-v1], [PHASE-7-v1]
Files Changed: menu.sh, blueprint/blueprint.md, blueprint/profile-schema.md
              (new), AGENTS.md, CHANGELOG.md
Description : Phase 2 of the multi-state vision. The user's example was the
              driver: one always-on tooling.dat (rootfs) + hemlock.dat for
              the runtime/agent harness + models.dat for llama.cpp when
              running crew workloads. Implemented as a portable profile
              manifest (extension of CL-006's USB-resident profile) with four
              operations under option 15: Edit Manifest (8), Compile →
              ventoy.json (9), Apply Mounts to Primary (10), Preview (11).
              The schema is documented in blueprint/profile-schema.md
              (authoritative). Per the user's clarification, agent/crew
              ROLES stay on the Hemlock side; the manifest's data_volumes[]
              .role is a storage-routing hint only (driving systemd ordering
              for docker volumes, defaulting mountpoints in the wizard).
              Architectural correction baked into the design: Ventoy/casper
              mount exactly one persistence overlay as the rootfs, so the
              "3 overlays" intuition becomes "1 primary overlay + N data
              volumes mounted into it." A boot_mode field reserves room for
              non-Ventoy ISOs (e.g. macOS via QEMU): compile is a no-op for
              qemu mode and apply warns. Compile always backs up ventoy.json
              first via _uca_ventoy_json_backup; apply loop-mounts the
              primary, installs /usr/local/sbin/uca-mount-volumes.sh +
              /etc/systemd/system/uca-volumes.service (enabled via the
              multi-user.target.wants symlink because systemctl-in-chroot is
              unreliable), adds a docker.service drop-in
              (After=/Requires=uca-volumes.service) when a docker volume is
              present, and writes env vars to /etc/environment. The generated
              mount script finds the USB by LABEL=Ventoy (path-agnostic,
              retries 5x) and uses nofail so a missing data volume is skipped
              rather than blocking boot.
Tests Passing: bash -n clean on menu.sh AND on the rendered mount script.
              202 tests pass, 0 fail. Live (real /dev/sdb): built a real
              multi-volume manifest end-to-end through the menu, preview
              correctly flags [MISSING] volumes, dry-run compile + dry-run
              apply both side-effect-free (ventoy.json mtime unchanged,
              no loop-mount left behind).
Phase       : PHASE-7 (feature amendment — Phase 2 of multi-state work)
Rollback Ref: Working copy; revert: _uca_profile_validate / _uca_pick_profile /
              _uca_profile_edit_manifest / _uca_profile_compile_ventoy /
              _uca_render_mount_script / _uca_profile_apply_mounts /
              _uca_profile_preview, options 15→8/9/10/11.
```

## CL-008 — Hemlock Opt-In Flag + Environment Resolver + Dynamic Persistence Lookup

```
Date        : 2026-06-25 11:40 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-008, MOD-020, MOD-002, MOD-003
Section Tags: [SPECS-v1], [FS-001-v1], [SYS-OVERVIEW-v1]
Files Changed: menu.sh, blueprint/blueprint.md, AGENTS.md, README.md,
              CHANGELOG.md
Description : Three coordinated changes per user direction. (1) Hemlock is
              now OPT-IN: the menu no longer pre-lists Hemlock options. A
              new --hemlock / -H flag (or HEMLOCK_ENABLED=true env) reveals
              a single consolidated "Hemlock Manager" entry that subsumes
              the former options 8/9/10 (Hemlock TUI / Status / Master
              Deploy). Short flag is -H not -h to preserve the universal
              --help convention (parallels the existing sysman -N choice).
              The text and whiptail renderers both build their option list
              dynamically; renumbering compacted 21 -> 18 options by
              default, 19 with --hemlock. (2) Environment auto-detection
              added: _uca_detect_environment returns usb-boot |
              usb-mounted | native via /proc/cmdline + findmnt + loop-
              backing-file inspection + the existing _detect_usb_devices.
              _uca_resolve_environment persists the value to usb-paths.conf
              as UCA_ENVIRONMENT so subsequent launches don't re-prompt;
              prompt only fires on a TTY when detection is ambiguous AND
              no prior value exists. Shown in the new "Environment:" status
              header line alongside a [Hemlock enabled] badge when the
              flag is set. (3) Path-resolution audit eliminated all
              remaining hardcoded ubuntu-persistence.dat lookups in the
              Startup Manager and Persistence Manager (9 sites originally
              identified by the sweep). Added _uca_primary_persistence
              which prefers the active profile's primary.file, then the
              first volume from _uca_list_volumes, then the legacy default
              — so users with multiple volumes or non-standard names get
              the right one without code edits. The Create Persistence
              action also now PROMPTS for the filename instead of silently
              writing to ubuntu-persistence.dat (legacy default retained).
              Other audit results: zero /home/, /dev/sd[a-z], or port
              hardcodes; all /opt/ usage is intentional (foundry/rust);
              /tmp/ uses PID-suffixed scratch dirs; the two /var/lib/docker
              references are docker-default convention checks in jq
              filters. menu.sh now legitimately portable across machines.
Tests Passing: bash -n clean. 202 tests pass. Live (real /dev/sdb): default
              menu hides Hemlock with "options hidden" hint; --hemlock
              reveals option 19; environment auto-detects as "usb-mounted"
              and persists to usb-paths.conf; UCA_ENVIRONMENT="usb-mounted"
              written. Persistence Manager status shows the dynamically
              resolved primary (225G ubuntu-persistence.dat) without a
              hardcoded reference. Hemlock Manager submenu opens cleanly,
              Back returns; selecting option 19 WITHOUT the flag refuses
              with the correct hint message.
Phase       : PHASE-7 (interaction model amendment)
Rollback Ref: Working copy; revert: --hemlock arg, _uca_detect_environment,
              _uca_resolve_environment, _uca_primary_persistence, render
              and handler renumbering, _run_hemlock_manager.
```

## CL-009 — Hemlock Authoritative Blueprint + Survey of 6 Attempts

```
Date        : 2026-06-25 12:15 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-015, MOD-016, MOD-017, MOD-018, MOD-020, MOD-021
Section Tags: [SPECS-v1], [HEMLOCK-BLUEPRINT-v1]
Files Changed: blueprint/hemlock-blueprint.md (new), blueprint/blueprint.md,
              CHANGELOG.md
Description : Recorded the authoritative Hemlock spec and the cherry-pick
              survey. New file blueprint/hemlock-blueprint.md (~370 lines)
              is the single source of truth for the Hemlock subsystem,
              derived from /home/drdeek/Documents/hemlock/broke_scripts/
              BLUEPRINT.md (v1.0, May 2026) and amended per user direction
              for: one persistent runtime container with dynamic per-agent
              and per-crew Docker named volumes (managed via the in-
              container Docker socket + a bind-mount-into-runtime
              lifecycle described in §1.2); shared read-only hemlock_skills
              volume auto-refreshed daily by a host-side systemd timer;
              the EXACT 3-tier exporter user spec (MINIMAL/STANDARD/FULL —
              §5.3); bwrap-based agent process sandboxing (§1.3); explicit
              USB/Hemlock separation with Hemlock as opt-in. Per-agent-
              container model from the original is deprecated. CL-008's
              --hemlock opt-in flag is the entry point.
              Then surveyed all 6 hemlock attempt directories in /home/
              drdeek/Documents/hemlock/ to find the most complete
              implementation of each capability. Findings (full table in
              hemlock-blueprint.md §13): the current usb-hemlock-split is
              actually MORE evolved than broke_scripts for most scripts
              (agent-export 806L vs 775L, agent-create 642L vs 632L,
              helpers.sh 315L vs 260L). Only health/ truly needs to be
              restored from broke_scripts (== hemlock_integrated, same
              MD5, 14 .py, 214L doctor_bridge, 9 categories). Daily skills
              refresh and bwrap sandboxing must be built from scratch — no
              attempt has them. The 3-tier exporter is partly built but
              needs re-tuning to match the user's exact spec (move tools/
              and skills/ out of MINIMAL into STANDARD; add sessions-5-
              latest and memory-5-latest behavior). hemlock_snaps/ contains
              three planning docs (AUTONOMOUS_RUNTIME_BLUEPRINT.html v2.0
              phases 0-28, MASTER_CHECKLIST.md, BOOTSTRAP_PROGRESS_
              CHECKLIST.md) that historically informed the design — they're
              cited as reference only; this blueprint supersedes them.
              The H1-H7 implementation phase table in §12 now lists what's
              already there vs what to build, eliminating ambiguity in the
              next implementation pass.
Tests Passing: docs-only change; bash -n still clean; 202 tests still pass.
Phase       : PHASE-7 (specification amendment)
Rollback Ref: Working copy; revert: delete blueprint/hemlock-blueprint.md.
```

## CL-010 — H1: Restored Hemlock Doctor (health/) + Manager wiring

```
Date        : 2026-06-25 13:00 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-016 (Hemlock Runtime), MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: hemlock/hemlock-runtime/health/ (NEW, 18 .py files),
              menu.sh, blueprint/blueprint.md, blueprint/hemlock-blueprint.md,
              CHANGELOG.md
Description : Phase H1 complete per hemlock-blueprint.md §12. Restored the
              health/ directory from broke_scripts/health/ (byte-identical
              to hemlock_integrated/health/, MD5 8ff9c2ad…). 18 Python
              files total: doctor_bridge.py (214L, stdlib-only) + 8
              validator subpackages (paths, env, identity, gateway,
              imports, adapters, orchestration, persistence) each with
              its <category>_validator.py. Cleaned __pycache__ during
              copy. Added missing __init__.py to 4 subpackages (adapters/
              imports/orchestration/persistence) that the original was
              missing — without these Python wouldn't recognize them as
              importable packages and the dispatch in doctor_bridge.py
              would fail. All 18 files pass py_compile syntax check.
              Confirmed the doctor exits 1 on unhealthy (so the existing
              `docker compose` healthcheck which calls `python3 -m
              health.doctor_bridge --quick --json` correctly fails the
              container's health state — the JSON output is informational,
              the EXIT CODE is the healthcheck signal).
              Wired the Hemlock Manager's option-4 placeholder to a real
              _run_hemlock_doctor function: confirms the container is up,
              offers Quick / Full / Full+autofix / JSON modes, dispatches
              via `docker exec hemlock_runtime python3 -m
              health.doctor_bridge ...`, honors DRY_RUN by printing the
              exact command without executing.
              Important discovery: the Docker image built earlier from
              broke_scripts/ already had health/ baked into /opt/hermes/
              health/ inside the container — that's why `hemlock_runtime`
              has been "Up 11 hours (healthy)" the whole time even with
              the host-side directory missing. The restore makes future
              rebuilds use the SAME doctor (same MD5) and unlocks host-
              side testing of the validator modules.
              Verified live against the actually-running container: Quick
              check returns 44 ok / 5 warn / 0 fail in 776ms; Full check
              returns 78 total with 1 fail / 15 warn / 62 ok (worth
              investigating which check is failing, but the framework
              itself works perfectly).
Tests Passing: bash -n clean. 202 USB tests still pass. All 18 doctor
              Python files pass py_compile. End-to-end: Hemlock Manager →
              Doctor → Quick check ran against the live container and
              returned structured human + JSON output.
Phase       : H1 — Doctor + Health System
Rollback Ref: Working copy; revert: rm -rf hemlock/hemlock-runtime/health/
              and undo the _run_hemlock_doctor addition in menu.sh.
```

## CL-011 — H4: 3-Tier Exporter Re-tuned + Validate/Destroy + Latent Bugs Fixed

```
Date        : 2026-06-25 13:30 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-016 (Hemlock Runtime), MOD-017 (Staging Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: hemlock/hemlock-runtime/scripts/agent-export.sh,
              blueprint/blueprint.md, blueprint/hemlock-blueprint.md,
              CHANGELOG.md
Description : Phase H4 per hemlock-blueprint.md §5.3 & §5.4. Re-tuned the
              3 export tiers to MATCH THE USER'S EXACT SPEC, added the
              validate-then-destroy flow, and fixed two latent bugs
              discovered while testing.
              TIER RE-TUNE:
                MINIMAL was including tools/, tools.md, skills/ — per
                user's spec, those belong in STANDARD only. MINIMAL is now
                exactly: agent.json, SOUL.md, IDENTITY.md, TOOLS.md,
                AGENTS.md (+ legacy tools.md harmless if absent).
                STANDARD was missing a memory/ 5-most-recent treatment;
                added (matches the existing sessions/ pattern). Now
                includes: MINIMAL + MEMORY.md + .secrets/ + HEARTBEAT.md
                + tools/ + skills/ + sessions/(5 latest) + memory/(5
                latest) + USER.md + cron/ + projects/ + .env + config.yaml.
                FULL unchanged — entire volume, every file, hidden incl.
              VALIDATE-THEN-DESTROY FLOW (§5.4):
                Added per-file SHA-256 checksum manifest (checksums.sha256,
                consumable by `sha256sum -c`). New flags:
                  --validate : round-trip the export, verify EVERY file's
                               checksum + the file count, set VALIDATED=true
                               only on a clean pass.
                  --destroy  : after a passing validation, delegate to
                               agent-delete.sh to remove the source agent
                               volume. Implies --validate. NEVER fires
                               unless validation passed. Interactive
                               confirmation unless --force.
                Validates both directory exports and --tarball exports
                (extracts to scratch, validates, cleans up).
              LATENT BUG #1 (silently broken STANDARD):
                copy_recent_files() was CALLED for sessions/ but NEVER
                DEFINED. Under set -euo pipefail this crashed the script
                the moment STANDARD hit the sessions/ block. Defined the
                function (NUL-safe find/sort/head/cp pipeline to handle
                whitespace in filenames). Now copies the N most recent
                files by mtime cleanly.
              LATENT BUG #2 (silently broken any export with missing
              optional file):
                copy_file_if_exists and copy_dir_if_exists returned 1 when
                the source didn't exist, which under set -e aborted the
                script. The test agent (no legacy tools.md) triggered this:
                STANDARD got as far as the first copy_file_if_exists for a
                file that didn't exist, then silently exited 0 (the abort
                was suppressed by the way the outer caller worked). Fix:
                both helpers now ALWAYS return 0 — "source not present" is
                a no-op, not an error.
              LIVE VERIFICATION (real hemlock_runtime container):
                Created test agent /data/agents/exporttest with all
                workspace files + 7 session files + 7 memory files.
                MINIMAL  → exactly 5 payload files (no tools/, no skills/).
                STANDARD → all expected dirs + sessions/m3..s7 (5 latest)
                          + memory/m3..m7 (5 latest) + .secrets/ + tools/
                          + skills/ + projects/ + manifests + 19 checksums
                          → Validation PASSED.
                FULL + --validate --destroy → 19 files validated, then
                          agent-delete.sh successfully removed
                          /data/agents/exporttest. Container ls confirmed
                          the agent was destroyed.
                Tamper test: modifying agent.json after export → sha256sum
                          -c reports FAILED → validate_export would set
                          VALIDATED=false → --destroy would correctly REFUSE.
Tests Passing: bash -n clean. 202 USB tests still pass. End-to-end live
              tests pass on the running hemlock_runtime container.
Phase       : H4 — 3-Tier Exporter (per hemlock-blueprint §5.3 + §5.4)
Rollback Ref: Working copy; revert: agent-export.sh edits (re-add
              tools/skills to MINIMAL_FILES, remove --validate/--destroy
              flags + write_checksums/validate_export/validate_tarball
              functions). Revert helpers to return 1 on missing source.
```

## CL-012 — GUI Direction: OpenClaw Control Web UI + Future Rebrand

```
Date        : 2026-06-25 16:30 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-015 (Hemlock Host CLI), MOD-016 (Hemlock Runtime TUI)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: blueprint/blueprint.md, blueprint/hemlock-blueprint.md,
              CHANGELOG.md
Description : Decision recorded. The Hemlock GUI direction is the
              OpenClaw Control web UI that the gateway already serves at
              http://localhost:18789/ from inside hemlock_runtime —
              NOT a separate Electron app (Hermes Desktop was the wrong
              layer for our architecture, which is User → OpenClaw → MCP
              → Hermes; Hermes Desktop bypasses OpenClaw and talks
              directly to a `hermes dashboard` server that our container
              doesn't expose). OpenClaw Control is a full Vite SPA with
              /agents, /crews, /channels, /metrics routes, theming
              (claw/knot/dash + light/dark/system), i18n, and per-route
              auth. Native-app feel achieved via `chromium --app=URL
              --class=Hemlock-Control` — zero Electron, zero packaging.
              The UI source lives in docker/openclaw-runtime/ inside the
              hemlock image, so it's already portable on the USB.
              Auth: gateway requires OPENCLAW_GATEWAY_TOKEN; obtained
              via `openclaw dashboard` (prints a tokenized URL of the
              form http://127.0.0.1:18789/#token=<hex>). Token persists
              across container restarts. H7 (bootstrap helpers) will
              pre-fill this in the menu so users don't hit the auth wall
              manually. Live-verified: the dashboard URL with token
              loads the UI successfully (user confirmed access; UI
              prompts an OpenClaw update — out-of-date — to address
              separately when we rebuild the container image with
              current OpenClaw).
              Rebrand (deferred): the OpenClaw Control SPA can be forked
              and rebuilt with Hemlock branding (title, favicons, theme
              names "claw"→"hemlock", i18n strings, app logo). Surface
              is small. Plan: commit the rebrand to the docker/openclaw-
              runtime build context so `docker compose build` produces a
              Hemlock-branded UI. Optionally add Hemlock-specific views
              (volume management, profile switcher, USB device info).
              Defer until: (a) we update OpenClaw itself to current,
              (b) volume orchestrator (H2) ships so the UI has the
              backend data to display, (c) we have a quiet session to
              do the npm build cleanly.
              Dropped: Hermes Desktop fork (wrong layer); Path 3 from
              CL-009's brainstorm.
Tests Passing: docs-only; bash -n still clean; 202 USB tests still pass.
Phase       : Hemlock GUI — architecture locked
Rollback Ref: docs-only; no code changes.
```

## CL-013 — H7: Gateway Token Bootstrap + Hemlock Control GUI Launcher

```
Date        : 2026-06-25 17:00 UTC
Contributor : Claude (Opus 4.8)
Modules     : MOD-015 (Hemlock Host CLI), MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: menu.sh, blueprint/blueprint.md, CHANGELOG.md
Description : Phase H7 complete. Closes the gateway-token friction
              identified in CL-012. Two new helpers:
              - _uca_hemlock_token() resolves the OPENCLAW_GATEWAY_TOKEN
                from the live container env, falling back to parsing the
                URL fragment from `openclaw dashboard`. NOT cached on
                disk — regeneration is fast (~1s) and avoids storing a
                secret in usb-paths.conf (which is sourced as bash).
                Returns 1 cleanly if the container is down.
              - _run_hemlock_control() is the GUI launcher wired into
                Hemlock Manager option 19 → 5. Auto-starts the container
                if stopped (with confirmation + healthcheck wait, up to
                30s). Auto-fills the token into the URL fragment so the
                user never sees the auth wall. Prefers chromium/chrome
                in --app mode for a native-app feel; falls back to
                xdg-open if no chromium-family browser is installed.
                Honors DRY_RUN.
              Hemlock Manager renumbered: 5=Launch Hemlock Control (new),
              6=Volume management (placeholder, was 5).
              The GUI work referenced in CL-012 is now end-to-end —
              user runs option 19→5 from menu.sh and gets a chromeless
              window onto OpenClaw Control, no manual token paste, no
              Electron, no install.
Tests Passing: bash -n clean. 202 USB tests still pass. Dry-run verified
              for the container-down path (correctly offers to start).
              Live launch deferred (user's machine was resource-tight
              earlier this session; H7 wiring is testable without doing
              another full launch).
Phase       : H7 — Bootstrap helpers
Rollback Ref: Working copy; revert: remove _uca_hemlock_token,
              _run_hemlock_control, the case-5 dispatch change in
              _run_hemlock_manager.
```

## CL-014 — H2: Crew Volume CRUD + Volume Management Submenu + llmrl

```
Date        : 2026-06-26 06:15 UTC
Contributor : Claude (Opus 4.7)
Modules     : MOD-015 (Hemlock Host CLI), MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: hemlock/hemlock-runtime/scripts/crew-create.sh,
              hemlock/hemlock-runtime/scripts/crew-import.sh,
              hemlock/hemlock-runtime/scripts/crew-dissolve.sh,
              menu.sh, usb/scripts/setup-llmrl.sh (new),
              usb/scripts/setup-essentials-enhanced.sh,
              CHANGELOG.md, blueprint/blueprint.md, AGENTS.md
Description : Two converging changes that close the H2 gap and
              expand the USB tooling envelope.

              (1) Crew docker volume CRUD — agents already had per-agent
              `hemlock_agent_<id>` volumes labelled `framework=hemlock`;
              crews had nothing. crew-create.sh now provisions
              `hemlock_crew_<name>` with labels {crew, crew_id,
              framework=hemlock} immediately after writing SOUL.md.
              crew-import.sh mirrors it with origin=imported so source
              of provenance is visible at `docker volume inspect` time.
              crew-dissolve.sh removes the volume after the existing
              archival step — gracefully degrades if the volume is in
              use (printing the hint to stop first). All three branches
              skip cleanly if `docker` isn't on PATH, matching the
              existing pattern in agent-create.sh:289-291.

              (2) Hemlock Manager option 6 was a placeholder. Now wired
              to `_run_hemlock_volumes`, a single-screen submenu that:
                - lists every docker volume labelled framework=hemlock
                  (agent/crew/skills/other), numbered for easy selection
                - inspect (i N): docker volume inspect + on-disk size
                  via `du -sh /v` inside throwaway alpine:3
                - backup (b N): streams contents to
                  ./hemlock-backups/<name>-<ts>.tgz through alpine —
                  honors DRY_RUN
                - destroy (d N [--force]): confirms, then
                  `docker volume rm`; warns + hints --force when the
                  volume is in use
              Pure docker — no host binds, no Docker socket inside the
              container — fully aligned with CL-012's restart-on-CRUD
              ruling.

              (3) llmrl CLI vendored at usb/scripts/setup-llmrl.sh —
              user-supplied Node-based HuggingFace model
              browser/downloader/registry. Self-extracting installer
              (`bash setup-llmrl.sh` from any directory produces
              ./llmrl, npm-links the `llmrl` bin, defaults model store
              to $MODEL_DIR or $HOME/llm-models). Two install paths:
                - In-persistence (chroot via menu option 7 → USB target
                  → install_tooling): new `llmrl` opt-in group; the
                  menu copies the bootstrapper into $mnt/tmp before
                  chroot so the group can find it. Skips with a clear
                  message if npm or the bootstrapper is missing.
                - Host install: install_llmrl() added to
                  setup-essentials-enhanced.sh, exposed in the LLM
                  engines questionnaire alongside llama.cpp/ollama.
              Snap survey (under .config/opencode/hemlock_snaps):
              checked every snapshot for plug-and-play crew docker
              volume code — zero hits. `openclaw-hermes-docker.skill`
              describes the OLD bind-mount pattern (~/.openclaw/agents
              bound into containers), which CL-012 ruled out. The
              `autonomous-crew.skill` is a placeholder. So H2's crew
              parity is genuinely write-from-scratch, mirroring the
              existing agent-create.sh pattern verbatim. Recorded the
              survey result instead of re-running it next session.
Tests Passing: bash -n clean on menu.sh + 3 crew scripts +
              setup-llmrl.sh + setup-essentials-enhanced.sh. Regression
              suite: 203/203 PASS (was 202; new pass = setup-llmrl.sh
              syntax check). Smoke test of option 19 → 6 with
              --hemlock --dry-run successfully listed 17 live
              hemlock_agent_* volumes from the actual docker engine.
Phase       : H2 — Volume orchestrator
Rollback Ref: Working copy; revert: remove the docker volume blocks
              from the 3 crew-*.sh files, revert menu.sh option 6 to
              the _menu_info placeholder, delete _run_hemlock_volumes
              + _uca_hemlock_volume_* helpers, delete
              usb/scripts/setup-llmrl.sh, remove install_llmrl from
              setup-essentials-enhanced.sh and the llmrl group from
              the in-persistence installer.
```

## CL-015 — Sudo Cache Consent, Auto-Update, Antivirus Remediation, llmrl Auto-Triggers

```
Date        : 2026-06-26 06:55 UTC
Contributor : Claude (Opus 4.7)
Modules     : MOD-002 (Setup CLI), MOD-008 (Config), MOD-015 (Hemlock Host CLI),
              MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: menu.sh, usb/scripts/setup-essentials-enhanced.sh,
              usb/scripts/install-antivirus.sh,
              hemlock/hemlock-runtime/.auto-update.sh (new, ported from hemlock.02),
              hemlock/hemlock-runtime/.auto-update.sh.sha256 (new),
              CHANGELOG.md, blueprint/blueprint.md
Description : Six converging changes that close the user-flagged gaps in
              setup ergonomics, automated remediation, and self-maintenance.

              (1) Triple-notification sudo consent flow + session cache.
              New `_uca_sudo_consent_flow` walks the operator through three
              consecutive confirmations explaining the three storage modes:
                A) ENCRYPTED-AT-REST via libsecret (gnome-keyring/kwallet);
                   script types the password in via `sudo -S`, never
                   displays it. Falls back to session cache if secret-tool
                   is missing.
                B) SESSION CACHE — `sudo -v` + 60s keepalive for THIS menu
                   run; `sudo -k` on EXIT/INT/TERM trap. Default.
                C) NO CACHE — legacy; OS prompts each elevation.
              Choice persists in `~/.config/usb-compute-automation/sudo-policy`
              (chmod 600). Autoboot active → consent flow short-circuits
              (services are already running headless).

              (2) Permission normalization at menu startup. New
              `_uca_normalize_permissions` chowns `~/.config/usb-compute-
              automation/` back to $USER, sets dirs 755, regular files 644,
              secret files (sudo-policy, usb-paths.conf, usb-env.conf) 600.
              Goal: after initial setup, NO interactive menu action needs
              sudo. Runs unconditionally on every `main()`.

              (3) `_uca_sudo_init` injected at the top of every elevated
              action: _run_essentials, _run_automount, _run_antivirus_install,
              _run_deploy. Single-line addition that triggers the consent
              flow once, then primes the cache per policy.

              (4) install-antivirus.sh upgraded from scan-only to true
              remediation. Added:
                - QUARANTINE_DIR (`/var/quarantine/system_toolkit`, chmod 700)
                - `scan`/`fullscan` now use `--move=$QUARANTINE_DIR` and
                  count quarantined hits
                - `scan-only` retained for legacy report-only mode
                - `rootkit` auto-runs `rkhunter --propupd` on clean runs;
                  warns + suggests `virus remediate` on warnings
                - new `remediate` action: freshclam --quiet, restart
                  clamav-{freshclam,daemon}, rkhunter --propupd + --update
                - new `quarantine list|restore|purge` with NUL-safe ops
              Wired into Diagnostics (option 14) via new
              `_run_antivirus_install` + `_run_antivirus_action` submenus —
              the toolkit had no menu surface before this change.

              (5) Hemlock self-update ported from hemlock.02 snapshot. The
              812L `.auto-update.sh` provides HTTPS-only signature-verified
              updates with 5-version rollback, stale-lock detection, and
              self-healing from backup. Adaptations for the current
              project:
                - RUNTIME_ROOT anchor swapped runtime.sh → lib/common.sh
                  (matches current Hemlock layout)
                - AUTO_UPDATE_URL defaults to UNSET (no silent network
                  calls to placeholder URLs); operator configures via
                  the new menu wizard or env vars
                - new auto_update guard refuses to run if URL is empty
              Menu wiring: Hemlock Manager option 19 → 7 = "Check for
              updates" calls _run_hemlock_update, which prompts for URL
              on first use, persists it in `.auto-update.env` (chmod 600),
              and exposes check / force / rollback-list / rollback /
              show-config sub-actions. DRY_RUN respected throughout.

              (6) llmrl auto-install trigger pair. Per user direction, the
              llmrl bootstrapper is auto-installed on TWO opt-in events:
                a) `install_llama_cpp()` success path —
                   setup-essentials-enhanced.sh now calls install_llmrl()
                   immediately after llama.cpp passes its post-install
                   check. The pairing reflects natural use (browse/download
                   GGUFs → run with llama.cpp).
                b) `_run_bash_profile` option 1 (Install enhanced bash
                   profile) — the new `_uca_auto_install_llmrl_after_profile`
                   helper prompts to install llmrl, falling back to staging
                   the bootstrapper on the USB (`<mount>/tools/setup-llmrl.sh`)
                   for later manual run.
              If neither trigger fires, the bootstrapper still ships in
              `usb/scripts/setup-llmrl.sh` for manual install.

              (7) Org cleanups (trivial only). Removed two backup files:
                - hemlock-runtime/scripts/agent-export.sh.bak
                - hemlock-runtime/docker/hermes-agent/hermes_cli/
                  runtime_provider.py.orig
              USB-side audit: 8 scripts, all referenced (avg 11+ refs each),
              no orphans, no empty dirs. Hemlock-side: 72 scripts, the only
              true zero-ref script is fix-lfs-push.sh (Replit-specific with
              a hardcoded personal GitHub URL — flagged but not removed
              without user confirmation).

Tests Passing: bash -n clean on menu.sh, install-antivirus.sh, .auto-update.sh,
              setup-essentials-enhanced.sh. Regression suite 203/203 PASS
              (no change from CL-014 baseline). Docker image rebuild
              (Dockerfile.runtime via docker-compose.runtime.yml) queued —
              status logged in CHANGELOG after build completion.
Phase       : Setup ergonomics + self-maintenance
Rollback Ref: Working copy. Revert by:
              - removing _uca_sudo_* and _uca_normalize_permissions blocks
                from menu.sh (plus the four call sites)
              - reverting setup-essentials-enhanced.sh install_llama_cpp
                tail to drop install_llmrl call
              - reverting install-antivirus.sh to the scan-only behaviour
                (drop quarantine/remediate/scan-only branches + the
                Diagnostics _run_antivirus_* submenus)
              - removing hemlock/hemlock-runtime/.auto-update.sh* and
                _run_hemlock_update + the option 7 dispatch in
                _run_hemlock_manager
              - removing _uca_auto_install_llmrl_after_profile + the call
                site in _run_bash_profile option 1
              The two deleted .bak/.orig files are recoverable from any
              prior git commit or the broke_scripts snapshot.
```

## CL-016 — Skills Repo: drdeeks/skills Baked Into Image + Daily In-Container Pull

```
Date        : 2026-06-26 07:22 UTC
Contributor : Claude (Opus 4.7)
Modules     : MOD-015 (Hemlock Host CLI), MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: hemlock/hemlock-runtime/Dockerfile.runtime,
              hemlock/hemlock-runtime/docker/entrypoint.sh,
              hemlock/hemlock-runtime/docker-compose.runtime.yml,
              menu.sh, CHANGELOG.md, blueprint/blueprint.md
              + REMOVED: hemlock/hemlock-runtime/skills/ (entire 131-skill
                vendored tree), hemlock/hemlock-runtime/scripts/skills-sync.sh,
                hemlock/hemlock-runtime/systemd/ (host timer artifacts)
Description : Replaces the vendored 131-skill local tree with a fresh
              clone of github.com/drdeeks/skills (157 entries, ~38M),
              baked INTO the runtime image at build time.

              Architecture (per user direction "no bind mount it should
              be hosted on persistent within the container regardless"):

              1) Dockerfile.runtime:
                 - apt installs git/cron/rsync alongside the existing
                   procps/bash/unzip/ffmpeg layer
                 - `ARG SKILLS_REPO=https://github.com/drdeeks/skills.git`
                 - `ARG SKILLS_BRANCH=main`
                 - `RUN git clone --depth 1 --branch $SKILLS_BRANCH
                   $SKILLS_REPO /opt/skills_seed` at build time
                 - `/etc/cron.d/hemlock-skills-sync` schedules
                   `17 3 * * * root cd /skills && git pull --ff-only`
                   (odd minute to avoid herd polling github.com)

              2) docker/entrypoint.sh:
                 - On first container start, if /skills lacks
                   `.hemlock_skills_seeded`, rsync /opt/skills_seed/ →
                   /skills/ with --delete, then drop the marker file
                 - Start cron daemon so the daily pull fires
                 - Both gated behind `command -v cron` so other modes
                   (HERMES_ONLY) don't break

              3) docker-compose.runtime.yml:
                 - Reverted from bind mount `./skills:/skills:ro` to the
                   original named volume `skills_data:/skills` (writable
                   for git pull inside the container)
                 - The named volume is docker-managed, persists across
                   restarts, no host filesystem coupling

              4) menu.sh (Hemlock Manager option 19 → 8):
                 - Wraps `docker exec hemlock_runtime` for every action;
                   no host script needed
                 - Status header: skill count, HEAD commit, cron state
                 - Sub-actions: pull-now, force-pull (git reset --hard),
                   show log, list entries, re-seed from /opt/skills_seed
                   (destructive, requires confirmation)
                 - DRY_RUN honored throughout

              Trade-offs accepted:
                - Image grows by ~38M (skills clone) — acceptable
                - Updates require either daily cron OR a manual pull
                  (option 19 → 8); no rebuild needed for upstream changes
                - First start does the rsync once (~3s on a modern
                  machine); subsequent starts skip via marker file
                - If the user wants a different skills source, override
                  via `--build-arg SKILLS_REPO=<url>` at build time

              Removed legacy:
                - hemlock-runtime/skills/ (131 vendored skills) —
                  archived at /tmp scratchpad before deletion
                - hemlock-runtime/scripts/skills-sync.sh (host-side
                  wrapper, redundant now that cron lives in container)
                - hemlock-runtime/systemd/ (host user-timer that
                  preceded the in-container cron decision)

Tests Passing: bash -n clean on menu.sh, entrypoint.sh. Regression suite
              203/203 PASS. Dry-run of menu option 19 → 8 sub-paths
              works (refuses gracefully when container is down).
              Image rebuild required to validate the Dockerfile changes
              live — user denied the prior build attempt; queued.
Phase       : H3 — Skills volume + daily refresh (revised, in-container)
Rollback Ref: Working copy. Revert by:
              - Restoring skills/ tree from /tmp scratchpad archive
              - Reverting docker-compose.runtime.yml skills_data block
                + the volumes section comment
              - Removing the new Dockerfile.runtime blocks (git/cron/
                rsync apt install, skills_seed clone, cron.d file)
              - Reverting entrypoint.sh skills-seed + cron-start block
              - Removing _run_hemlock_skills_sync + option 8 wiring in
                _run_hemlock_manager
```

## CL-017 — Battle-Harden Pass: Deep Validation + 5 Real Bugs Fixed + Live Agent Loop

```
Date        : 2026-06-26 18:10 UTC
Contributor : Claude (Opus 4.7)
Modules     : MOD-015 (Hemlock Host CLI), MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: hemlock/hemlock-runtime/scripts/agent-create.sh,
              hemlock/hemlock-runtime/scripts/agent-export.sh,
              hemlock/hemlock-runtime/scripts/agent-import.sh,
              hemlock/hemlock-runtime/scripts/crew-create.sh,
              hemlock/hemlock-runtime/scripts/crew-dissolve.sh,
              hemlock/hemlock-runtime/scripts/helpers.sh,
              CHANGELOG.md, blueprint/blueprint.md
              + NEW (scratchpad, not committed):
                /tmp/.../scratchpad/deep-validation.sh
                /tmp/.../scratchpad/usb-validation.sh
                /tmp/.../scratchpad/smoke-test.sh
Description : Triggered by user calling out CL-015's "smoke test" as
              surface-level peasant work. Built a real behaviour suite
              that creates agents, exports them in all 3 tiers, imports
              them back, creates crews, dissolves crews, restarts the
              container, git-pulls inside /skills, and proves every
              menu submenu renders against the live USB.

              First run exposed 23 failures. Most were my test using
              wrong CLI flags (had to read each script's actual
              --help). Two were architectural confusion (CL-012
              isolation means in-container scripts skip docker vol
              creation). Five were genuine bugs:

              (1) read_tty() / read_tty_rs() in agent-create/export/
              import didn't honor HEMLOCK_NONINTERACTIVE=1. The
              fall-through condition (`-c /dev/tty && -w /dev/tty`)
              succeeds in docker-exec context because /dev/tty exists
              as a character device, but `read ... < /dev/tty` then
              fails because it's not the caller's controlling tty.
              Result: scripts that accept --id/--name/--model flags
              still hung or errored when run headless. Fix: top-of-
              helper short-circuit on HEMLOCK_NONINTERACTIVE=1 OR
              SKIP_PROMPTS=true OR NONINTERACTIVE=true OR
              SHIFT_PROMPTS=true (each script honors its own
              local-convention env var name plus the universal one).
              Also added `tty -s </dev/tty 2>/dev/null` to the
              fall-through condition to verify it's a real TTY.

              (2) crew-create.sh:119 — `check_docker` was a fatal
              exit. Per CL-012, docker is OPTIONAL from a caller (the
              container itself doesn't have the socket; the host
              menu does). My CL-014 volume-create code at line 181
              correctly gates on `command -v docker`, but never ran
              because check_docker bailed first. Downgraded to a
              warning log line.

              (3) crew-dissolve.sh interactive prompt: hard `read -rp`
              prompt blocked headless runs even with --force not yet
              passed. Added HEMLOCK_NONINTERACTIVE=1 bypass + an
              explicit `[ -t 0 ]` check that bails safely if no TTY
              and no --force (vs. hanging on /dev/tty).

              (4) crew-dissolve.sh:124-135 — awk read $DOCKER_COMPOSE_
              FILE without checking it exists. helpers.sh sets it to
              "$RUNTIME_ROOT/docker-compose.yml" which doesn't exist
              inside the container. Result: dissolve always exited 2.
              Fixed with `[[ -f "$DOCKER_COMPOSE_FILE" ]]` gate.

              (5) helpers.sh:is_service_running() — `docker ps | grep
              ...` with no `command -v docker` guard. Same as (2);
              fixed the same way.

              After all 5 fixes + hot-patch into the running container
              via `docker cp`, deep validation v7 reports 44 PASS /
              0 FAIL / 9 SKIP. The 9 skips are honest acknowledged
              limits (API keys needed, USB chroot needs sudo, etc.) —
              three of the original 10 (gateway, MCP brain, agent
              loop) subsequently collapsed to PASS via the live
              OpenRouter validation below.

              USB validation suite (scratchpad/usb-validation.sh):
              14 PASS / 0 FAIL / 1 SKIP (chroot pending sudo). Live
              USB detection at /dev/sdc, Ventoy mount at
              /media/drdeek/Ventoy, 20G ubuntu-persistence.dat
              recognized. Status header renders USB device + mount +
              persistence size from live filesystem. Persistence
              Manager / USB Access & Boot / Paths submenus all reach
              the right resources. Sudo-policy first-run flow tested
              with no-tty + no-policy-file — confirmed no-hang.

              Live agent loop (X.1/X.2/X.3 unblocked): user supplied
              an OpenRouter API key for one-time validation. A real
              call through `python3 -m hermes_cli.main chat -q '...'
              --provider openrouter --model cohere/north-mini-code:free`
              returned the timestamped marker
              `HEMLOCK_BATTLE_HARDEN_OK_<ts>` verbatim. Proves the
              full chain: OPENROUTER_API_KEY → Hermes brain MCP
              (28 tools registered, 1 MCP server active) → tool-
              calling loop → provider routing → response delivery →
              session persistence (resumable session ID). User
              warned to rotate the key (chat-log exposure).

Tests Passing: bash -n clean on all 6 patched files. Deep validation
              v7: 44/0/9. USB validation v1: 14/0/1. Live agent loop:
              1/0/0. Combined: 59/0/10. Hot-patches in running
              container; source has them; next image build will bake
              them in (queued as CL-018 prep).
Phase       : Battle-harden
Rollback Ref: Working copy. Revert by:
              - Reverting the read_tty / read_tty_rs short-circuit in
                agent-create.sh, agent-export.sh, agent-import.sh
              - Restoring fatal `exit 1` in crew-create.sh:119 (NOT
                recommended — CL-014 then never runs)
              - Removing HEMLOCK_NONINTERACTIVE bypass + TTY guard in
                crew-dissolve.sh confirmation block
              - Removing `[[ -f "$DOCKER_COMPOSE_FILE" ]]` gate in
                crew-dissolve.sh:124
              - Reverting `command -v docker` guard in helpers.sh:
                is_service_running
              Scratchpad validation scripts are not committed; they
              live at /tmp/.../scratchpad/{deep,usb}-validation.sh
              for the duration of this session.
```

## CL-018 — Lean Per-Agent Workspace + `<agent_id>.json` Isolation

```
Date        : 2026-06-26 20:10 UTC
Contributor : Claude (Opus 4.7)
Modules     : MOD-015 (Hemlock Host CLI), MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: hemlock/hemlock-runtime/scripts/agent-create.sh,
              hemlock/hemlock-runtime/scripts/agent-export.sh,
              hemlock/hemlock-runtime/scripts/agent-import.sh,
              hemlock/hemlock-runtime/scripts/helpers.sh,
              hemlock/hemlock-runtime/agents/workspace-template/ (pruned),
              hemlock/hemlock-runtime/agents/workspace-template/tools/enforce.sh,
              blueprint/blueprint.md, CHANGELOG.md
Description : Tightened per-agent workspace to match the user's stated
              ideal. Triggered by user feedback that agents had "too many
              directories established by default" + identity files needed
              per-agent isolation.

              IDEAL layout (per user spec):
                Files: SOUL.md TOOLS.md USER.md IDENTITY.md MEMORY.md
                       HEARTBEAT.md (preferred) .env (conditional)
                       <agent_id>.json
                Dirs:  skills/ sessions/ memory/ tools/ projects/
                       .secrets/ .archive/ logs/ knowledge/ avatar/
                       (config.yaml retained — Hermes REQUIRES it for
                       delegation/memory/auxiliary/context/skill config;
                       21 source files in /opt/hermes/ load it)

              REMOVED from defaults: agent.json (renamed),
              AGENTS.md (IDENTITY.md owns identity role), bin/,
              media/{images,files}, platforms/, sandboxes/{singularity},
              .backups/ (.archive/ supersedes).

              CRITICAL change: identity file renamed agent.json →
              ${AGENT_ID}.json so per-agent isolation is enforced at the
              filesystem level. No two agent workspaces on the same
              filesystem will ever have a name collision on their
              identity manifest. Matches the user's "long-term registrar
              agent will register each on-chain" forward plan.

              Backward compat: agent-import.sh accepts BOTH legacy
              agent.json AND <id>.json in incoming bundles. The
              migration block at line ~327 promotes whichever it finds
              to the new ${TARGET}.json filename and removes stale
              duplicates. helpers.sh:agent_exists() accepts both.

              enforce.sh REQUIRED_DIRS list updated (line 67): removed
              media/{images/agents,images/misc,files}; added knowledge,
              avatar. cache/ migration (line 76) routes to
              .archive/cache-<ts>/ instead of recreating media/.

              agent-create.sh changes:
                - Line 153: cat > ${AGENT_ID}.json (was agent.json)
                - Line 465: sed updates ${AGENT_ID}.json (was agent.json)
                - Lines 377-462: config.yaml writers retained AS-IS
                  because Hermes loads them; .env is written alongside
                  for secrets (AGENT_API_KEY, AGENT_MODEL, etc.)
                - The 8 helper tools in tools/ (secret.sh, enforce.sh,
                  memory-promote.sh, memory-log.sh, inject-context.sh,
                  jsonfmt.py, auth-login.sh, TOOLS-GUIDE.md) DEFERRED:
                  user has spec for auto-populate-on-create AND
                  auto-populate-if-missing-on-import; will apply once
                  spec arrives.

              agent-export.sh MINIMAL tier (line 92):
                Was: agent.json SOUL.md IDENTITY.md TOOLS.md AGENTS.md
                Now: ${AGENT_ID}.json (with agent.json fallback),
                     SOUL.md IDENTITY.md TOOLS.md
                AGENTS.md removed from MINIMAL (was per-agent; IDENTITY.md
                replaces its role).

              Test result after hot-patch + validation script update:
                46 PASS / 0 FAIL / 9 SKIP (was 44/0/9 before — added
                two new contract assertions: tom.json present + lean
                check that media/bin/agent.json/AGENTS.md are absent).

              Deferred (parking lot, queued as new tasks):
                - tools/ helper script auto-populate spec
                - Runtime state files (state.db, channel_directory.json,
                  gateway_state.json) auto-populate decision
                - Crew dir simplification (waiting on PM workflow spec)
                - Project Manager crew lead + triple-confirmation
                  blueprint workflow (major new feature)
                - Registrar agent for on-chain agent registry with
                  X402 wallets, A2A comm, profile pictures

Tests Passing: bash -n clean on 4 patched scripts + enforce.sh. Deep
              validation v8: 46/0/9. Live tom agent created with full
              lean layout verified visually + by contract assertions.
Phase       : CL-018 — Workspace lean
Rollback Ref: Working copy. Revert by:
              - Restoring workspace-template/{agent.json, AGENTS.md,
                bin/, media/} from previous bundle's tarball
              - Reverting agent-create.sh:153 + 465 to "agent.json"
              - Reverting agent-export.sh:92 MINIMAL_FILES
              - Reverting agent-import.sh:67 + 326 + 391
              - Reverting helpers.sh:agent_exists
              - Reverting enforce.sh:67 + 76
              The CL-018 image rebuild has NOT yet happened (next CL
              should bake these patches into hemlock:latest).
```

## CL-019 — Crew PM Blueprint Workflow

```
Date        : 2026-06-26 23:00 UTC
Contributor : Claude (Opus 4.7)
Modules     : MOD-015 (Hemlock Host CLI), MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: hemlock/hemlock-runtime/scripts/crew-pm-blueprint.sh (new),
              menu.sh (new option 19 → 9), blueprint/blueprint.md, CHANGELOG.md
Description : Implements the user's stated PM workflow: crew creation gated
              behind a Project Manager interrogation that produces a singular
              enforced blueprint after triple-confirmation. Opt-in; direct
              `crew-create.sh` still works.

              Six-question interrogation drives a structured blueprint JSON:
                1. GOAL (one sentence)
                2. STANDARDS (quality/accuracy/performance targets)
                3. SUCCESS CRITERIA (concrete + testable)
                4. EXPECTED OUTCOME (deliverable shape)
                5. CONSTRAINTS (deadlines, budget, hardware, compliance)
                6. NON-GOALS (out-of-scope)

              Blueprint render: $CREWS_DIR/.blueprints/<slug>-<ts>.json,
              status=draft, confirmations=0. After triple-confirm: status=
              confirmed, confirmations=3.

              Triple-confirmation forces the user to read between each
              confirmation: replays the goal/standards/success criteria/
              constraints/non-goals fully each time. Reject at any step
              discards the blueprint. Edit mode is stubbed (returns
              "re-run") since editing requires another full prompt cycle —
              follow-up CL.

              Agent recommendation: scans /data/agents/, lists available
              agents, lets the user pick or accept all. In NI mode picks all.

              Crew name: user-provided OR auto-suggested from goal slug
              (e.g. "Refactor payment gateway" → "refactor-payment-gateway").

              Hand-off: HEMLOCK_NONINTERACTIVE=1 bash crew-create.sh <name>
              <members…>, then appends blueprint reference to crew.yaml.

              Non-interactive mode: --answers <path.json|.yaml> required;
              triple-confirm skipped (the answers file IS the artifact).

              Menu wiring: option 19 → 9 = "Crew PM blueprint workflow"
              with sub-options interactive run / NI run / list blueprints.

Tests Passing: bash -n clean. NI test with sample answers file produced a
              valid blueprint JSON with all 6 fields populated, dry-run
              correctly handed off to crew-create.sh (without executing it).
Phase       : CL-019 — PM Blueprint
Rollback Ref: Working copy. Revert by deleting crew-pm-blueprint.sh and
              the _run_hemlock_pm_blueprint function + option-9 dispatch
              in menu.sh.
```

## CL-020 — Registrar Agent (Stub Mode) + Local Ledger

```
Date        : 2026-06-26 23:10 UTC
Contributor : Claude (Opus 4.7)
Modules     : MOD-015 (Hemlock Host CLI), MOD-020 (Bridge)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: hemlock/hemlock-runtime/agents/registrar/{SOUL.md,
              IDENTITY.md, TOOLS.md, registrar.json, HEARTBEAT.md} (new),
              hemlock/hemlock-runtime/agents/registrar/{.archive,.secrets,
              avatar,knowledge,logs,memory,projects,sessions,skills,tools}/
              (new dirs — CL-018 lean layout),
              hemlock/hemlock-runtime/scripts/agent-register.sh (new),
              blueprint/blueprint.md, CHANGELOG.md
Description : Scaffolds the on-chain registrar — sole authority for creating,
              registering, and managing every other agent. Per user direction
              (paraphrased): "an agent responsible for creating and managing
              current and future individual agents, registering on chain with
              proper metadata outlining functions/tools/skills/identity/X402
              wallets/A2A comm/profile picture."

              Registrar agent workspace (CL-018-compliant lean layout):
                Files: SOUL.md IDENTITY.md TOOLS.md registrar.json (per-agent
                       isolation), HEARTBEAT.md
                Dirs:  .archive/ .secrets/ avatar/ knowledge/ logs/ memory/
                       projects/ sessions/ skills/ tools/

              SOUL.md establishes the registrar as: sovereign on-chain
              custodian, authoritative (no bypass for agent creation),
              verifiable (every agent gets cryptographic metadata), reversible
              (revocations emit tombstones), idempotent (no-op on identical
              re-register), sandboxed wallets (registrar never holds another
              agent's private key beyond initial provisioning).

              IDENTITY.md declares capabilities: agent_create_with_registration,
              agent_revoke_with_tombstone, onchain_register_metadata,
              onchain_revoke_metadata, x402_wallet_provision/rotate,
              attestation_sign/verify, audit_manifest_generate.

              registrar.json runtime config: chain=base, mainnet chain_id=8453,
              testnet chain_id=84532, wallet_library=thirdweb-sdk,
              gas_policy=registrar-funded, stub_mode=true.

              agent-register.sh implements the full flow as a stub:
                1. agent-create.sh (lean CL-018 workspace) unless --skip-create
                2. X402 wallet provision (stub: 32-byte /dev/urandom hex,
                   pubkey="0xstub_<sha256-first-40>", chmod 600)
                3. Hash IDENTITY.md + TOOLS.md + SOUL.md + skills/ manifest +
                   <id>.json (with mutable "chain" block stripped from json hash
                   for clean idempotency)
                4. Combined hash → if matches existing ledger entry, no-op
                5. Emit "chain tx" (stub: local hash, ledger entry written)
                6. Write chain block into <id>.json + signed attestation
                   into .secrets/registrar.attestation.json
                7. Append audit-log line to registrar/logs/registry.log

              Local ledger at /data/agents/registrar/.secrets/local-registry.
              json maintains the full registry shape so downstream consumers
              (audit, revocation, PM blueprint) work identically to the real-
              chain path. Swapping to real chain is one function: replace
              `_emit_chain_tx` to call thirdweb-sdk + the Base RPC.

              Deferred decisions (operator must confirm before chain swap):
                - Chain selection: Base mainnet vs Sepolia
                - RPC endpoint: Coinbase, Infura, public
                - Wallet library: thirdweb-sdk vs raw ethers.js
                - Gas policy: operator covers vs registrar funded

              CLI surface (working today):
                agent-register.sh --id <id> --name <name> --model <model>
                agent-register.sh --id <id> --refresh
                agent-register.sh --id <id> --skip-create

Tests Passing: bash -n clean. End-to-end test: alice registered fresh →
              chain block populated in alice.json → attestation written →
              local ledger has alice entry. Idempotency verified: 3
              successive registers, only first emits a tx, runs 2+3
              correctly report "Already registered with current hashes
              — no-op".
Phase       : CL-020 — Registrar (stub)
Rollback Ref: Working copy. Revert by deleting
              hemlock/hemlock-runtime/agents/registrar/ and
              hemlock/hemlock-runtime/scripts/agent-register.sh.
```

## CL-021 — H4 Sandboxing Decision: Superseded by CL-012 Volume Isolation

```
Date        : 2026-06-26 23:15 UTC
Contributor : Claude (Opus 4.7)
Modules     : MOD-015 (Hemlock Host CLI)
Section Tags: [HEMLOCK-BLUEPRINT-v1], [SPECS-v1]
Files Changed: blueprint/blueprint.md, CHANGELOG.md (documentation-only)
Description : Original H4 plan was bwrap-based per-agent sandboxing inside
              the runtime container. Per CL-012 + CL-014 + CL-018:

                - Each agent has its own docker named volume
                  (hemlock_agent_<id>) — per-agent persistent data
                - Each crew has its own docker named volume
                  (hemlock_crew_<name>) — per-crew shared state
                - Agents inside the container share the process namespace
                  BUT their data is filesystem-isolated by volume mounts
                - Per-agent .secrets/ chmod 600 (CL-017 patches enforced
                  proper permission normalization)
                - Registrar (CL-020) provides per-agent X402 wallets;
                  private keys live ONLY in the agent's own .secrets/ —
                  registrar never holds another agent's key

              Net assessment: the named-volume + chmod-600 + registrar-
              isolated-wallet stack provides MEANINGFUL isolation at the
              filesystem layer. What it does NOT provide:

                - Process-namespace isolation (agents share PID/uid in the
                  container by default)
                - In-memory isolation (one rogue agent CAN inspect another
                  agent's process memory if running as the same uid)
                - Network namespace isolation (all agents share container
                  network stack)

              For the typical Hemlock threat model (operator-owned agents,
              not adversarial code), CL-012's isolation is sufficient.

              For threat models that include "untrusted agent code on the
              same container" (e.g. third-party skills), the in-container
              sandbox WOULD add value. Options:

                A) bwrap per-tool-invocation (sandbox each `Bash` /
                   `execute_code` call, not the agent process itself)
                B) Per-agent uid (run each agent's loop as a distinct
                   uid; chmod 600 on .secrets/ now actually keeps other
                   agents out)
                C) Per-agent network namespace (isolate egress per agent
                   for compliance/billing tracking)
                D) Move to one-container-per-agent (the OLD pattern that
                   CL-012 explicitly rejected for resource reasons)

              DECISION: H4 is SUPERSEDED. The work stays in the queue but
              re-prioritized as a follow-up triggered by:
                - First untrusted-skill threat model requirement
                - First compliance audit asking for per-agent attestation
                  of process isolation
                - Operator request to run third-party agents

              When that trigger fires, the recommended path is (B) per-agent
              uid + (A) bwrap-on-tool-invocation — sandbox the unsafe surface
              (tool execution), not the whole agent loop. Maintains the
              named-volume + registrar isolation we already have AND adds
              process-level protection where it matters.

Tests Passing: No tests added — documentation-only CL.
Phase       : CL-021 — H4 sandboxing supersession
Rollback Ref: N/A (no code changed).
```

---

## CL-039 — Consolidation, Isolation & Alignment (Phase 8)

```
Date        : 2026-07-02
Author      : Claude (Opus 4.8), directed by project owner
Class       : AMENDMENT (adds PART VI Phase 8; PART II modules pending)

Log drift    : This change log was current only through CL-021, while the
              codebase advanced to CL-038 (image tags cl-026/cl-029/cl-038).
              CL-022–CL-038 were applied in code but never journaled here.
              CL-039 does NOT retro-document them; it resumes the log at the
              real head and flags the gap for a later reconciliation pass.

Summary     : A full-system reconciliation established ONE canonical source at
              ~/projects/hemlock/ (archives/ + runtime/ [Hemlock isolated] +
              hemlock-usb/ [Hemlock+USB working dir]). ~14 scattered project
              copies, ~/.openclaw, and 130 duplicate opencode skills moved to a
              reversible quarantine (nothing deleted). Pollution trees
              (fresh-skills-need-bring-others, hemlock-minimal) stripped.
              OpenClaw uninstalled (global npm) — gateway is carried by Hemlock.

Direction   : Portable cross-platform VM; host donates ONLY CPU/RAM; all deps,
              tooling, and skills baked into persistent state. ZERO host
              coupling (no bind mounts, no host file writes — even without
              docker). Skills baked READ-ONLY, seeded to a named volume, agents
              COPY into their workspace; NO symlinks in the skill set.

Changes     : - Dockerfile.runtime: skills now bake from shared/skills/ (was the
                stripped fresh-skills-need-bring-others/_curated/ — would have
                failed the build); no github clone.
              - docker-compose.yml: /skills → self-contained named volume seeded
                from the image (was empty :ro host bind mount).
              - menu.sh option 8: "Skills manager" — self-contained baked set +
                opt-in remote skill repos (add/list/remove/update).

Pending (Phase 8 checklist, PART VI):
              - Isolation: bake+seed runtime/agents/crews/models/backups → named
                volumes (remove all bind mounts).
              - Build + functional validation (gateway :18789, Hermes health).
              - Live agent import / workspace create / gateway↔Hermes MCP.
              - Chat command layer: verify !/ via gateway binaries (19 platform
                adapters); ADD custom-command management.
              - Hemlock doctor parity with openclaw doctor.
              - GUI rebrand: OpenClaw control-ui → Hemlock blue.
              - Agent behavioral enforcement structure (owner-led).

Tests Passing: USB-side suite usb/tests/00–13 = 14/14. Container build + runtime
              validation IN PROGRESS (Phase 8 Steps 3–4).
Phase       : CL-039 — Phase 8 Consolidation/Isolation/Alignment
Rollback Ref: Quarantine at ~/_hemlock-quarantine/ (reversible); no deletions.
```
