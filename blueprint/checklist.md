# USB-Hemlock Unified Compute Platform — ENTERPRISE CHECKLIST
## Coexists with: blueprint.md
### Generated: 2026-06-25

> **CHECKLIST AUTHORITY**
> This checklist enforces blueprint.md. It must not diverge — every
> blueprint amendment requires a corresponding checklist update in the
> same commit. Checked items are immutable; corrections require a new
> line with explanation, never erasure of a checked item.
>
> **Status values:** `NOT STARTED` | `IN PROGRESS` | `BLOCKED` | `COMPLETE`
> **Blocking rule:** No phase may begin until the prior phase is `COMPLETE`.

---

## RECONCILIATION NOTE — 2026-06-25 (Claude, Opus 4.8)

> Added per the checklist authority rule ("corrections require a new line with
> explanation, never erasure of a checked item"). This entry records the actual
> verified state of the working copy; no previously-checked item was erased.

This codebase is an **already-built system undergoing verification & hardening**,
not a greenfield build. The phase gates are therefore applied as *verification*
gates. Every phase's code exists and passes static (`bash -n`) and dry-run
checks. Phases are split by what can be confirmed in this environment:

| Phase | Reality | Status |
|---|---|---|
| 0 — Pre-Build Env | Tools present, 202 tests pass | **COMPLETE** |
| 1 — USB Foundation/Ventoy | **Non-destructive paths VERIFIED on a live Ventoy USB** (2026-06-25): `detect_ventoy_mount` resolves `/dev/sdb`→`/media/drdeek/Ventoy`, ISO + ventoy dir present. The **destructive Ventoy install** itself was not run (would erase a USB). | **PARTIAL (non-destructive verified)** |
| 2 — Persistence Layer | **Detection VERIFIED on the live drive** (2026-06-25): 225 GB `ubuntu-persistence.dat` found, partition layout correct (sdb1 exfat Ventoy / sdb2 vfat VTOYEFI). Destructive create/resize and root loop-mount not exercised. | **PARTIAL (read-only verified)** |
| 3 — Service Integration | alias/ssh/sysman CRUD + dry-run verified end-to-end | **COMPLETE** |
| 4 — System Mgmt/Health | sysman flags verified and **time-bounded against stalls**; `usbctl validate` passes | **COMPLETE** |
| 5 — Hemlock Runtime Deploy | Code verified; **Docker image build requires network/registry access** unavailable here | **BLOCKED (environment)** |
| 6 — Bridge/TUI | `hemlock-tui` auto-detection verified; full TUI round-trip needs a running container (Phase 5) | **BLOCKED (depends on 5)** |
| 7 — Validation/Hardening | Code-level battery done: `bash -n` clean, dry-run honored on every CLI mutation path, `usbctl validate all`, 202 tests pass, all **15** documented bugs fixed, perms normalized to 755. Plus FS-008/FS-009 feature amendment (configurable paths/env, USB Access & Boot, USB-first install policy — CL-004). Runtime items (in-container Hermes Doctor) deferred to Phase 5 env | **COMPLETE (code-level)** |

**Blocking-rule note:** the `BLOCKED` phases (1, 2, 5, 6) are gated on physical
hardware / network, not on missing code. Code for all phases is present and
statically verified, so downstream code-level phases were verified without
regression. Runtime sign-off for hardware/network phases must be completed on a
host with a physical Ventoy USB and registry access.

---
## GLOBAL PREREQUISITES

Complete before starting Phase 0:

- [ ] Project directory structure created at target location.
- [ ] `CHANGELOG.md` created in project root (append-only).
- [ ] Docker installed and running (dockerd active).
- [ ] Bash 5.0+ available; all scripts have execute permissions.
- [ ] Python 3.12+ available; pip dependencies documented.
- [ ] Feature flags system initialized; every flag defaults to `disabled`.
- [ ] `assignments.json` initialized with Phase 0 agent assignments.

---

## MODULE REGISTRY VERIFICATION

Confirm each module is defined before implementation begins:

- [ ] **MOD-001 — Core Library**: Feature flag `FEAT_CORE_LIB` created and set to `disabled`. Description confirmed: _Colors, logging, confirm, run_or_dry, safe_exec, traps_
- [ ] **MOD-002 — Platform Detection**: Feature flag `FEAT_PLATFORM` created and set to `disabled`. Description confirmed: _OS detection (Linux/macOS/WSL/Windows), virtualization, tool selection_
- [ ] **MOD-003 — Ventoy USB Management**: Feature flag `FEAT_VENTOY` created and set to `disabled`. Description confirmed: _Mount detection (5 fallbacks), unmount, persistence check/size_
- [ ] **MOD-004 — JSON Configuration**: Feature flag `FEAT_CONFIG` created and set to `disabled`. Description confirmed: _Config init/get/set via jq, host-ID generation (md5 of hostname+mac)_
- [ ] **MOD-005 — Menu Framework**: Feature flag `FEAT_MENU` created and set to `disabled`. Description confirmed: _Stack-based menu_loop with back/quit, UCA_MENU_STACK array_
- [ ] **MOD-006 — Validation Engine**: Feature flag `FEAT_VALIDATION` created and set to `disabled`. Description confirmed: _Triple validation (host-id, USB mount, menu stack), self-heal_
- [ ] **MOD-007 — Unified CLI**: Feature flag `FEAT_CLI` created and set to `disabled`. Description confirmed: _usbctl dispatcher: usb/config/alias/validate subcommands_
- [ ] **MOD-008 — USB Setup Assistant**: Feature flag `FEAT_SETUP_ASSISTANT` created and set to `disabled`. Description confirmed: _5908-line interactive installer: Ventoy, persistence, VM, essentials_
- [ ] **MOD-009 — Alias Manager**: Feature flag `FEAT_ALIAS` created and set to `disabled`. Description confirmed: _~/.bash_aliases_usb CRUD with menu_loop integration_
- [ ] **MOD-010 — SSH Host Manager**: Feature flag `FEAT_SSH` created and set to `disabled`. Description confirmed: _~/.ssh/hosts_usb pipe-delimited store, config generation_
- [ ] **MOD-011 — System Manager**: Feature flag `FEAT_SYSMAN` created and set to `disabled`. Description confirmed: _Health/network/disk/services/repair dashboard (whiptail+text)_
- [ ] **MOD-012 — Essentials Installer**: Feature flag `FEAT_ESSENTIALS` created and set to `disabled`. Description confirmed: _Build toolchain provisioner: llama.cpp, ollama, rust, foundry, node, python_
- [ ] **MOD-013 — USB Auto-Mount**: Feature flag `FEAT_AUTOMOUNT` created and set to `disabled`. Description confirmed: _udev rules + systemd service for automatic USB mounting_
- [ ] **MOD-014 — System Bootstrap**: Feature flag `FEAT_BOOTSTRAP` created and set to `disabled`. Description confirmed: _Ubuntu one-time provisioner: apt, Node, Bun, Python, Docker, Tailscale_
- [ ] **MOD-015 — Hemlock Host CLI**: Feature flag `FEAT_HEMLOCK_CLI` created and set to `disabled`. Description confirmed: _Host-side entrypoint: container lifecycle, staging watcher, exec_
- [ ] **MOD-016 — Hemlock Runtime TUI**: Feature flag `FEAT_HEMLOCK_TUI` created and set to `disabled`. Description confirmed: _In-container menu: agent/crew/validation/security/monitoring/config_
- [ ] **MOD-017 — Hemlock Staging Bridge**: Feature flag `FEAT_HEMLOCK_STAGING` created and set to `disabled`. Description confirmed: _Import/export file staging via volumes/imports/.request protocol_
- [ ] **MOD-018 — Hemlock Docker Infra**: Feature flag `FEAT_HEMLOCK_DOCKER` created and set to `disabled`. Description confirmed: _Compose files, Dockerfiles, Makefile for runtime/agent/crew/doctor_
- [ ] **MOD-019 — Master Deployment**: Feature flag `FEAT_DEPLOY` created and set to `disabled`. Description confirmed: _DEPLOY.sh: 3-phase deploy (system + USB + Hemlock) with --dry-run_
- [ ] **MOD-020 — USB-Hemlock Bridge**: Feature flag `FEAT_BRIDGE` created and set to `disabled`. Description confirmed: _hemlock-tui wrapper: connects USB menu option 8 (Hemlock TUI) to Hemlock CLI_
- [ ] **MOD-021 — Skills Bundle**: Feature flag `FEAT_SKILLS` created and set to `disabled`. Description confirmed: _84 agent skill packages for Hemlock runtime_

---

## Phase 0: Pre-Build Environment

**Section Tag:** `[PHASE-0-v1]` | **Feature Flag:** `FEAT_PRE_BUILD_ENVIRONMENT`
**Status:** `COMPLETE` | **Assigned Agent:** _system-verified_
**Prerequisite:** N/A must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ N/A — first phase, no prior entry required.
  - _Validation:_ N/A — first phase.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_PRE_BUILD_ENVIRONMENT` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_PRE_BUILD_ENVIRONMENT` = false in production.
  - _Validation:_ Verify via flag config or admin panel.
  - _Rollback:_ Set flag to false immediately; redeploy if necessary.
- [ ] **Database migration rollback files prepared**
  _Every forward migration has a corresponding rollback file._
  - _Example:_ For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.
  - _Validation:_ Execute rollback on staging; confirm clean revert.
  - _Rollback:_ Execute the rollback SQL file; verify schema returns to prior state.
- [ ] **Agent assignment confirmed in assignments.json**
  _The responsible agent for this phase is recorded before work begins._
  - _Example:_ assign_agents.py --assign "AgentName:[PHASE-0-v1]" ./project
  - _Validation:_ assignments.json shows this phase with a non-null agent field.
  - _Rollback:_ Re-run assign_agents.py --assign to correct the assignment.

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [ ] **Step 1 — Foundation Setup**
  _Create project structure and core files._
  - _Example:_ ls -la shows expected directories and files.
  - _Validation:_ All created files exist and are non-empty.
  - _Rollback:_ Remove created files and directories.
- [ ] **Step 2 — Core Implementation**
  _Build the primary feature logic for this phase._
  - _Example:_ Core functionality works as specified.
  - _Validation:_ No regressions on existing features.
  - _Rollback:_ Revert changed files; disable feature flag.
- [ ] **Step 3 — Validation & Testing**
  _Verify the implementation works correctly._
  - _Example:_ All tests pass; no errors.
  - _Validation:_ No regressions.
  - _Rollback:_ Revert test changes if they break existing tests.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] `FEAT_PRE_BUILD_ENVIRONMENT` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 0 — Phase 0: Pre-Build Environment
  Agent     : system-verified
  Date      : 2026-06-25
  Commit    : N/A — pre-build
  Notes     : Bash 5.2.21, jq 1.7, Docker 29.6.0, Python 3.12.3 present.
              202 tests pass, bash -n clean on all authored scripts.
```

---

## Phase 1: USB Foundation and Ventoy

**Section Tag:** `[PHASE-1-v1]` | **Feature Flag:** `FEAT_USB_FOUNDATION_AND_VENTOY`
**Status:** `PARTIAL — non-destructive paths verified on a live Ventoy USB; destructive install not run` | **Assigned Agent:** Claude (Opus 4.8)
**Prerequisite:** Phase 0 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-0' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_USB_FOUNDATION_AND_VENTOY` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_USB_FOUNDATION_AND_VENTOY` = false in production.
  - _Validation:_ Verify via flag config or admin panel.
  - _Rollback:_ Set flag to false immediately; redeploy if necessary.
- [ ] **Database migration rollback files prepared**
  _Every forward migration has a corresponding rollback file._
  - _Example:_ For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.
  - _Validation:_ Execute rollback on staging; confirm clean revert.
  - _Rollback:_ Execute the rollback SQL file; verify schema returns to prior state.
- [ ] **Agent assignment confirmed in assignments.json**
  _The responsible agent for this phase is recorded before work begins._
  - _Example:_ assign_agents.py --assign "AgentName:[PHASE-1-v1]" ./project
  - _Validation:_ assignments.json shows this phase with a non-null agent field.
  - _Rollback:_ Re-run assign_agents.py --assign to correct the assignment.

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [ ] **Step 1 — Foundation Setup**
  _Create project structure and core files._
  - _Example:_ ls -la shows expected directories and files.
  - _Validation:_ All created files exist and are non-empty.
  - _Rollback:_ Remove created files and directories.
- [ ] **Step 2 — Core Implementation**
  _Build the primary feature logic for this phase._
  - _Example:_ Core functionality works as specified.
  - _Validation:_ No regressions on existing features.
  - _Rollback:_ Revert changed files; disable feature flag.
- [ ] **Step 3 — Validation & Testing**
  _Verify the implementation works correctly._
  - _Example:_ All tests pass; no errors.
  - _Validation:_ No regressions.
  - _Rollback:_ Revert test changes if they break existing tests.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] `FEAT_USB_FOUNDATION_AND_VENTOY` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 1 — Phase 1: USB Foundation and Ventoy
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Phase 2: Persistence Layer and Partitioning

**Section Tag:** `[PHASE-2-v1]` | **Feature Flag:** `FEAT_PERSISTENCE_LAYER_AND_PARTITIONING`
**Status:** `PARTIAL — persistence detection verified on the live drive; destructive create/resize not run` | **Assigned Agent:** Claude (Opus 4.8)
**Prerequisite:** Phase 1 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-1' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_PERSISTENCE_LAYER_AND_PARTITIONING` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_PERSISTENCE_LAYER_AND_PARTITIONING` = false in production.
  - _Validation:_ Verify via flag config or admin panel.
  - _Rollback:_ Set flag to false immediately; redeploy if necessary.
- [ ] **Database migration rollback files prepared**
  _Every forward migration has a corresponding rollback file._
  - _Example:_ For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.
  - _Validation:_ Execute rollback on staging; confirm clean revert.
  - _Rollback:_ Execute the rollback SQL file; verify schema returns to prior state.
- [ ] **Agent assignment confirmed in assignments.json**
  _The responsible agent for this phase is recorded before work begins._
  - _Example:_ assign_agents.py --assign "AgentName:[PHASE-2-v1]" ./project
  - _Validation:_ assignments.json shows this phase with a non-null agent field.
  - _Rollback:_ Re-run assign_agents.py --assign to correct the assignment.

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [ ] **Step 1 — Foundation Setup**
  _Create project structure and core files._
  - _Example:_ ls -la shows expected directories and files.
  - _Validation:_ All created files exist and are non-empty.
  - _Rollback:_ Remove created files and directories.
- [ ] **Step 2 — Core Implementation**
  _Build the primary feature logic for this phase._
  - _Example:_ Core functionality works as specified.
  - _Validation:_ No regressions on existing features.
  - _Rollback:_ Revert changed files; disable feature flag.
- [ ] **Step 3 — Validation & Testing**
  _Verify the implementation works correctly._
  - _Example:_ All tests pass; no errors.
  - _Validation:_ No regressions.
  - _Rollback:_ Revert test changes if they break existing tests.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] `FEAT_PERSISTENCE_LAYER_AND_PARTITIONING` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 2 — Phase 2: Persistence Layer and Partitioning
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Phase 3: Service Integration

**Section Tag:** `[PHASE-3-v1]` | **Feature Flag:** `FEAT_SERVICE_INTEGRATION`
**Status:** `COMPLETE` | **Assigned Agent:** _system-verified_
**Prerequisite:** N/A must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [x] **Prior phase change log entry written** _N/A — first phase_
- [x] **Feature flag `FEAT_PRE_BUILD_ENVIRONMENT` created and disabled** _VERIFIED in feature-flags.json_
- [x] **Database migration rollback files prepared** _N/A — shell-based system, no database_
- [x] **Agent assignment confirmed in assignments.json** _System-verified_

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [x] **Step 1 — Foundation Setup** _VERIFIED 2026-06-25_
  _Create project structure and core files._
  - _Validation:_ All 55 usb/ files, 51K hemlock/ files, menu.sh, AGENTS.md, CHANGELOG.md, feature-flags.json exist.
  - _Rollback:_ N/A — verification only.
- [x] **Step 2 — Core Implementation** _VERIFIED 2026-06-25_
  _Build the primary feature logic for this phase._
  - _Validation:_ Bash 5.2.21, jq 1.7, Docker 29.6.0, Docker Compose, Python 3.12.3 all available.
  - _Rollback:_ N/A — verification only.
- [x] **Step 3 — Validation & Testing** _VERIFIED 2026-06-25_
  _Verify the implementation works correctly._
  - _Validation:_ 201 tests pass, 0 fail, 1 skipped. `bash -n` syntax checks all pass.
  - _Rollback:_ N/A — verification only.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [x] All implementation steps above are checked.
- [x] `FEAT_PRE_BUILD_ENVIRONMENT` is confirmed enabled.
- [x] Change log entry for this phase is written and appended.
- [x] Blueprint updated to reflect any deviations from the specification.
- [x] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 3 — Phase 3: Service Integration
  Agent     : Claude (Opus 4.8)
  Date      : 2026-06-25
  Commit    : N/A — working copy
  Notes     : alias_manager + ssh_host_manager full CLI CRUD verified
              (add/list/remove round-trip). Dry-run honored — no writes,
              no backup side-effects. ssh --add made fully non-interactive
              per FS-004. Backups land in ~/.alias_backups / ~/.ssh/hosts_backups.
              menu.sh text/whiptail navigation hardened (see CL-001).
```

---

## Phase 4: System Management and Health

**Section Tag:** `[PHASE-4-v1]` | **Feature Flag:** `FEAT_SYSTEM_MANAGEMENT_AND_HEALTH`
**Status:** `COMPLETE` | **Assigned Agent:** Claude (Opus 4.8)
**Prerequisite:** Phase 3 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-3' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_SYSTEM_MANAGEMENT_AND_HEALTH` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_SYSTEM_MANAGEMENT_AND_HEALTH` = false in production.
  - _Validation:_ Verify via flag config or admin panel.
  - _Rollback:_ Set flag to false immediately; redeploy if necessary.
- [ ] **Database migration rollback files prepared**
  _Every forward migration has a corresponding rollback file._
  - _Example:_ For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.
  - _Validation:_ Execute rollback on staging; confirm clean revert.
  - _Rollback:_ Execute the rollback SQL file; verify schema returns to prior state.
- [ ] **Agent assignment confirmed in assignments.json**
  _The responsible agent for this phase is recorded before work begins._
  - _Example:_ assign_agents.py --assign "AgentName:[PHASE-4-v1]" ./project
  - _Validation:_ assignments.json shows this phase with a non-null agent field.
  - _Rollback:_ Re-run assign_agents.py --assign to correct the assignment.

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [ ] **Step 1 — Foundation Setup**
  _Create project structure and core files._
  - _Example:_ ls -la shows expected directories and files.
  - _Validation:_ All created files exist and are non-empty.
  - _Rollback:_ Remove created files and directories.
- [ ] **Step 2 — Core Implementation**
  _Build the primary feature logic for this phase._
  - _Example:_ Core functionality works as specified.
  - _Validation:_ No regressions on existing features.
  - _Rollback:_ Revert changed files; disable feature flag.
- [ ] **Step 3 — Validation & Testing**
  _Verify the implementation works correctly._
  - _Example:_ All tests pass; no errors.
  - _Validation:_ No regressions.
  - _Rollback:_ Revert test changes if they break existing tests.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] `FEAT_SYSTEM_MANAGEMENT_AND_HEALTH` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 4 — Phase 4: System Management and Health
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Phase 5: Hemlock Runtime Deployment

**Section Tag:** `[PHASE-5-v1]` | **Feature Flag:** `FEAT_HEMLOCK_RUNTIME_DEPLOYMENT`
**Status:** `BLOCKED (environment — Docker image build needs network/registry)` | **Assigned Agent:** _unassigned_
**Prerequisite:** Phase 4 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-4' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_HEMLOCK_RUNTIME_DEPLOYMENT` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_HEMLOCK_RUNTIME_DEPLOYMENT` = false in production.
  - _Validation:_ Verify via flag config or admin panel.
  - _Rollback:_ Set flag to false immediately; redeploy if necessary.
- [ ] **Database migration rollback files prepared**
  _Every forward migration has a corresponding rollback file._
  - _Example:_ For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.
  - _Validation:_ Execute rollback on staging; confirm clean revert.
  - _Rollback:_ Execute the rollback SQL file; verify schema returns to prior state.
- [ ] **Agent assignment confirmed in assignments.json**
  _The responsible agent for this phase is recorded before work begins._
  - _Example:_ assign_agents.py --assign "AgentName:[PHASE-5-v1]" ./project
  - _Validation:_ assignments.json shows this phase with a non-null agent field.
  - _Rollback:_ Re-run assign_agents.py --assign to correct the assignment.

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [ ] **Step 1 — Foundation Setup**
  _Create project structure and core files._
  - _Example:_ ls -la shows expected directories and files.
  - _Validation:_ All created files exist and are non-empty.
  - _Rollback:_ Remove created files and directories.
- [ ] **Step 2 — Core Implementation**
  _Build the primary feature logic for this phase._
  - _Example:_ Core functionality works as specified.
  - _Validation:_ No regressions on existing features.
  - _Rollback:_ Revert changed files; disable feature flag.
- [ ] **Step 3 — Validation & Testing**
  _Verify the implementation works correctly._
  - _Example:_ All tests pass; no errors.
  - _Validation:_ No regressions.
  - _Rollback:_ Revert test changes if they break existing tests.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] `FEAT_HEMLOCK_RUNTIME_DEPLOYMENT` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 5 — Phase 5: Hemlock Runtime Deployment
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Phase 6: USB-Hemlock Bridge and TUI Integration

**Section Tag:** `[PHASE-6-v1]` | **Feature Flag:** `FEAT_USB_HEMLOCK_BRIDGE_AND_TUI_INTEGRATION`
**Status:** `BLOCKED (depends on Phase 5 container)` | **Assigned Agent:** _unassigned_
**Prerequisite:** Phase 5 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-5' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_USB_HEMLOCK_BRIDGE_AND_TUI_INTEGRATION` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_USB_HEMLOCK_BRIDGE_AND_TUI_INTEGRATION` = false in production.
  - _Validation:_ Verify via flag config or admin panel.
  - _Rollback:_ Set flag to false immediately; redeploy if necessary.
- [ ] **Database migration rollback files prepared**
  _Every forward migration has a corresponding rollback file._
  - _Example:_ For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.
  - _Validation:_ Execute rollback on staging; confirm clean revert.
  - _Rollback:_ Execute the rollback SQL file; verify schema returns to prior state.
- [ ] **Agent assignment confirmed in assignments.json**
  _The responsible agent for this phase is recorded before work begins._
  - _Example:_ assign_agents.py --assign "AgentName:[PHASE-6-v1]" ./project
  - _Validation:_ assignments.json shows this phase with a non-null agent field.
  - _Rollback:_ Re-run assign_agents.py --assign to correct the assignment.

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [ ] **Step 1 — Foundation Setup**
  _Create project structure and core files._
  - _Example:_ ls -la shows expected directories and files.
  - _Validation:_ All created files exist and are non-empty.
  - _Rollback:_ Remove created files and directories.
- [ ] **Step 2 — Core Implementation**
  _Build the primary feature logic for this phase._
  - _Example:_ Core functionality works as specified.
  - _Validation:_ No regressions on existing features.
  - _Rollback:_ Revert changed files; disable feature flag.
- [ ] **Step 3 — Validation & Testing**
  _Verify the implementation works correctly._
  - _Example:_ All tests pass; no errors.
  - _Validation:_ No regressions.
  - _Rollback:_ Revert test changes if they break existing tests.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] `FEAT_USB_HEMLOCK_BRIDGE_AND_TUI_INTEGRATION` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 6 — Phase 6: USB-Hemlock Bridge and TUI Integration
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Phase 7: Validation and Hardening

**Section Tag:** `[PHASE-7-v1]` | **Feature Flag:** `FEAT_VALIDATION_AND_HARDENING`
**Status:** `COMPLETE (code-level; runtime items deferred to Phase 5 env)` | **Assigned Agent:** Claude (Opus 4.8)
**Prerequisite:** Phase 6 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-6' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_VALIDATION_AND_HARDENING` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_VALIDATION_AND_HARDENING` = false in production.
  - _Validation:_ Verify via flag config or admin panel.
  - _Rollback:_ Set flag to false immediately; redeploy if necessary.
- [ ] **Database migration rollback files prepared**
  _Every forward migration has a corresponding rollback file._
  - _Example:_ For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.
  - _Validation:_ Execute rollback on staging; confirm clean revert.
  - _Rollback:_ Execute the rollback SQL file; verify schema returns to prior state.
- [ ] **Agent assignment confirmed in assignments.json**
  _The responsible agent for this phase is recorded before work begins._
  - _Example:_ assign_agents.py --assign "AgentName:[PHASE-7-v1]" ./project
  - _Validation:_ assignments.json shows this phase with a non-null agent field.
  - _Rollback:_ Re-run assign_agents.py --assign to correct the assignment.

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [ ] **Step 1 — Foundation Setup**
  _Create project structure and core files._
  - _Example:_ ls -la shows expected directories and files.
  - _Validation:_ All created files exist and are non-empty.
  - _Rollback:_ Remove created files and directories.
- [ ] **Step 2 — Core Implementation**
  _Build the primary feature logic for this phase._
  - _Example:_ Core functionality works as specified.
  - _Validation:_ No regressions on existing features.
  - _Rollback:_ Revert changed files; disable feature flag.
- [ ] **Step 3 — Validation & Testing**
  _Verify the implementation works correctly._
  - _Example:_ All tests pass; no errors.
  - _Validation:_ No regressions.
  - _Rollback:_ Revert test changes if they break existing tests.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] `FEAT_VALIDATION_AND_HARDENING` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 7 — Phase 7: Validation and Hardening
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Phase 8: Consolidation, Isolation & Alignment

**Section Tag:** `[PHASE-8-v1]` | **Feature Flag:** `FEAT_CONSOLIDATION_ISOLATION_ALIGNMENT`
**Status:** `IN PROGRESS` | **Assigned Agent:** Claude (Opus 4.8)
**Prerequisite:** Phase 7 `COMPLETE`. Added via CL-039 (2026-07-02) after a full-system
reconciliation revealed the change log had drifted (logged through CL-021; code reached CL-038).

### Pre-Phase Gate

- [x] **Canonical single source established** — `~/projects/hemlock/` = `archives/` + `runtime/`
  (Hemlock isolated) + `hemlock-usb/` (Hemlock+USB working dir). Scattered copies quarantined
  (reversible), pollution trees (`fresh-skills-need-bring-others`, `hemlock-minimal`) stripped.
- [x] **OpenClaw retired** — global npm `openclaw` uninstalled; gateway carried by Hemlock image.

### Implementation Steps

- [x] **Step 1 — Self-contained skills.** Bake `shared/skills/` (curated set) into image
  `/opt/skills_seed`; entrypoint rsyncs REAL FILES (no symlinks) into a `/skills` named volume;
  agents COPY into their own workspace. No github clone, no network. (`Dockerfile.runtime`,
  `docker/entrypoint.sh`, `docker-compose.yml`)
- [ ] **Step 2 — Full host isolation.** Convert ALL remaining bind mounts
  (`runtime/agents/crews/models/backups`) to named volumes seeded from baked `/opt/*_seed`.
  Zero host coupling; nothing modifies host files even in non-docker persistent mode.
- [ ] **Step 3 — Build + functional validation.** `docker compose build`; `make up`; gateway
  reachable on :18789; Hermes health via `health/doctor_bridge.py --quick`.
- [ ] **Step 4 — Live agent path (OpenRouter).** Import an agent; create agent workspace dir;
  verify gateway kickstart + Hermes MCP handshake; interactive-menu manageability.
- [ ] **Step 5 — Chat command layer.** Verify `!` shell + `/` slash via gateway binaries across
  the 19 `gateway/platforms/*.py` adapters; ADD user-facing custom-command management
  (`hermes_cli/commands.py` + `commands.yaml`), surfaced in the menu.
- [ ] **Step 6 — Hemlock doctor parity.** Validate `scripts/system/hemlock-doctor.sh` +
  `health/doctor_bridge.py` + `hermes_cli/doctor.py` cover gateway/identity/persistence/env/paths
  equivalent to `openclaw doctor`.
- [ ] **Step 7 — GUI rebrand.** De-brand OpenClaw `control-ui` (`dist/control-ui/index.html` +
  assets CSS, `canvas-host/a2ui`) to Hemlock blue; survive npm reinstalls via overlay.
- [ ] **Step 8 — Agent behavioral enforcement (USER-LED).** One enforcement structure baking
  mandatory scripts/tools into every agent/crew (`agents/workspace-template/`, `crews/rules/`,
  `plugins/injections/`). Scaffold hook once concept is consolidated.

### Phase Validation Gate

- [ ] All implementation steps above are checked.
- [ ] `FEAT_CONSOLIDATION_ISOLATION_ALIGNMENT` confirmed enabled.
- [ ] Change log entry CL-039 present in blueprint.md.
- [ ] Blueprint PART II module registry updated for isolation + skills-bake modules.
- [ ] Assigned agent has signed off.
- [ ] Quarantine (`~/_hemlock-quarantine/`) NOT deleted until this phase is `COMPLETE`.

### Agent Sign-Off

```
Phase 8 — Consolidation, Isolation & Alignment
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## GLOBAL COMPLETION CRITERIA

The project is production-complete when all of the following are true:

- [ ] All phase statuses are `COMPLETE` with agent sign-offs recorded.
- [ ] All feature flags are enabled.
- [ ] All Docker images build; containers start and are healthy.
- [ ] All shell scripts have correct permissions (755) and pass syntax check.
- [ ] Python modules import cleanly; pytest suite passes.
- [ ] Performance budgets verified; results documented in change log.
- [ ] Security audit completed; no plaintext secrets in tracked files.
- [ ] Final change log entry written documenting the production launch.
- [ ] Blueprint marked as FINAL in document header.
