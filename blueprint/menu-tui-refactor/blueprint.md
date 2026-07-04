# Menu TUI Refactor — ENTERPRISE BLUEPRINT
## Version 1.0 | Document Class: MASTER SPECIFICATION
### Generated: 2026-06-27

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

The interactive menu (`menu.sh`) is the single human entry point for the
USB-Hemlock platform. It is **USB-first**: every default targets the
mounted USB persistence, the host is touched only for the narrow set of
ops that genuinely require it (alias manager, bash profile, host udev/
systemd installs). The TUI is **stateful, error-resilient, and explicit**
— it loops on errors, explains every action before mutating, and never
leaks features the operator did not opt into.

## 1.2 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ENTRY LAYER — menu.sh                                       │
│    flags: --hemlock | --text | --dry-run                     │
│    auto-detects USB device, mount point, env                 │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│  TUI LOOP — main() while true: render → handle → continue    │
│    whiptail when available; --text fallback                  │
│    errors print + return-to-screen, NEVER abort the loop     │
│    status header on every screen (device, mount, env, flags) │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│  ACTION DISPATCH (USB-targeted by default)                   │
│    [USB] options: persistence, profile, install, chroot…    │
│    [HOST] options: alias mgr, bash profile, host services    │
│    [USB+HOST] options: auto-mount, headless autostart        │
│    [CONTAINER] options: Hemlock Manager (gated by --hemlock) │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│  TARGET LAYER                                                │
│    USB:        loop-mount + chroot + apt-in-persistence      │
│    HOST:       narrow surface — alias_manager / bash_profile │
│    CONTAINER:  docker compose (Hemlock runtime, opt-in)      │
└─────────────────────────────────────────────────────────────┘
```

## 1.3 Tech Stack

| Layer | Technology | Rationale |
|---|---|---|
| TUI front-end | bash + whiptail (Newt) | Universally available; falls back to plain text |
| Auto-detect | lsblk, udevadm, blkid, /proc/mounts, ventoy-marker | 5-method redundancy proven in CL-008/CL-031 |
| Chroot lifecycle | mount-bind /dev /proc /sys + chroot | Pure kernel primitives, no extra deps |
| Sudo cache | sudo -v keepalive + libsecret (encrypted-at-rest) | CL-015 triple-notification consent flow |
| Permission model | chmod 755/644, NEVER 0700 | CL-017 — operator never re-needs sudo for menu actions |
| Profile storage | USB-resident JSON manifests at <mount>/profiles/ | CL-008 — profiles travel with the drive |
| State tracking | ~/.config/usb-compute-automation/*.conf | Sourceable bash KEY=VAL; secrets chmod 600 |

---

---

# PART II — MODULE REGISTRY

> **Rollback Tag:** `[MODULE-REGISTRY-v1]`
> **Rule:** Every change log entry MUST reference at least one Module ID.

| Module ID | Name | Description | Feature Flag |
|---|---|---|---|
| MOD-001 | Main Menu Loop | `main()` while-true render+dispatch with error-trap returning to menu | FEAT_TUI_LOOP |
| MOD-002 | Auto-Detect | 5-method USB+mount+env detection at startup, re-run on demand | FEAT_AUTODETECT |
| MOD-003 | Status Header | Persistent banner on every screen: device, mount, persistence size, env, flags | FEAT_STATUS_HEADER |
| MOD-004 | Target-Labeled Options | Every option carries `[USB]/[HOST]/[USB+HOST]/[CONTAINER]` tag for instant clarity | FEAT_TARGET_LABELS |
| MOD-005 | Whiptail+Text Render | Whiptail when TTY; `--text` mode falls back to numbered prompts | FEAT_WHIPTAIL |
| MOD-006 | Persistence Manager v2 | Multi-volume support — list/add/edit/delete persistence files, no "already configured" denial | FEAT_PERSISTENCE_MULTI |
| MOD-007 | Hemlock Gate | Hemlock entries hidden unless `--hemlock` flag OR `HEMLOCK_ENABLED=true` env | FEAT_HEMLOCK_GATE |
| MOD-008 | USB-First Default Resolver | All [USB] options target USB persistence by default; host install requires explicit override + reason prompt | FEAT_USB_DEFAULT |
| MOD-009 | Sudo Consent | Triple-notification policy (CL-015) — encrypted-at-rest / session / none | FEAT_SUDO_CONSENT |
| MOD-010 | Permission Normalizer | Startup chown+chmod on `~/.config/usb-compute-automation/` so subsequent runs need no sudo | FEAT_PERM_NORMALIZE |
| MOD-011 | Error-Resilient Action Wrapper | `_run_action()` wraps every dispatch in `|| _menu_warn` so errors print + return | FEAT_ERROR_RESILIENT |
| MOD-012 | Action Explainer | Every action prints "this will do X to Y" before any mutation; DRY_RUN-aware | FEAT_EXPLAINER |
| MOD-013 | Startup Script Wizard | Writes startup hook into USB persistence rc.local by default; host install requires explicit `--host` confirmation | FEAT_STARTUP_USB_DEFAULT |

---

---

# PART III — SCREEN & FEATURE SPECIFICATIONS

> **Rollback Tag:** `[SPECS-v1]`
> Each specification follows this format:
> ID, Module Ref, Rollback Tag, Feature Flag, Purpose,
> Components, Rules, Error States, Fallback.

### SPEC-T01 Main Menu Loop — `_run_main_loop`

- **ID:** SPEC-T01
- **Module Ref:** MOD-001, MOD-011
- **Rollback Tag:** `[SPEC-T01-v1]`
- **Feature Flag:** `FEAT_TUI_LOOP`
- **Purpose:** Single re-entrant render→handle loop; errors NEVER drop user back to bash.
- **Components:** `render_status_header`, `render_options`, `dispatch_choice`, `error_trap_to_menu`.
- **Rules:**
  - Every dispatch is wrapped in `|| { _menu_warn "$action failed"; _menu_pause; continue; }`.
  - `q`, `Q`, `quit`, `exit`, `0`+Back navigate normally; nothing else exits.
  - Ctrl-C is trapped and asks "Confirm exit? [y/N]".
- **Error States:** Action throws → warn + pause + redisplay; dependency missing → suggest install + return; auto-detect fails → menu still renders with "device: <none>".
- **Fallback:** Whiptail unavailable → `--text` mode renders the same options as a numbered list.

### SPEC-T02 Auto-Detect at Startup — `_auto_detect()`

- **ID:** SPEC-T02
- **Module Ref:** MOD-002, MOD-003
- **Rollback Tag:** `[SPEC-T02-v1]`
- **Feature Flag:** `FEAT_AUTODETECT`
- **Purpose:** Identify USB device + Ventoy mount + env on startup so the user never has to set `SELECTED_DEVICE` by hand.
- **Components:** `lsblk_scan`, `udev_scan`, `blkid_scan`, `proc_mounts_scan`, `ventoy_marker_scan`.
- **Rules:**
  - 5-method redundancy — first match wins, all agree or warn.
  - Auto-detect is RE-RUN whenever the operator picks option 11 (USB Device Setup) explicitly.
  - Result persists in `~/.config/usb-compute-automation/state.json` (chmod 644).
- **Error States:** 0 USBs → header shows `device: <none>`, USB-only options gracefully fail with "no USB detected — re-run option 11"; >1 USBs → numbered picker.
- **Fallback:** Manual device entry via option 11 always available.

### SPEC-T03 Persistence Manager v2 — multi-volume

- **ID:** SPEC-T03
- **Module Ref:** MOD-006
- **Rollback Tag:** `[SPEC-T03-v1]`
- **Feature Flag:** `FEAT_PERSISTENCE_MULTI`
- **Purpose:** Fix the "already configured" denial — the operator MUST be able to add additional persistence volumes (e.g. `hemlock.dat`, `models.dat`, `docker.dat`) alongside the primary.
- **Components:**
  - `_persistence_list`: enumerate every `.dat` / `casper-rw` under `<mount>/persistence/` AND wherever `UCA_PERSISTENCE_VOLUMES` points.
  - `_persistence_add`: create new sibling `.dat` (size-prompted, ext4-formatted, label-checked per CL-006 — never `casper-rw` for non-primary).
  - `_persistence_edit`: rename / resize / relabel.
  - `_persistence_delete`: confirm-twice + archive metadata before unlink.
- **Rules:**
  - Adding a NEW persistence file MUST succeed even when a primary already exists.
  - The wizard auto-suggests a non-colliding label (e.g. existing `casper-rw` → suggest `hemlock-data`, `models-data`).
  - Optionally adds the new volume to the active profile's `data_volumes[]` (cross-link to Device/Boot Profiles menu).
- **Error States:** Insufficient free space on USB → reject with size diff; permission denied → escalate via sudo consent; collision with existing label → suggest alternative.
- **Fallback:** If `mkfs.ext4` missing → install via host-dep installer with explicit consent.

### SPEC-T04 Hemlock Gate — strict opt-in

- **ID:** SPEC-T04
- **Module Ref:** MOD-007
- **Rollback Tag:** `[SPEC-T04-v1]`
- **Feature Flag:** `FEAT_HEMLOCK_GATE`
- **Purpose:** Hemlock Manager (option 19) MUST be hidden when `--hemlock` flag is absent AND `HEMLOCK_ENABLED` env is unset/false. No Hemlock-related entries should leak into the default 18-option menu OR submenu prompts.
- **Components:** `_hemlock_enabled` predicate, conditional `_menu_item 19` render, conditional dispatch case-19.
- **Rules:**
  - `_hemlock_enabled` returns true only if `--hemlock`/`-H` passed OR `HEMLOCK_ENABLED=true` exported.
  - Default render: 18 options; status header shows `[Hemlock disabled]` for clarity.
  - With flag: 19 options; header shows `[Hemlock enabled]`.
- **Error States:** User picks option 19 while gate is closed → "Hemlock is opt-in; re-run with `--hemlock`" + return to menu.
- **Fallback:** N/A — this IS the gate.

### SPEC-T05 Startup-Script Wizard — USB-first default

- **ID:** SPEC-T05
- **Module Ref:** MOD-008, MOD-013
- **Rollback Tag:** `[SPEC-T05-v1]`
- **Feature Flag:** `FEAT_STARTUP_USB_DEFAULT`
- **Purpose:** Fix the current bug where the startup-script wizard defaults to writing to the host's `/etc/rc.local`. The default target MUST be the USB persistence's `rc.local`; host writes require an explicit `[HOST]` confirmation with reason prompt.
- **Components:** `_startup_wizard_target_resolver`, `_startup_write_to_persistence`, `_startup_write_to_host_with_consent`.
- **Rules:**
  - Default target = USB persistence (loop-mount + write to `etc/rc.local` inside the chroot path).
  - Host target requires an explicit answer to "writing this to the HOST instead of the USB will modify your live system — type HOST to confirm".
  - Auto-detects which persistence is the active primary via `_uca_primary_persistence` (no hardcoding).
- **Error States:** No USB mounted → "no USB target; aborting (re-run option 11 to detect)"; persistence not mountable → mount diag + bail.
- **Fallback:** N/A — refuses to silently default to host.

### SPEC-T06 Error-Resilient Action Wrapper

- **ID:** SPEC-T06
- **Module Ref:** MOD-011
- **Rollback Tag:** `[SPEC-T06-v1]`
- **Feature Flag:** `FEAT_ERROR_RESILIENT`
- **Purpose:** Every dispatch from the main loop is wrapped so a failing action prints + pauses + returns to menu instead of dropping the operator to bash.
- **Components:** `_dispatch(choice)` wrapper, `_menu_pause()` (waits for any key).
- **Rules:**
  - `set -e` is disabled in the main loop (only in pure-script paths).
  - Any non-zero exit from an action prints the captured stderr tail + `[FAIL] action exited <code>`.
  - The pause is bypassed when `DRY_RUN=true` (CI / scripted use).
- **Error States:** Action hard-crashes mid-output → trap catches + continues loop.
- **Fallback:** Operator can `Ctrl-C` → confirms exit.

---

---

# PART IV — DATA ARCHITECTURE

> **Rollback Tag:** `[DATA-ARCH-v1]`
> **Rule:** All schema changes require a migration file named
> `YYYYMMDD_NNN_description.sql` with a corresponding rollback file,
> and must be referenced in the Global Change Log.

## 4.1 Core Database Schemas

N/A — this is a TUI refactor. State lives in flat KEY=VAL config files at
`~/.config/usb-compute-automation/` (usb-paths.conf, usb-env.conf, sudo-policy)
plus USB-resident profile JSON manifests at `<mount>/profiles/`. No database,
no migrations, no schema versioning beyond the manifest version field.

## 4.2 API Contract Specifications

N/A — no external API. The menu shells out to local helpers:
- `usb/cli/usbctl` (USB CLI)
- `usb/sysman.sh` (system management)
- `usb/scripts/*.sh` (essentials installer, antivirus, clean-local, etc.)
- `hemlock/hemlock-runtime/scripts/*.sh` (via `docker exec` when --hemlock)

All helpers honor `DRY_RUN=true` and return non-zero on failure (CL-017).

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
Tests Passing: [test names, or 'none — pre-build']
Phase       : [PHASE-N]
Rollback Ref: [git commit hash or migration rollback filename]
```

## Contributor Rules

1. No code merged without a change log entry in the same PR.
2. No database migration without a rollback migration file.
3. Feature flags required for every Phase 2+ feature.
4. Minimum: 1 unit test per new function, 1 integration test per endpoint.
5. `CHANGELOG.md` CI append-only check must pass on every PR.
6. No contributor may modify or delete an existing change log entry.

---

---

# PART VI — MASTER IMPLEMENTATION CHECKLIST

## Pre-Build

**Section Tag:** `[PHASE-0-v1]`
**Feature Flag:** `FEAT_PRE_BUILD`
**Assigned Agent:** _unassigned_

### Prerequisites

All Phase N/A items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] [Define deliverable 1]
- [ ] [Define deliverable 2]

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
## Audit-Bugs

**Section Tag:** `[PHASE-1-v1]`
**Feature Flag:** `FEAT_AUDIT_BUGS`
**Assigned Agent:** _unassigned_

### Prerequisites

All Phase 0 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] [Define deliverable 1]
- [ ] [Define deliverable 2]

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
## Foundation-USB-First

**Section Tag:** `[PHASE-2-v1]`
**Feature Flag:** `FEAT_FOUNDATION_USB_FIRST`
**Assigned Agent:** _unassigned_

### Prerequisites

All Phase 1 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] [Define deliverable 1]
- [ ] [Define deliverable 2]

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
## Stateful-TUI-Loop

**Section Tag:** `[PHASE-3-v1]`
**Feature Flag:** `FEAT_STATEFUL_TUI_LOOP`
**Assigned Agent:** _unassigned_

### Prerequisites

All Phase 2 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] [Define deliverable 1]
- [ ] [Define deliverable 2]

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
## Persistence-Manager-Fix

**Section Tag:** `[PHASE-4-v1]`
**Feature Flag:** `FEAT_PERSISTENCE_MANAGER_FIX`
**Assigned Agent:** _unassigned_

### Prerequisites

All Phase 3 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] [Define deliverable 1]
- [ ] [Define deliverable 2]

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
## Hemlock-Gating

**Section Tag:** `[PHASE-5-v1]`
**Feature Flag:** `FEAT_HEMLOCK_GATING`
**Assigned Agent:** _unassigned_

### Prerequisites

All Phase 4 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] [Define deliverable 1]
- [ ] [Define deliverable 2]

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
## Validation

**Section Tag:** `[PHASE-6-v1]`
**Feature Flag:** `FEAT_VALIDATION`
**Assigned Agent:** _unassigned_

### Prerequisites

All Phase 5 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] [Define deliverable 1]
- [ ] [Define deliverable 2]

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---
## Cutover

**Section Tag:** `[PHASE-7-v1]`
**Feature Flag:** `FEAT_CUTOVER`
**Assigned Agent:** _unassigned_

### Prerequisites

All Phase 6 items must be complete, tests passing, and change log entry written.

### Deliverables

- [ ] [Define deliverable 1]
- [ ] [Define deliverable 2]

### Validation Gate

> No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.

### Rollback Procedure

1. Disable relevant feature flags immediately (no deployment required).
2. Assess whether a code rollback or flag-only disable resolves the issue.
3. If database migration rollback is required, obtain two-contributor approval.
4. Write a post-incident change log entry within 24 hours.

---

---

---

# PART VII — QUALITY & COMPLIANCE STANDARDS

> **Rollback Tag:** `[QUALITY-v1]`

## Error Handling Standards

1. Graceful degradation for all non-critical services.
2. User-facing messages: friendly, non-technical, no stack traces exposed.
3. Internal logging: full context — requestId, userId, error code, stack.
4. Retry: exponential backoff on external calls (3 retries: 1s, 2s, 4s).
5. Circuit breaker: 10 failures in 60s opens circuit for 5 minutes.

## Testing Requirements

- Unit tests: 80% line coverage on all core modules.
- Integration tests: every API endpoint has success + error case.
- E2E tests: all critical user flows have passing automated tests.

## Performance Budgets

| Metric | Budget |
|---|---|
| Page load LCP (3G) | < 2.0 seconds |
| API response time p95 | < 500ms |
| Background job completion | < 60 seconds |

---

---

# CHANGE LOG

> This section is append-only. No entry may be modified or deleted.

## CL-000 — Document Initialization

```
Date        : 2026-06-27
Contributor : [author]
Modules     : [MOD-001]
Section Tags: [[PHASE-0-v1]]
Files Changed: [blueprint.md, checklist.md]
Description : Initial blueprint created via enterprise-blueprint skill.
              Project: Menu TUI Refactor. All sections pre-populated with
              required enterprise structure awaiting content population.
Tests Passing: none — pre-build
Phase       : PHASE-0
Rollback Ref: N/A — initial document creation
```
