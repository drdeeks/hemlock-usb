# AGENTS.md — USB-Hemlock Unified Compute Platform

Compact instruction file for OpenCode agents. Every line answers: "Would an agent likely miss this without help?"

---

## 1. Dual-Purpose Architecture

Two directories, two purposes, one menu. This is the most important thing to understand.

| Directory | Purpose | Runs On | Entry Point |
|-----------|---------|---------|-------------|
| `usb/` | Portable USB compute automation | USB live environment OR host | `usb-setup-assistant.sh` |
| `hemlock/` | Dockerized AI agent orchestration | Host (Docker) | `hemlock-runtime/scripts/hemlock` |

**`menu.sh`** at root is the singular master entry point for everything. It auto-detects `HEMLOCK_DIR` and sources `usb/lib/` modules.

### Target Labels

Every menu option has a target label that tells you WHERE the action happens:

- **[USB]** — modifies USB drive (Ventoy, persistence, boot scripts)
- **[HOST]** — modifies the host machine (aliases, SSH, services, packages)
- **[CONTAINER]** — runs inside Docker container (Hemlock agent runtime)
- **[ALL]** — spans all three (DEPLOY.sh, validation)
- **[USB+HOST]** — spans USB and host (startup manager)

When editing code, you MUST know which target you're modifying. A `[USB]` change must work on any machine with a Ventoy USB. A `[HOST]` change must work on Linux/macOS/WSL. A `[CONTAINER]` change runs in Docker.

---

## 2. Master Menu (18 default options; 19 with `--hemlock`/`-H`)

Hemlock is opt-in. Default launches **hide** the Hemlock entry. Pass
`--hemlock` / `-H` (or export `HEMLOCK_ENABLED=true`) to reveal a single
consolidated Hemlock Manager option that subsumes the former options
8/9/10 (Hemlock TUI, Status, Master Deploy).

```
USB Components:
  1)  USB Setup Assistant        [USB]      Interactive Ventoy installer
  2)  Unified CLI (usbctl)       [USB]      USB/config/alias/validate
  3)  Alias Manager              [HOST]     Manage ~/.bash_aliases_usb
  4)  SSH Host Manager           [HOST]     Manage ~/.ssh/hosts_usb
  5)  System Manager (sysman)    [HOST]     Health/network/disk/services
  6)  USB Auto-Mount             [HOST]     udev + systemd setup
  7)  Build Essentials           [HOST]     Install dev toolchain

Configuration:
  8)  Startup Manager            [USB+HOST] Boot scripts & autostart
  9)  Persistence Manager        [USB]      Persistence partitions
  10) Bash Profile Manager       [HOST]     Shell config & aliases
  11) USB Device Setup           [USB]      Detect/select USB device
  12) Device/Boot Profiles       [HOST/USB] USB-resident profiles + autoboot
                                            + manifest (primary+data_volumes)
                                            + compile→ventoy.json + apply mounts

System:
  13) Run Validation             [ALL]      Validate all components
  14) Diagnostics                [HOST]     System info & config
  15) View Logs                  [HOST]     Log viewer & search

Access & Configuration:
  16) USB Paths & Environment    [HOST]     Configure paths/schema/env (FS-008)
  17) USB Access & Boot          [USB+HOST] Terminal/chroot/QEMU/SSH (FS-009)
  18) Toggle Dry-Run             (toggle)

Hemlock  (only when --hemlock/-H or HEMLOCK_ENABLED=true):
  19) Hemlock Manager            [CONTAINER] Runtime/agents/crews/deploy/doctor
```

Source: `menu.sh` text render and whiptail functions.

**Status header** shows: USB device, mount, persistence size (dynamically
resolved — no hardcoded filename), environment (`usb-boot`|`usb-mounted`|
`native`), and a `[Hemlock enabled]` badge when the opt-in flag is set.

**Options 16–17 (FS-008/FS-009):** `16` edits a sourced `usb-paths.conf` so the
whole file-tree schema is configurable (mount, persistence dir, multiple
volumes, script paths, rc.local path, ISO, QEMU RAM/CPUs/SSH-port, boot target,
install target) plus a `usb-env.conf` for env vars. `17` gives terminal/chroot
access into persistence volumes, rc.local editing, QEMU headless(+SSH
hostfwd)/GUI/ISO boot, SSH-into-VM, USB-targeted tooling install, and OS-aware
headless autostart. **USB-first install policy:** tooling installs onto the USB
persistence by default; host installs go through `_uca_require_host_dep`, which
explains why the dep must be host-side (QEMU/KVM = host CPU/RAM + port-forward)
and shows the OS-detected install command before prompting. All `_uca_*` actions
honor `DRY_RUN`, confirm first, and clean up mounts.

**Option 19 (Hemlock Manager, opt-in):** consolidates the former separate
Hemlock entries. Today's sub-options (per CL-013/CL-014/CL-015):
- 1) Launch in-container TUI
- 2) Runtime status
- 3) Master Deploy (`hemlock/DEPLOY.sh`)
- 4) Hemlock Doctor (health/doctor_bridge — 8 categories)
- 5) Launch Hemlock Control (GUI) — auto-fills token, chromium `--app=...`
- 6) Volume management — list/inspect/backup/destroy `hemlock_*` volumes
- 7) Check for updates — `.auto-update.sh` wrapper with rollback

**Option 14 (Diagnostics) — antivirus toolkit surface (CL-015).**
After the static system-info dump, two sub-options:
- 1) Install antivirus toolkit (`scripts/install-antivirus.sh` — clamav,
     rkhunter, lynis, trivy, ufw, apparmor; installs `/usr/local/bin/virus`
     command + cron jobs)
- 2) Run antivirus action — scan/fullscan/rootkit/selfheal/remediate,
     plus quarantine list/purge. Scans now auto-quarantine into
     `/var/quarantine/system_toolkit` instead of just printing findings.

**Sudo cache policy (CL-015).** First-run setup walks the operator
through a triple-confirmation flow to pick between ENCRYPTED-AT-REST
(libsecret/keyring), SESSION CACHE (sudo-v + 60s keepalive, sudo-k on
exit), or NO CACHE. Choice persists in `~/.config/usb-compute-automation/
sudo-policy` (chmod 600). After initial setup, every menu action runs
without sudo because `_uca_normalize_permissions` chowns the config dir
back to `$USER` (dirs 755, files 644, secrets 600). Autoboot bypasses
the whole flow.

**llmrl auto-trigger (CL-014/CL-015).** The vendored
`usb/scripts/setup-llmrl.sh` (HF model browser/downloader, Node)
auto-installs on two opt-in events: (a) `install_llama_cpp()` success,
(b) Bash Profile Manager → "Install enhanced bash profile". Otherwise
it's copied to the USB at `<mount>/tools/setup-llmrl.sh` for manual run.

---

## 3. Three Execution Models

### Model A: Sourceable lib/ Modules (`usb/lib/*.sh`)

Used by: `menu.sh`, `cli/usbctl`, `scripts/alias_manager.sh`

- Double-source guard on every module: `[[ -n "${UCA_<MODULE>_SH_SOURCED:-}" ]] && return 0`
- Colors are overridable defaults: `: "${RED:=\033[0;31m]}"` — never hard-assign
- Mutations go through `run_or_dry` (honors `DRY_RUN`) or `safe_exec` (timeout + error capture)
- `jq` is a hard dependency for `config.sh` and `validation.sh`
- Cross-module deps load idempotently: `[[ -n "${UCA_CORE_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/core.sh"`

7 modules:

| Module | Key Functions | Guard Var |
|--------|--------------|-----------|
| `core.sh` | `uca_log`, `print_header/success/error/warning/info`, `confirm`, `run_or_dry`, `safe_exec`, `set_standard_traps` | `UCA_CORE_SH_SOURCED` |
| `logging.sh` | `log_info/warn/error/debug/section/result` (structured, file output, rotation) | `UCA_LOGGING_SH_SOURCED` |
| `platform.sh` | `detect_os` → Linux/macOS/WSL/Windows, `detect_virtualization`, `select_best_tool` | `UCA_PLATFORM_SH_SOURCED` |
| `usb.sh` | `detect_ventoy_mount` (5 fallbacks), `unmount_ventoy`, `check_persistence_exists`, `get_persistence_size` | `UCA_USB_SH_SOURCED` |
| `config.sh` | `config_init/get/set` (JSON via jq), `generate_host_id` | `UCA_CONFIG_SH_SOURCED` |
| `menu.sh` | `menu_loop "Title" render_fn handler_fn`, stack-based navigation (`UCA_MENU_STACK`) | `UCA_MENU_SH_SOURCED` |
| `validation.sh` | `validate_host_id`, `validate_usb_mount`, `self_heal`, `run_full_validation` | `UCA_VALIDATION_SH_SOURCED` |

### Model B: Self-Contained Monoliths

These files re-declare their own `print_*`/`run_or_dry`/colors. Do NOT assume `lib/` is available.

| File | Lines | Purpose |
|------|-------|---------|
| `usb/usb-setup-assistant.sh` | 5908 | Interactive Ventoy installer, persistence, VM, essentials |
| `usb/sysman.sh` | ~1000 | System health/repair dashboard (whiptail + text fallback) |
| `usb/scripts/ssh_host_manager.sh` | ~1000 | `~/.ssh/hosts_usb` CRUD (pipe-delimited store) |

When editing these, match their local style — they don't share lib/ conventions.

### Model C: In-Container Runtime

Runs inside Docker. Host files not visible. Uses staging bridge for file transfers.

| File | Purpose |
|------|---------|
| `hemlock/hemlock-runtime/scripts/runtime.sh` | In-container TUI (1334 lines) |
| `hemlock/hemlock-runtime/scripts/hemlock` | Host-side CLI (container lifecycle, staging watcher) |
| `hemlock/hemlock-runtime/scripts/hemlock-stage.sh` | Import/export staging via `volumes/imports/.request` |

---

## 4. Quick Commands

```bash
# Entry point
bash menu.sh                          # Interactive menu (whiptail or text fallback)
bash menu.sh --dry-run                # Preview mode (no mutations)
bash menu.sh --text                   # Force text menu (no whiptail dependency)
bash menu.sh --help                   # Show help

# Syntax check (MUST run after every .sh edit)
bash -n menu.sh usb/lib/*.sh usb/cli/usbctl usb/scripts/*.sh usb/sysman.sh usb/usb-setup-assistant.sh

# Test suite (163+ assertions across 14 test scripts)
bash usb/tests/run-all.sh             # All tests
bash usb/tests/run-all.sh --syntax    # Syntax checks only
bash usb/tests/run-all.sh --runtime   # Runtime behavior only
bash usb/tests/run-all.sh --integration  # Integration tests only
bash usb/tests/run-all.sh --dry-run   # Dry-run tests (no mutations)

# Validation
bash usb/cli/usbctl validate all      # Host-id, USB mount, menu stack

# Individual usbctl commands
bash usb/cli/usbctl usb detect        # List USB devices
bash usb/cli/usbctl usb mount         # Mount Ventoy USB (needs SELECTED_DEVICE)
bash usb/cli/usbctl usb persistence   # Show persistence status
bash usb/cli/usbctl config host-id    # Generate host ID
bash usb/cli/usbctl config show       # Show full config
bash usb/cli/usbctl alias --list      # List aliases

# Deployment (requires root)
sudo bash hemlock/DEPLOY.sh --dry-run # Preview deployment
sudo bash hemlock/DEPLOY.sh           # Full deployment (system + USB + Hemlock)
sudo bash hemlock/DEPLOY.sh --no-system --no-usb  # Hemlock only

# Individual managers (can also be accessed via menu.sh)
bash usb/scripts/alias_manager.sh --list       # List aliases
bash usb/scripts/alias_manager.sh --add NAME 'CMD' 'desc'  # Add alias
bash usb/scripts/ssh_host_manager.sh --list    # List SSH hosts
bash usb/sysman.sh --health                    # System health check
```

---

## 5. Verified Bugs (All Fixed)

All 18 verified bugs have been fixed. Documenting them here so agents understand the patterns that caused them. BUG-14/BUG-15 were exposed by navigating the menu with a real Ventoy USB attached. BUG-16..BUG-18 were exposed while registering the first real boot profile (2026-07-08).

### BUG-1: usbctl alias path (FIXED)

**File:** `usb/cli/usbctl:155`
**Bug:** Called `$PROJECT_ROOT/alias_manager.sh` — file doesn't exist at repo root.
**Fix:** Changed to `$PROJECT_ROOT/scripts/alias_manager.sh`.

### BUG-2: alias_manager.sh lib source path (FIXED)

**File:** `usb/scripts/alias_manager.sh:44-52`
**Bug:** Sourced `$SCRIPT_DIR/lib/*.sh` → resolves to `scripts/lib/core.sh` (doesn't exist). `lib/` is at `../lib/` relative to `scripts/`.
**Fix:** Changed to `$SCRIPT_DIR/../lib/*.sh` with fallback detection.

### BUG-3: hemlock-tui hardcoded path (FIXED)

**Files:** `usb/hemlock-tui`, `hemlock/hemlock-tui`
**Bug:** Default `HEMLOCK_DIR` was `/home/ubuntu/projects/hemlock-test/hemlock` — always fails on other machines.
**Fix:** Replaced with 3-path auto-detection search (sibling `hemlock/hemlock-runtime`, `hemlock-complete-deployment/hemlock-runtime`, `hemlock-runtime`).

### BUG-4: hemlock-tui permissions (FIXED)

**Files:** `usb/hemlock-tui`, `hemlock/hemlock-tui`
**Bug:** Permissions were 644 (not executable).
**Fix:** Changed to 755.

### BUG-5: sysman.sh `-n` flag collision (FIXED)

**File:** `usb/sysman.sh:738,746`
**Bug:** Both `--dry-run|-n` and `--network|-n` used `-n`. Case-match order meant `-n` always triggered dry-run, making `--network` unreachable via short flag.
**Fix:** `--network` now uses `-N` instead of `-n`.

### BUG-6: sysman.sh CLI fallthrough (FIXED)

**File:** `usb/sysman.sh:780`
**Bug:** After processing CLI arguments (`--dry-run --health` etc.), the `while` loop consumed all args, then `if [[ $# -eq 0 ]]` was always true → launched interactive menu.
**Fix:** Track `cli_args_provided` before the while loop; check after instead of `$# -eq 0`.

### BUG-7: ssh_host_manager.sh CLI fallthrough (FIXED)

**File:** `usb/scripts/ssh_host_manager.sh:988`
**Bug:** Same pattern as BUG-6 — CLI args consumed, then fell through to interactive menu.
**Fix:** Same pattern — track `CLI_ARG_PROCESSED` flag before args loop.

### BUG-8: menu.sh text mode swallowed all component output (FIXED)

**File:** `menu.sh` (main(), text-mode branch)
**Bug:** Used `menu_loop` from `lib/menu.sh`, which reads the handler's verdict via `action=$("$handler_fn" "$choice")`. Since `_main_menu_handler` prints output directly rather than echoing `stay|back|exit`, every option's output (Diagnostics, Hemlock Status, etc.) was captured into `$action` and discarded — the menu just silently re-rendered.
**Fix:** `menu.sh` now drives `_main_menu_handler` with its own inline `while` loop that calls the handler directly (no command substitution). `lib/menu.sh` itself is untouched and still used correctly by `alias_manager.sh`.

### BUG-9: menu.sh whiptail mode non-functional (FIXED)

**File:** `menu.sh:_main_menu_whiptail`
**Bug:** `"3>&1 1>&2 2>&3"` was passed as a literal quoted string argument to `whiptail`, not as a shell redirection, so whiptail's selection was never captured on stdout.
**Fix:** Made it a real redirection (`3>&1 1>&2 2>&3` after the last menu item, inside the command substitution).

### BUG-10: menu.sh whiptail mode had no way to quit (FIXED)

**File:** `menu.sh:_main_menu_whiptail` / `main()`
**Bug:** Cancel/ESC made `_main_menu_whiptail` `return 0`, and the caller's `while true; do ... _main_menu_whiptail || break; done` only breaks on non-zero — so Cancel/ESC looped forever with no quit option in the menu itself.
**Fix:** Whiptail's Cancel button is relabeled "Quit" via `--cancel-button "Quit"`; Cancel/ESC now makes the function return non-zero, breaking the outer loop and exiting the program.

### BUG-11: menu.sh USB device auto-detection produced a mangled device path (FIXED)

**File:** `menu.sh:_detect_usb_devices`
**Bug:** `sed 's/[├─└─│ ]//g'` stripped spaces along with tree-drawing glyphs, then `awk '{print $1}'` ran on the already-space-collapsed line — producing `/dev/sdb1exfatVentoy` instead of a clean device path. `detect_ventoy_mount` (which appends a partition suffix itself) then failed to find anything.
**Fix:** Extract the NAME column first, strip only tree glyphs, then strip the trailing partition number/`p<N>` suffix to reduce a partition (`sdb1`) to its base disk (`sdb`), matching what `detect_ventoy_mount` expects.

### BUG-12: menu.sh alias/SSH managers always ran in dry-run regardless of toggle (FIXED)

**File:** `menu.sh:_run_alias_manager`, `_run_ssh_manager`
**Bug:** Used `${DRY_RUN:+--dry-run}`, which expands to `--dry-run` whenever `$DRY_RUN` is non-empty — and `DRY_RUN` defaults to the literal string `"false"`, which is non-empty. So both managers always received `--dry-run` and never mutated, even with the dry-run toggle (option 19) off.
**Fix:** Changed to an explicit conditional: `[[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)`.

### BUG-13: menu.sh handler failures could abort the whole menu (FIXED)

**File:** `menu.sh:main()`, `_main_menu_whiptail`
**Bug:** `menu.sh` runs under `set -euo pipefail`. A non-zero return from any `_run_*` handler (e.g. a failed sub-command) could propagate and kill the entire interactive session instead of just that one operation.
**Fix:** All handler invocations are now called with `|| true`. Also hardened `read` EOF handling in the text loop to break cleanly instead of risking a busy-loop on closed stdin.

### BUG-14: menu.sh submenus crashed on `set -u` "Back" item (FIXED)

**File:** `menu.sh:_menu_item`
**Bug:** `_menu_item` did `local target="$3" detail="$4"` unconditionally, but every submenu renders its Back row as `_menu_item "0" "Back"` (2 args). Under `set -u` the unbound `$3` aborted the script with `line N: $3: unbound variable` the moment a submenu (Persistence, Startup, usbctl, Auto-Mount, Bash Profile, Device Config) was opened. Latent because the test suite never rendered those submenus; surfaced immediately when navigating with a real device attached.
**Fix:** Default the optional args: `local target="${3:-}" detail="${4:-}"`.

### BUG-15: menu.sh missed the real Ventoy mount path (FIXED)

**Files:** `menu.sh` — Persistence Manager, Startup Manager (10 sites), `main()`
**Bug:** Persistence/Startup submenus resolved the mount with a hardcoded `for mp in /mnt/ventoy /Volumes/Ventoy` loop, which does NOT include `/media/$USER/Ventoy` — the path desktop Linux (GNOME/udisks) actually auto-mounts to. On a real, standard Ventoy USB mounted at `/media/drdeek/Ventoy`, every persistence/startup action wrongly reported "Ventoy not mounted." Separately, `main()` only ran `detect_ventoy_mount` when it auto-detected the device, so a pre-set `SELECTED_DEVICE` left the status header showing "not mounted."
**Fix:** Added `_resolve_ventoy_mount` (prefers the already-detected `$VENTOY_MOUNT`, then `detect_ventoy_mount`, then scans `/media/$USER/Ventoy`, `/run/media/$USER/Ventoy`, glob fallbacks, `/mnt/ventoy`, `/Volumes/Ventoy`) and replaced all 10 hardcoded loops with it. `main()` now resolves the mount whether the device was auto-detected or pre-set. Verified against a real 233G Ventoy drive (`/dev/sdb` → `/media/drdeek/Ventoy`, 225G persistence).

---

### BUG-16: profile autoload read the whole `primary` object (FIXED)

**File:** `menu.sh` `_uca_autoload_profile`
**Bug:** `jq -r '.primary'` on a schema-conformant profile (`primary` is `{file,label}`) injected object JSON into `UCA_PERSISTENCE_VOLUMES`.
**Fix:** Read `.primary.file` and resolve the mount-relative path against the USB mount. Verified with the live `hemlock-main` default profile.

### BUG-17: validate-all-skills.sh death by `set -e` + `((var++))` (FIXED)

**File:** `hemlock/hemlock-runtime/scripts/validate-all-skills.sh`
**Bug:** `((total++))` returns exit 1 when the variable is 0; under `set -euo pipefail` the first counted skill killed the script.
**Fix:** `var=$((var+1))` form. Pattern to remember: never post-increment with `(( ))` under `set -e`.

### BUG-18: validate-all-skills.sh assumed the container skills path (FIXED)

**File:** same script
**Bug:** `SKILLS_DIR` defaulted to `$RUNTIME_ROOT/skills` (container layout) — nonexistent on the host tree, so the report file write failed.
**Fix:** Falls back to `shared/skills` beside the scripts dir. Reports 17/17 valid.

## 6. Gotchas

- **`usb/usb-setup-assistant.sh`** is a 5908-line monolith. Do NOT refactor to use `lib/` without a blueprint amendment. It re-declares its own utilities.
- **`usb/sysman.sh`** and **`usb/scripts/ssh_host_manager.sh`** are self-contained. They share the same CLI fallthrough pattern (now fixed).
- **`DEPLOY.sh`** expects paths relative to `hemlock/` not `usb/`. It references `$SCRIPT_DIR/usb-compute-automation/` which exists in the deployment copy but NOT in `usb-hemlock-split/`. Run it from the `hemlock/` directory.
- **`jq` is required** for `lib/config.sh`, `lib/validation.sh`, and `feature-flags.json`. Install if missing: `apt install jq` or `brew install jq`.
- **`SELECTED_DEVICE`** must be exported before USB operations: `export SELECTED_DEVICE=/dev/sdX`. Detect with `lsblk`.
- **`HEMLOCK_DIR`** must point to `hemlock/hemlock-runtime/` for Hemlock TUI. Auto-detection works in `menu.sh` and `hemlock-tui` but may fail in edge cases.
- **Tests are standalone** — they source `test-helpers.sh` then `lib/` as needed. Run from repo root: `bash usb/tests/run-all.sh`.
- **Feature flags** in `feature-flags.json` are all `disabled`. They gate blueprint phases, not runtime behavior.
- **Ventoy tarball** is at `usb/volumes/ventoy/ventoy-1.0.99-linux.tar.gz` (20MB). Used by `usb-setup-assistant.sh`.
- **Persistence** uses ext4 with `casper-rw` label (Ubuntu casper convention). Default size 8GB, user-overridable.
- **`menu.sh` does NOT use `menu_loop`** from `lib/menu.sh` for its top-level loop — it drives `_main_menu_handler` with its own inline `while` loop (`q`/`Q`/`quit`/`exit` to quit; numbered "Back" item per submenu). This was changed because `menu_loop` reads the handler's return value via command substitution (`action=$(...)`), which silently swallows everything the handler prints. Sub-managers invoked from the menu, e.g. `usb/scripts/alias_manager.sh`, still use `menu_loop` legitimately for their own submenus — `lib/menu.sh` itself is unchanged.

---

## 7. File Inventory

### Root Level
| File | Lines | Purpose |
|------|-------|---------|
| `menu.sh` | 2042 | ★ Master entry point — 21-option interactive menu |
| `README.md` | 770 | Architecture, quick start, directory structure |
| `CHANGELOG.md` | 32 | Append-only change log |
| `feature-flags.json` | 180 | 29 feature flags (all disabled) |

### `usb/` — USB Compute Automation
| Path | Lines | Target | Purpose |
|------|-------|--------|---------|
| `lib/core.sh` | 82 | [USB] | Colors, logging, confirm, run_or_dry, safe_exec, traps |
| `lib/logging.sh` | 194 | [USB] | Structured logging with file output, rotation, levels |
| `lib/platform.sh` | ~80 | [USB] | OS/virtualization detection, tool selection |
| `lib/usb.sh` | ~120 | [USB] | Ventoy mount (5 fallbacks), persistence helpers |
| `lib/config.sh` | 75 | [USB] | JSON config via jq, host-id generation |
| `lib/menu.sh` | ~100 | [USB] | Stack-based menu_loop framework |
| `lib/validation.sh` | 99 | [USB] | Health checks + self_heal |
| `cli/usbctl` | 209 | [USB] | Unified CLI dispatcher (sources all lib/) |
| `scripts/alias_manager.sh` | ~400 | [HOST] | `~/.bash_aliases_usb` CRUD (uses lib/) |
| `scripts/ssh_host_manager.sh` | ~1000 | [HOST] | `~/.ssh/hosts_usb` CRUD (self-contained) |
| `scripts/setup-essentials-enhanced.sh` | ~600 | [HOST] | Build toolchain installer (needs root) |
| `scripts/setup-usb-compute.sh` | ~500 | [HOST] | Older standalone provisioning script |
| `scripts/bash_enhanced.sh` | ~200 | [HOST] | Enhanced .bashrc profile |
| `scripts/clean-local.sh` | ~100 | [HOST] | System cleanup |
| `scripts/install-antivirus.sh` | ~100 | [HOST] | Antivirus installer |
| `usb-setup-assistant.sh` | 5908 | [USB] | Interactive Ventoy installer (self-contained monolith) |
| `sysman.sh` | ~1000 | [HOST] | System health/repair dashboard (self-contained) |
| `hemlock-tui` | 45 | [CONTAINER] | Wrapper to launch Hemlock TUI |
| `usb-automount/` | 5 files | [HOST] | systemd + udev auto-mount installer |
| `config/initialize.sh` | ~300 | [USB] | Ubuntu one-time bootstrap |
| `volumes/ventoy/` | 1 file | [USB] | Bundled Ventoy tarball (20MB) |
| `tests/` | 16 files | [ALL] | Test suite (163+ assertions) |

### `hemlock/` — Agent Runtime
| Path | Lines | Target | Purpose |
|------|-------|--------|---------|
| `DEPLOY.sh` | 135 | [ALL] | Master deployment (system + USB + Hemlock, needs root) |
| `hemlock-tui` | ~40 | [CONTAINER] | Host-side wrapper to launch Hemlock TUI |
| `hemlock-runtime/scripts/hemlock` | ~200 | [CONTAINER] | Host CLI (container lifecycle, staging watcher) |
| `hemlock-runtime/scripts/runtime.sh` | 1334 | [CONTAINER] | In-container TUI (agent/crew/validation/security) |
| `hemlock-runtime/scripts/hemlock-stage.sh` | ~300 | [CONTAINER] | Import/export staging bridge |
| `hemlock-runtime/docker-compose.runtime.yml` | ~100 | [CONTAINER] | Primary compose (runtime/agent/doctor/setup) |
| `hemlock-runtime/docker-compose.yml` | ~50 | [CONTAINER] | Framework compose (single service) |
| `hemlock-runtime/Makefile` | ~50 | [CONTAINER] | Build targets |
| `hemlock-minimal/skills/` | ~20K files | [CONTAINER] | 84 agent skill packages |

### `blueprint/` — Enterprise Specification
| Path | Lines | Purpose |
|------|-------|---------|
| `blueprint.md` | 837 | Authoritative master specification (7 parts + change log) |
| `checklist.md` | 897 | Phase-synchronized enforcement checklist |
| `project.json` | ~30 | Phase registry and metadata |
| `assignments.json` | ~50 | Agent role assignments |

**Full specs:** See `blueprint/blueprint.md` for architecture, module registry, screen/feature specs, data architecture, change control protocol, implementation checklist, and quality standards.

---

## 8. Verification After Edits

```bash
# Syntax check everything you touch
bash -n menu.sh usb/lib/*.sh usb/cli/usbctl usb/scripts/*.sh usb/sysman.sh usb/usb-setup-assistant.sh

# Run the test suite
bash usb/tests/run-all.sh

# Preview mutations without side effects
DRY_RUN=true bash menu.sh --text --dry-run

# Health/self-heal checks
bash usb/cli/usbctl validate all
```

---

## 9. Blueprint Reference

The authoritative specification lives at `blueprint/blueprint.md` (837 lines). It covers:

- **Part I:** System overview, architecture diagram, tech stack
- **Part II:** Module registry (21 modules, MOD-001 through MOD-021)
- **Part III:** Screen & feature specifications (FS-001 through FS-007)
- **Part IV:** Data architecture (config stores, persistence, Docker volumes, ports)
- **Part V:** Change control protocol (append-only change log, contributor rules)
- **Part VI:** Master implementation checklist (8 phases, Phase 0 through Phase 7)
- **Part VII:** Quality & compliance standards (error handling, coding, testing, performance budgets)

**Enforcement:** `blueprint/checklist.md` (897 lines) — phase-synchronized enforcement checklist with pre-phase gates, implementation steps, validation gates, and agent sign-off blocks.

**Feature flags:** `feature-flags.json` — 29 flags (all disabled), gate blueprint phases.

When the blueprint and this file conflict, the blueprint wins.

---

## 10. Next Enhancements (queue)

> Forward-looking work agreed with the user but not yet implemented. Keep this
> list short and concrete; promote items to `blueprint/blueprint.md` (with a
> CL entry) once they ship.

- **Data-volume wizard** for the Persistence Manager (option 12). Guided
  flow that creates a new sibling `.dat` file (e.g. `hemlock.dat`,
  `models.dat`, `docker.dat`) next to the casper-rw primary: prompts for
  size (sanity-checked against USB free space), runs
  `dd if=/dev/zero of=<path> bs=1M count=<MB> status=progress` +
  `mkfs.ext4 -F -L <label> <path>` (per CL-006 relabel rules — never
  `casper-rw` here), and optionally adds the new volume to a selected
  profile's `data_volumes[]` via `_uca_profile_edit_manifest`. Closes the
  loop on the Phase 2 multi-state workflow so steps 1–2 of the
  "build the volumes" recipe in CL-007 become menu-driven. Will land as a
  new option under Persistence Manager (likely **12 → 10**) plus a
  cross-link from the profile edit wizard ("create a new volume now?").

- **Hemlock Control rebrand (deferred).** GUI launch is shipped (CL-013:
  option 19 → 5 auto-fills the token and opens chromium in --app mode
  pointing at OpenClaw Control web UI). The remaining rebrand work —
  forking the OpenClaw Control SPA under
  `hemlock/hemlock-runtime/docker/openclaw-runtime/` to swap title,
  favicons, theme name (`claw` → `hemlock`), i18n strings — is deferred
  until: (a) OpenClaw itself updated to current (out-of-date warning
  seen 2026-06-25), (b) a quiet machine for the npm build, (c) we add
  Hemlock-specific views (volume browser, profile switcher, USB info).

- **Hemlock H3 — shared `hemlock_skills` volume + daily refresh.** The
  next Hemlock phase. Single volume mounted read-only into every agent
  container; refresh via a systemd timer that pulls/updates the source
  skill tree. Will let us add new skills system-wide without touching
  per-agent volumes. Architecture stays restart-on-CRUD per CL-012.

- **Hemlock H5 — sandboxing (re-evaluate).** Originally bwrap-based.
  May simplify or drop entirely now that H2 ships per-volume isolation
  with no host filesystem coupling — revisit once H3 lands so the full
  picture is concrete.

- **`hemlock-blueprint.md §1.2` amendment.** The authoritative Hemlock
  spec still describes the old Docker-socket + bind-mount design;
  CL-012 + CL-014 supersede it with restart-on-CRUD + pure named
  volumes. Patch §1.2 to match the shipped reality the next time we
  touch that file.

- **llmrl power-user surface.** Vendored at `usb/scripts/setup-llmrl.sh`
  (CL-014). Today it's exposed via (a) `Build Essentials → llmrl` opt-in
  group on the USB persistence and (b) the `install_llmrl()` function in
  the host installer's LLM-engines questionnaire. Future polish:
  a dedicated menu option that runs `llmrl search` / `llmrl show`
  interactively against an already-installed copy, and integration with
  the planned Persistence Manager wizard so model storage lives on a
  dedicated `models.dat` sibling volume.
