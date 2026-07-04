# Hemlock Enterprise Agent Framework — ENTERPRISE CHECKLIST
## Coexists with: blueprint.md
### Generated: 2026-06-11

> **CHECKLIST AUTHORITY**
> This checklist enforces blueprint.md. It must not diverge — every
> blueprint amendment requires a corresponding checklist update in the
> same commit. Checked items are immutable; corrections require a new
> line with explanation, never erasure of a checked item.
>
> **Status values:** `NOT STARTED` | `IN PROGRESS` | `BLOCKED` | `COMPLETE`
> **Blocking rule:** No phase may begin until the prior phase is `COMPLETE`.

---
## GLOBAL PREREQUISITES

Complete before starting Phase 0:

- [ ] Project directory structure created at target location.
- [ ] `CHANGELOG.md` created in project root (append-only).
- [ ] Feature flags system initialized; every flag defaults to `disabled`.
- [ ] `assignments.json` initialized with Phase 0 agent assignments.

---

## Foundation

**Section Tag:** `[PHASE-0-v1]` | **Feature Flag:** `FEAT_FOUNDATION`
**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_
**Prerequisite:** N/A must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ N/A — first phase, no prior entry required.
  - _Validation:_ N/A — first phase.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_FOUNDATION` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_FOUNDATION` = false in production.
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

- [ ] **Step 1 — [Define deliverable 1]**
  - _Example:_ Verify: confirm '[Define deliverable 1]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.
- [ ] **Step 2 — [Define deliverable 2]**
  - _Example:_ Verify: confirm '[Define deliverable 2]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.
- [ ] `FEAT_FOUNDATION` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 0 — Foundation
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Core

**Section Tag:** `[PHASE-1-v1]` | **Feature Flag:** `FEAT_CORE`
**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_
**Prerequisite:** Phase 0 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-0' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_CORE` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_CORE` = false in production.
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

- [ ] **Step 1 — [Define deliverable 1]**
  - _Example:_ Verify: confirm '[Define deliverable 1]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.
- [ ] **Step 2 — [Define deliverable 2]**
  - _Example:_ Verify: confirm '[Define deliverable 2]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.
- [ ] `FEAT_CORE` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 1 — Core
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Gateway

**Section Tag:** `[PHASE-2-v1]` | **Feature Flag:** `FEAT_GATEWAY`
**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_
**Prerequisite:** Phase 1 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-1' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_GATEWAY` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_GATEWAY` = false in production.
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

- [ ] **Step 1 — [Define deliverable 1]**
  - _Example:_ Verify: confirm '[Define deliverable 1]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.
- [ ] **Step 2 — [Define deliverable 2]**
  - _Example:_ Verify: confirm '[Define deliverable 2]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.
- [ ] `FEAT_GATEWAY` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 2 — Gateway
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Agents

**Section Tag:** `[PHASE-3-v1]` | **Feature Flag:** `FEAT_AGENTS`
**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_
**Prerequisite:** Phase 2 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-2' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_AGENTS` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_AGENTS` = false in production.
  - _Validation:_ Verify via flag config or admin panel.
  - _Rollback:_ Set flag to false immediately; redeploy if necessary.
- [ ] **Database migration rollback files prepared**
  _Every forward migration has a corresponding rollback file._
  - _Example:_ For each `YYYYMMDD_NNN_description.sql`, a `_ROLLBACK.sql` exists.
  - _Validation:_ Execute rollback on staging; confirm clean revert.
  - _Rollback:_ Execute the rollback SQL file; verify schema returns to prior state.
- [ ] **Agent assignment confirmed in assignments.json**
  _The responsible agent for this phase is recorded before work begins._
  - _Example:_ assign_agents.py --assign "AgentName:[PHASE-3-v1]" ./project
  - _Validation:_ assignments.json shows this phase with a non-null agent field.
  - _Rollback:_ Re-run assign_agents.py --assign to correct the assignment.

### Implementation Steps

> Every step must be completed, tested, and individually logged before proceeding to the next.

- [ ] **Step 1 — [Define deliverable 1]**
  - _Example:_ Verify: confirm '[Define deliverable 1]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.
- [ ] **Step 2 — [Define deliverable 2]**
  - _Example:_ Verify: confirm '[Define deliverable 2]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.
- [ ] `FEAT_AGENTS` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 3 — Agents
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Security

**Section Tag:** `[PHASE-4-v1]` | **Feature Flag:** `FEAT_SECURITY`
**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_
**Prerequisite:** Phase 3 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-3' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_SECURITY` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_SECURITY` = false in production.
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

- [ ] **Step 1 — [Define deliverable 1]**
  - _Example:_ Verify: confirm '[Define deliverable 1]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.
- [ ] **Step 2 — [Define deliverable 2]**
  - _Example:_ Verify: confirm '[Define deliverable 2]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.
- [ ] `FEAT_SECURITY` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 4 — Security
  Agent     : _________________
  Date      : _________________
  Commit    : _________________
  Notes     : _________________
```

---

## Launch

**Section Tag:** `[PHASE-5-v1]` | **Feature Flag:** `FEAT_LAUNCH`
**Status:** `NOT STARTED` | **Assigned Agent:** _unassigned_
**Prerequisite:** Phase 4 must be `COMPLETE` with change log entry written.

### Pre-Phase Gate

Confirm all of the following before any work begins on this phase:

- [ ] **Prior phase change log entry written**
  _The CL entry for the preceding phase is appended to CHANGELOG.md._
  - _Example:_ grep 'PHASE-4' CHANGELOG.md returns at least one entry.
  - _Validation:_ Entry is present and contains all required fields.
  - _Rollback:_ N/A — this is a gate check, not a code change.
- [ ] **Feature flag `FEAT_LAUNCH` created and disabled**
  _The flag must exist before any Phase code ships._
  - _Example:_ Flag `FEAT_LAUNCH` = false in production.
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

- [ ] **Step 1 — [Define deliverable 1]**
  - _Example:_ Verify: confirm '[Define deliverable 1]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.
- [ ] **Step 2 — [Define deliverable 2]**
  - _Example:_ Verify: confirm '[Define deliverable 2]' is complete.
  - _Validation:_ Deliverable is present and functional.
  - _Rollback:_ Revert changes from this step.

### Phase Validation Gate

All of the following must be true before this phase is marked `COMPLETE`:

- [ ] All implementation steps above are checked.
- [ ] No phase may begin until all prior checklist items are verified complete, all tests pass in CI, and a change log entry is appended.
- [ ] `FEAT_LAUNCH` is confirmed enabled.
- [ ] Change log entry for this phase is written and appended.
- [ ] Blueprint updated to reflect any deviations from the specification.
- [ ] Assigned agent has signed off (name + date in block below).

### Agent Sign-Off

```
Phase 5 — Launch
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
- [ ] Performance budgets verified; results documented in change log.
- [ ] Security audit completed; no plaintext secrets in tracked files.
- [ ] Final change log entry written documenting the production launch.
- [ ] Blueprint marked as FINAL in document header.
