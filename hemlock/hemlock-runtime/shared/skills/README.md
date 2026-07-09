# Hemlock Curated Skills

**The canonical, version-tracked, self-enforcing source of truth for every curated skill the Hemlock agent runtime uses.**

This repository is not a loose folder of scripts. It is a governed skill database: every skill in it has passed an enforced validation-and-packaging loop, is pinned by a git hash, is recorded in a signed/verifiable manifest, and is auto-committed the moment its version changes. The container that runs Hemlock agents mirrors this repository into a read-only skills seed and pulls the latest **every day**, so agents always reference a consistent, current, diagnostic set of tools.

---

## Table of Contents

- [What this repository is](#what-this-repository-is)
- [Design philosophy](#design-philosophy--portable-diagnostic-multifunctional-isolated)
- [Skill anatomy](#skill-anatomy--the-structure-standard)
- [The three-tool system](#the-three-tool-system)
  - [1. skill-creator — the creator](#1-skill-creator--the-creator)
  - [2. skill-installer — the installer](#2-skill-installer--the-installer)
  - [3. guardrail-enforcement — the enforcer](#3-guardrail-enforcement--the-enforcer)
- [Packaging — the method](#packaging--the-method)
- [Enforcement — how integrity is guaranteed](#enforcement--how-integrity-is-guaranteed)
- [Validation — what "valid" means](#validation--what-valid-means)
- [Versioning &amp; the manifest](#versioning--the-manifest)
- [The canonical git workflow](#the-canonical-git-workflow)
- [Daily auto-update inside the container](#daily-auto-update-inside-the-container)
- [Skill catalog](#skill-catalog)
- [Tags &amp; tooling metadata](#tags--tooling-metadata)
- [Adding or updating a skill](#adding-or-updating-a-skill)
- [License](#license)

---

## What this repository is

- **The single canonical authority** for curated, validated, finalized skills. Not just an initial set — every skill we curate and finalize is migrated in here and version-tracked from then on.
- **The upstream the Hemlock image mirrors.** Finalized skills are copied (real files, never symlinks) into the container image's baked `shared/skills` seed. On first run the container seeds a writable `/skills` volume from that read-only seed; **agents copy** skills into their own workspace rather than mutating the shared set.
- **Self-governing.** The [`guardrail-enforcement`](guardrail-enforcement/) skill lives inside this very repo and watches, enforces, signs, and version-tracks every change to it. The repository polices itself.

## Design philosophy — portable, diagnostic, multifunctional, isolated

Every skill here is built to the same non-negotiable principles:

| Principle | What it means in practice |
|---|---|
| **Path-agnostic** | No hardcoded absolute paths in executable scripts. Everything resolves from arguments, `$HOME`, environment variables, or the script's own location. A skill works identically on any host, any mount, any USB. The validator *enforces* this. |
| **Free-first ($0)** | Every script is Python 3.8+ **standard library only** — zero `pip` installs, zero paid services. Escalation to paid tiers is documented but never required. |
| **Provider-agnostic** | Skills declare `providers: [openai, claude, mistral, gemini, hermes, copilot, any]`. Nothing is bound to one model vendor. |
| **Isolated** | No host-filesystem coupling, no bind mounts, **no symlinks anywhere**. Skills are baked read-only; agents copy what they need. A skill can never modify the machine it runs on outside its own workspace. |
| **Diagnostic &amp; multifunctional** | Each skill is a self-contained tool that reports structured JSON (`{operation, status, cost, ...}`), supports `--dry-run` where it mutates, and `--json` for machine consumption — usable interactively, in CI, or driven by an agent. |
| **Self-verifying** | The manifest, the on-disk files, and git's content hashes are cross-checked so drift is impossible to hide. |

## Skill anatomy — the structure standard

Every skill is a directory with **exactly five root items**:

```
<skill-name>/
├── SKILL.md            # frontmatter + documentation (the only SKILL.md in the skill)
├── __init__.py         # scaffolder / integrator entry point
├── scripts/            # executable tools (.py/.sh) — no .md files here
├── references/         # documentation (.md) the skill loads on demand
└── <skill-name>.skill  # the packaged, distributable archive
```

`SKILL.md` frontmatter is the contract:

```yaml
---
name: <skill-name>
description: "What it does + when to use it + trigger phrases."
license: MIT
metadata:
  tags: [ ... ]          # 5+ (basic tier) or 7+ (enterprise tier)  <-- the enforced field
  openclaw: { tags: [...], category: ..., priority: ... }
  hermes:   { tags: [...], category: ..., related_skills: [...] }
  providers: [openai, claude, mistral, gemini, hermes, copilot, any]
version: X.Y.Z           # semantic version — the field the guardrail watches
---
```

Two tiers: **basic** (≥5 tags, ≥1 script, ≥3 references) and **enterprise** (≥7 tags, ≥3 substantive scripts, ≥5 substantive references, provider matrix, error/​safety sections). The skills in this repo target enterprise tier.

## The three-tool system

The whole lifecycle — create → validate → package → install → enforce — is covered by three cooperating tools. They are deliberately **separate** so each can ship and be used alone, yet they compose into a full authoring platform.

| Tool | Role | Where it lives |
|---|---|---|
| **skill-creator** | The **creator** — scaffolds, validates, auto-fixes, packages, and upgrades skills through one enforced loop. | Baked into the Hemlock image `shared/skills`; migrates into this repo as it is re-validated. |
| **skill-installer** | The **installer** — installs `.skill` archives into a target project, agent, or crew, wiring them in without touching the source. | Baked into the Hemlock image `shared/skills`. |
| **guardrail-enforcement** | The **enforcer** — watches versions, auto-commits, gates workflows with a signed audit log, holds advisory locks, and cross-verifies the manifest against git. | **In this repo** ([`guardrail-enforcement/`](guardrail-enforcement/)) — it governs the repo itself. |

### 1. skill-creator — the creator

The authoring engine. Its public read-only tools (`validate.py`, `analyze_skill.py`, `verify_sources.py`, `detect_redundancy.py`) inspect a skill; its orchestrator `skill_enhance.py` runs the **11-step enforced loop** that is the *only* sanctioned way to mutate and package a skill:

1. Update / target the skill
2. Gate: `SKILL.md` frontmatter (tier tags, description, no placeholders)
3. Gate: `scripts/` count
4. Gate: `references/` count
5. Run `validate.py` (informational baseline)
6. Run `auto_fix.py` (safe moves only — **never deletes**)
7. **Re-validate (HARD GATE)** — must pass or the loop stops
8. `test_script.py` — every script must compile, have a shebang, and answer `--help` (BLOCKING)
9. `verify_sources.py` — external-source sanity
10. `package_skills.py` — build the `.skill` archive, bump the version, update the manifest
11. **Extract-verify** — unpack the fresh archive and confirm every file hash matches source (no mutation slipped in)

The creator is kept **pure of enforcement policy** so a `skill-creator.skill` shipped alone is immediately usable with zero policy overhead. The policy lives in the enforcer.

### 2. skill-installer — the installer

Takes a finalized `.skill` archive and installs it into a destination — a project, an agent workspace, or a crew — verifying structure on the way in and never modifying the upstream skill. This is how a curated skill from this repo reaches the place that actually runs it. Combined with the daily container pull, it keeps every agent's toolset current.

### 3. guardrail-enforcement — the enforcer

The governance layer, and itself a skill in this repo. Two composable halves plus supporting integrity tools:

- **Watcher (`monitor.py`)** — a directory-agnostic *condition → action* trigger. Its headline job: watch each skill's `SKILL.md` `version:` and, on a bump, derive the skill name from its own directory and **auto-commit `"<skill_name> version bumped to vX.Y.Z"`** (staging the skill dir + the root manifest in lockstep). New skill directories are **discovered dynamically** on every scan — add a skill and it is tracked immediately, no config change.
- **Gate (`gate.py`)** — enforces a user-defined loop (pre-checks → loop → post-checks) and appends an **HMAC-signed, hash-chained** entry to a tamper-evident audit log only when every stage passes.
- **Lock (`lock.py`)** — an advisory `.loop.lock` marker; cooperating tools (the watcher, the verifier) **skip** a skill that is mid-authoring so half-finished state is never auto-committed.
- **Verifier (`verify_manifest.py`)** — cross-checks the manifest ↔ on-disk `SKILL.md` versions ↔ git's tracked hashes, flags new/uncommitted/mismatched skills, and excuses anything holding a lock.
- **Hooks (`install_hooks.py`)** + **log verifier (`verify_log.py`)** — bind git commits to a valid, signed, recent audit entry, with an interactive front-end (`menu.sh`).

Watcher and gate are **independent but compose**: auto-commit version bumps with the watcher alone, enforce a loop with the gate alone, or point the watcher's action at the gate to chain them.

## Packaging — the method

A skill is distributed as a single `<skill-name>.skill` file — a deterministic archive of its `SKILL.md`, `__init__.py`, `scripts/`, and `references/`. Packaging (`package_skills.py`, step 10 of the loop):

1. Bumps the semantic version.
2. Builds the archive.
3. Records the skill in `.skill-manifest.json` (`current_version`, `previous_version`, `last_packaged`, file count, size, and a version `history`).
4. Is immediately **extract-verified** (step 11): the fresh archive is unpacked to a temp dir and every file's hash is compared against source. A mismatch fails the build — you can never ship an archive that doesn't match its tree.

Because git also stores the byte-level hash of every file, "the package matches the source, the manifest matches the package, and git pins the hash" is a fully closed loop.

## Enforcement — how integrity is guaranteed

Integrity is layered so that no single bypass lands bad or untracked state:

| Layer | Guarantee | Bypass |
|---|---|---|
| **The loop (`skill_enhance.py`)** | The only sanctioned mutation path; hard gates block on any failure. | — |
| **Advisory `.loop.lock`** | Cooperating tools skip mid-authoring skills — no half-baked auto-commits. | A raw `git commit` ignores it — caught by the next layer. |
| **Git pre-commit / pre-push hooks** | Reject commits/pushes without a valid, recent, signed audit entry. | `git commit --no-verify`, which leaves a *visible gap* in the audit trail. |
| **HMAC-signed, hash-chained audit log** | Every gated run is signed; tampering, insertion, deletion, or reordering breaks the chain and fails verification. | Requires the per-machine secret, which never ships in a `.skill`. |
| **Version-bump auto-commit (watcher)** | Every version change becomes a uniform, labelled git commit — consistent tracking + precise rollback. | — |
| **Manifest cross-verification** | Manifest ↔ files ↔ git hashes must reconcile, or the repo is flagged inconsistent. | — |

Historically this began as a `SKILL_LOOP_TOKEN` environment gate on renamed private scripts inside skill-creator; it was refactored out so the creator stays distributable and all enforcement lives in `guardrail-enforcement`. See [`guardrail-enforcement/references/proposed-design.md`](guardrail-enforcement/references/proposed-design.md) for the full rationale.

## Validation — what "valid" means

`skill-creator/scripts/validate.py` scores a skill against the structure standard. Representative checks:

- **Structure** — exactly the five root items; no stray `SKILL.md`; no `.md` in `scripts/`; substantive (non-placeholder) scripts and references.
- **Frontmatter** — `name`, a real `description`, `license`, `metadata.tags` at/above the tier minimum, `version`. No `REPLACE_ME` / TODO placeholders.
- **Path-agnostic (enforced)** — a non-portable-path detector **fails** any executable script containing a machine-specific path (`/home/...`, `/Users/...`, `/media/...`, `/mnt/...`) and **warns** on the same in docs, exempting env-var defaults, comments, and system roots.
- **Angle-bracket / placeholder hygiene** — the description may not contain literal `<...>` placeholders.
- **Tier gates** — enterprise requires ≥7 tags, ≥3 scripts, ≥5 references, plus provider/error/safety coverage.

Validation is the *purpose*: a skill that passes is portable, self-describing, safe to run unattended, and trustworthy for an autonomous agent to pick up and use without a human in the loop.

## Versioning &amp; the manifest

- **Semantic versioning** on every skill's `SKILL.md` `version:` field.
- **`.skill-manifest.json`** at the repo root records each skill's current and previous version, last-packaged timestamp, file count, size, and full version history.
- Every version bump is auto-committed by the watcher, so `git log` is a complete, uniform version history and any version is a `git checkout` away.

## The canonical git workflow

1. Author or update a skill (optionally `lock.py acquire` it first).
2. Run the creator's loop (`skill_enhance.py`) — validate → auto-fix → re-validate → package → extract-verify. The version bumps.
3. `lock.py release` if you locked it.
4. `monitor.py scan` detects the new version and **auto-commits** `"<skill> version bumped to vX.Y.Z"`.
5. `verify_manifest.py` confirms manifest ↔ files ↔ git are consistent.
6. Push. The container picks it up on its next daily sync.

Rollback is `git revert`/`git checkout` of the relevant version commit — clean because each commit is one skill at one version.

## Daily auto-update inside the container

This repository is the upstream for a **daily skills sync** baked into the Hemlock runtime (`docker/skills-auto-update.sh`). Each day the container:

1. Fetches the latest from this repo into a container-internal clone (network-only; no host coupling; fully fail-soft when offline).
2. Version-checks each skill against what it currently has, deciding by content (`rsync --checksum`), so a same-length bump such as `0.1.0 → 0.2.0` is never skipped.
3. Refreshes the `/skills` database with anything new or updated, copied in as **real files** (never symlinks).

Three invariants make the sync safe to run unattended:

- **Control artifacts are never clobbered.** `.git`, `.monitor.json`, `.monitor-state.json`, `.loop.lock`, `.loop-log.jsonl`, `.gate.json` and `__pycache__` are excluded from every sync, so local watcher/gate state and git history survive an upstream pull.
- **Control artifacts are root-only.** After every cycle the updater re-asserts `root:root`, mode `600` on those files (the script itself `755`), so guardrail state cannot be tampered with by a non-root process inside the container.
- **The updater is self-healing.** It runs under a supervisor that restarts the update loop on any unexpected exit. It stops **only** on an explicit stop (the `--stop` flag, raised by the entrypoint at container shutdown) — never by simply dying and staying dead.

The result is a **consistently current skill database** that every agent and crew references — new and updated skills propagate to the whole fleet within a day, automatically, while the guardrail's version tracking makes each day's delta auditable and reversible.

## Skill catalog

| Skill | Version | Tier | Purpose |
|---|---|---|---|
| [`enterprise-blueprint`](enterprise-blueprint/) | 0.0.7 | enterprise | The full blueprint lifecycle in one skill: generate blueprints, sync phase-gated enforcement checklists, validate against enterprise rules, orchestrate tiered testing (unit/integration/e2e/playwright), and assign/track agents. |
| [`guardrail-enforcement`](guardrail-enforcement/) | 0.1.3 | enterprise | The enforcer: version watcher + auto-commit, workflow gate + signed audit log, advisory locks, and manifest verification. |
| [`skill-creator`](skill-creator/) | 3.0.8 | enterprise | The creator: the enforced 11-step authoring/enhancement pipeline (validate → auto-fix → re-validate → test → package → extract-verify) that every skill in this repo passes through. |
| [`skill-installer`](skill-installer/) | 1.0.11 | basic | The installer: verifies structure and installs a finalized `.skill` into a project, agent workspace, or crew without mutating the upstream skill. |
| [`portable-usb-manager`](portable-usb-manager/) | 2.0.8 | enterprise | Provision and manage portable, bootable Linux/compute USB systems offline (bundles Ventoy). |

*Consolidation note: `enterprise-blueprint-validation` was merged into `enterprise-blueprint` at v0.0.7 — its unique `test-runner.py` and testing references moved in, its duplicate `validate_blueprint.py` / `generate_checklist.py` stubs discarded in favor of the fuller originals. A skill must complete its own lifecycle (generate → validate → test) without handing off to a second skill. The retired skill is preserved under `archives/`.*

## Tags &amp; tooling metadata

Skills are discoverable through layered tags in `metadata`:

- **`metadata.tags`** — the enforced, tier-gated tag list (7+ for enterprise). This is the field validation checks.
- **`metadata.openclaw`** — `tags`, `category`, `priority` for the OpenClaw/Hemlock gateway's catalog.
- **`metadata.hermes`** — `tags`, `category`, `related_skills` for the Hermes agent framework.
- **`metadata.providers`** — the model providers a skill is compatible with.

All scripts are pure Python stdlib or POSIX shell, run on Python 3.8+, and emit structured JSON with a `cost` block (`{"tier": 0, "amount_usd": 0.0, "service": "local"}`) so usage is measurable and free by default.

### Provider tags — install-time remap, repo-side auto-strip

**This repository ships STANDARD tags only** (`metadata.tags`). Provider tag blocks
(`metadata.hermes.tags`, `metadata.openclaw.tags`, `metadata.openai.tags`) are **install-time
state**, managed automatically at both ends of the lifecycle:

| Stage | What happens | Done by |
|-------|-------------|---------|
| Install / seed / enhance in a harness | Canonical tags are **copied** into the detected provider's block so the harness promotes the skill | `skill_enhance.py` remap step (auto-detects `HERMES_*` / `OPENCLAW_*` / `OPENAI_*` env; `--provider` overrides) and the runtime's first-start seeder |
| Repack / update in-harness | Provider blocks are **kept** — the skill stays picked up | packer never touches them |
| Commit to any skills repo | Provider blocks are **auto-stripped and the commit amended** — the repo returns to standard | self-contained post-commit gate hook |

The gate hook is **transmitted by every install**: `skill-installer` bakes it in
(`scripts/gate_hook.py`) and silently places it at the target — live in `.git/hooks/post-commit`
when a repo exists, dormant at `.githooks/post-commit` when one doesn't (wired on the next
install or `git init`). A pre-existing foreign hook is never replaced, only chained after.
The hook's strip logic is fully inlined — it depends on nothing but `python3` (+`pyyaml`).
Nothing is ever converted back by hand. Details: `skill-creator/references/provider-tag-remapping.md`.

### Self-reliant enforcement

`skill-creator`'s enhance pipeline carries its own **built-in chain enforcer**
(`scripts/chain.py`) — no external skill required. [`loop-enforcer`](loop-enforcer/) remains the
universal, programmable version of the same concept for any other project (as
[`guardrail-enforcement`](guardrail-enforcement/) is for repo integrity); set
`LOOP_ENFORCER_ROOT` to explicitly delegate enhance to it.

## Adding or updating a skill

```bash
# 1. (optional) claim the skill while you work
python3 guardrail-enforcement/scripts/lock.py acquire ./my-skill --note "authoring"

# 2. run the enforced creator loop (validate -> auto-fix -> re-validate -> package -> extract-verify)
python3 <skill-creator>/scripts/skill_enhance.py update --path ./my-skill --tier enterprise --noninteractive

# 3. release the lock
python3 guardrail-enforcement/scripts/lock.py release ./my-skill

# 4. let the watcher record + auto-commit the version bump
python3 guardrail-enforcement/scripts/monitor.py scan --config ./.monitor.json

# 5. prove consistency, then push
python3 guardrail-enforcement/scripts/verify_manifest.py --repo .
git push
```

New skill directories are picked up automatically by the watcher — just drop a validated skill in and scan.

## License

MIT. Each skill declares its own `license` in `SKILL.md` frontmatter (all currently MIT).
