---
doc: AGENTS.md (project root — hemlock-runtime)
version: 1.5.0
updated: 2026-07-03
changelog:
  - 1.5.0 (2026-07-03): Added §13 — skill tag system: the validator↔runtime field mismatch
    (validate.py gates metadata.tags; skill_registry.py promotes on metadata.hermes.tags) and
    the DEFERRED long-term provider-adaptive tag design. Fixed package_skills.py to preserve
    guardrail artifacts (.loop-log.jsonl etc.) on packaging. All 5 skills repacked (tags/versions
    unchanged). NOT yet resolved: the tag-field mismatch + the provider-adaptive feature.
  - 1.4.0 (2026-07-03): §12 — backup now spans the Ventoy/USB persistence layer (@ventoy +
    dat:<name> images + ventoy.json; FULL auto-includes it); prints the "can't back up the
    persistence you're booted into" constraint and skips in-use .dat via losetup.
  - 1.3.0 (2026-07-03): Added §12 — consolidated owner-driven backup/restore (FULL + CUSTOM
    modes, encrypted, opt-in scheduling, runtime.sh menu 8). Replaced the orphaned rsync
    full-dump scripts/backup.sh.
  - 1.2.0 (2026-07-03): §11 — added owner-facing link management (runtime.sh menu 7 +
    engine show/edit/archive/restore; archive is a restorable tombstone, never an erase).
  - 1.1.0 (2026-07-03): Added §11 — the runtime-root GLOBAL knowledge system (append-only
    knowledge/ + classified link DB + self-healing watcher + gateway capture hook). Updated
    §9 key files and §10 status.
  - 1.0.0 (2026-07-03): Initial project-level statement of the established architecture and
    everything built to date (modes, homes, identity ownership, per-agent tooling, resilience,
    memory discipline, OpenClaw config).
---

# Hemlock Runtime — Project Overview

**Hemlock = OpenClaw (control plane) + Hermes (cognition), bridged by MCP.** OpenClaw fronts
the messaging platforms, runs the agent loop, owns identity/context; Hermes provides the
per-agent auto-learning brain (memory, skills, insights) as an MCP server. Both are branded
**Hemlock** to the user; outside branding is being removed over time.

This file states what has been established. It is the developer/architecture reference for the
runtime source tree (not an agent workspace — that template lives in `agents/workspace-template/`).

## 1. Run modes — ONE toggle: `HEMLOCK_MODE`
Set in the container env; governs the entire topology (`docker/entrypoint.sh`):

| `HEMLOCK_MODE` | Runs | Ignores |
|----------------|------|---------|
| `full` (default) | OpenClaw manages everything; Hermes MINIMAL — per-agent brains launched on demand by OpenClaw via MCP (no standalone Hermes gateway) | — |
| `hermes` | Standalone Hermes gateway; paths still resolve via `$HEMLOCK_HOME`, nothing moves | OpenClaw (not started, no config generated) |
| `openclaw` | OpenClaw runs its own agents (config generated with `INCLUDE_BRAINS=0`) | Hermes brains (empty `mcp.servers`) |

Legacy `HERMES_ONLY=1` / `OPENCLAW_ONLY=1` still honored (`HEMLOCK_MODE` wins); unknown → `full`.

## 2. Agent home — `HEMLOCK_HOME` (canonical), `HERMES_HOME` (legacy alias)
`HEMLOCK_HOME` is the agent's workspace/volume root. `HERMES_HOME` still works everywhere
(non-breaking alias) during the de-brand. Both are exported by the entrypoint, the brain, and
`gen-openclaw-config.py`; all per-agent tools resolve `${HEMLOCK_HOME:-${HERMES_HOME:-.}}`.
Full rename + branding strip is a tracked long-run effort.

## 3. Identity ownership (important)
In the DEFAULT system **OpenClaw owns identity/context** — it injects each agent's workspace
files into the system prompt, in order: `AGENTS.md, SOUL.md, TOOLS.md, IDENTITY.md, USER.md,
HEARTBEAT.md, MEMORY.md` (from `agents.list[].workspace` = the agent's home). The Hermes brain
is **cognition + DATA ops only** and must NOT take identity over — hence `agent_chat` runs with
`skip_context_files=True`. `HEMLOCK_HOME` on the brain = DATA scope (memory/secrets/skills/
sessions/file I/O land in the right volume), NOT identity. Identity-from-home is standalone-only.

## 4. Per-agent workspace (`agents/workspace-template/`)
Seeded into every agent by `scripts/agent-create.sh` (`cp -ra`) and enforced on boot
(`entrypoint.sh` → `tools/enforce.sh`). Contains:
- **Docs** (may hardcode reference paths): `AGENTS.md` (operating standard), `TOOLS.md`
  (tool registry), `SOUL.md`, `IDENTITY.md`, `USER.md`, `MEMORY.md`, `HEARTBEAT.md`.
- **Tools** (must stay path-resolving): `secret.sh`, `memory-log.sh`, `memory-promote.sh`,
  `enforce.sh`, `inject-context.sh`, `context-dump.sh`, `rollback.sh`, `auth-login.sh`,
  `jsonfmt.py`.
- **Dirs**: `memory/`, `sessions/`, `skills/`, `projects/`, `knowledge/`, `.secrets/`, `logs/`,
  `.archive/`, plus a per-volume `.gitignore`.
- **Identity layer** (`.agent/`): `constitution.yaml` (values, operational standards, hard
  constraints — loads at t=0 via `inject-context.sh`, injected right after SOUL.md), three
  internalized habits (`identity-enforcement`, `tool-enforcement`, `reflective-loop`), and
  `enforcer-config.yaml` for the opt-in enforcer daemon. `agent-create.sh` fills the
  placeholders and stamps the constitution's sha256 into `<agent-id>.json` (`identity` block) —
  a later hash mismatch means the constitution was edited after provisioning. Fail-soft: a
  template without `.agent/` still provisions. Deep architecture lives in the seeded
  `agent-identity-architecture` skill (enforcer daemon, agent runtime, memory curator).

## 5. Agent operating standard (`agents/workspace-template/AGENTS.md`)
Injected into every agent's prompt by OpenClaw. Establishes:
- **⚠️ MANDATORY: search memory FIRST** — `session_search(<topic>)` before any task (grounded in
  the real FTS5 recall; upgrades to vector when built). Verified via `logs/memory-searches-*.log`.
- **Memory tree**: `memory/YYYY-MM-DD.md` (daily, append-only) → `MEMORY.md` (curated) →
  `SOUL.md` (identity). Write for agent-next; handoff on compaction/shutdown.
- **To-do lists MANDATORY** for any task > 2 edits/steps (native `todo` tool).
- **Autonomy spectrum**: scripts → tools → skills → subagents → coordinator; build a tool on the
  3rd repetition (deterministic, tested, validated, into `tools/`, registered in `TOOLS.md`).
- **Doc versioning standard**: `version/updated/changelog` frontmatter (enforce.sh warns).
- **Secrets**: encrypted JSON via `secret.sh` only; never plaintext/verbatim/in-memory. Owner
  can always view/manage (`secret.sh show`); exports carry `.secrets/` + `.secret-key`.

## 6. Resilience — nothing lost, everything reversible
- **Crash-safe context offload** (`tools/context-dump.sh` + entrypoint hook + periodic flush):
  dumps context to `sessions/dumps/context-<ts>.md` on shutdown/failure; WAL-checkpoints SQLite.
- **Per-volume git snapshots** (`docker/volume-git-daemon.sh`, self-healing, daily): each
  agent/crew volume is a git repo committed daily; `tools/rollback.sh` restores any file/dir.
  `.secrets` tracked ENCRYPTED; `sessions/dumps/`, `context.md`, caches ignored.
- **Skills auto-update** (`docker/skills-auto-update.sh`): self-healing daily curated-skill sync.

## 7. Skills — LAZY by design
17 enterprise-validated skills are seeded in `shared/skills/` (canonical repo: auto-committed
by a guardrail watcher on version bumps, mirrored here). OpenClaw injects only a compact
name+description+location index; `SKILL.md` is read on demand.
Index capped by `skills.limits.maxSkillsPromptChars` (+ per-agent `skillsLimits`), set by
`gen-openclaw-config.py` (default 8000).

## 8. OpenClaw config generation (`docker/gen-openclaw-config.py`)
Auto-discovers agents under `/data/agents`, writes `openclaw.json`: per-agent
`{id,name,workspace,model,identity.name,default}`, **no per-agent tool restriction = all tools
by default**, lazy-skills caps, bootstrap-injection limits, group defaults, a `bindings[]`
routing scaffold (real channel/peer routes are deployment-time; first agent is `default:true`),
and per-agent `brain-<id>` MCP (env `AGENT_ID` + `HEMLOCK_HOME`). `INCLUDE_BRAINS=0` omits brains
(openclaw-only mode).

## 9. Key files
- `docker/entrypoint.sh` — boot, mode dispatch, daemon supervision, shutdown hooks.
- `docker/gen-openclaw-config.py` — OpenClaw manager config generator.
- `docker/agent_brain_mcp.py` — per-agent Hermes brain MCP (cognition + data tools).
- `docker/volume-git-daemon.sh`, `docker/skills-auto-update.sh`, `docker/knowledge-watcher.sh`
  — self-healing daemons.
- `scripts/knowledge_capture.py` + `scripts/knowledge-capture.sh` — global knowledge engine.
- `scripts/backup.sh` — consolidated backup/restore (FULL + CUSTOM modes; owner-driven).
- `agents/workspace-template/` — the droppable per-agent workspace (docs + tools).
- `scripts/agent-create.sh`, `scripts/agent-import.sh`, `scripts/enforce.sh` — lifecycle.
- `Dockerfile.runtime` — bakes everything (toolchain + runtime + skills) into one image.

## 11. Global knowledge system (runtime-root, append-only)
One knowledge base shared by **every** agent, at the runtime root
(`$HEMLOCK_KNOWLEDGE_DIR`, default `/data/knowledge`):
- **Append-only** `inbox/` (captured docs, immutable timestamped names, never overwritten),
  a classified **link DB** `links.json` (facets: `use` / `function` / `scope`), a rebuildable
  keyword `index.json`, and an append-only `CAPTURE-LOG.md`.
- **Engine**: `scripts/knowledge_capture.py` (stdlib-only argparse CLI — arbitrary/hostile
  inbound content flows through argv, never interpolated) via `scripts/knowledge-capture.sh`.
  Offline-safe: URLs are recorded + classified without fetching (`--fetch` is opt-in).
- **Auto-capture (gateway hook)**: `agent_brain_mcp.py::agent_chat` — the mode-agnostic
  chokepoint every inbound message passes — fires a fail-soft, side-effect-only capture of any
  URL in the message (tagged `received_by` = agent). Never blocks or alters the reply.
- **Watcher**: `docker/knowledge-watcher.sh` (self-healing; inotify or poll) indexes new inbox
  files. Started/stopped by `entrypoint.sh` (`KNOWLEDGE_WATCH_ENABLED`, default on).
- **Agent-facing**: per-agent `tools/knowledge.sh` writes to the GLOBAL store, auto-tagging
  with the agent's identity (AGENTS.md §8; registered in TOOLS.md).
- **Owner-facing**: the interactive menu (`scripts/runtime.sh` → **7. Knowledge Base**) lets the
  owner review, search, add, **reclassify** (`edit`), **archive** (soft-remove → `links.archive.json`,
  nothing is erased), and **restore** links, and read the capture log. Engine commands:
  `show / edit / archive / restore / archived` (agents capture; the owner manages).

## 12. Backup & restore (`scripts/backup.sh`, owner-driven — menu 8)
ONE tool, the owner picks the mode — never forced to dump everything. It spans **both
persistence layers**: the CONTAINER layer (`/data` dirs) and the **Ventoy/USB layer** — the
delegated `.dat` persistence images (`hemlock.dat`, `tooling.dat`, `models.dat`,
`<os>-persistence.dat`) + `ventoy.json`, which are split precisely so each is a backup unit.
- **FULL** — the entire persistent data state in one shot: container dirs
  (`agents crews knowledge config`, override `HEMLOCK_FULL_TARGETS`, always encrypted) AND,
  when a Ventoy USB is detected, the `@ventoy` layer (all `.dat` + `ventoy.json`). Restore
  refuses in-place unless `--data-root <stage>` or `--force`.
- **Ventoy refs** (CUSTOM or FULL): `@ventoy` (whole USB state) / `dat:<name>` (one image).
  Detection: `HEMLOCK_VENTOY_MOUNT` / `UCA_PRIMARY_PERSISTENCE` / auto (`/media/*/*`…).
  **You cannot back up a persistence image you are booted INTO** — the tool prints this,
  detects in-use images via `losetup`, and SKIPS them. Do `.dat` backups from the host / another
  boot (outside Ventoy). `.dat` images are copied sparse-aware (opt `--compress`/`--encrypt`),
  not tarred; restore is guarded and skips live images.
- **CUSTOM** — one volume (agent / `crew:<name>` / `@knowledge`), with chosen `--include`
  categories (memory/identity/sessions/skills/projects/knowledge/tools/secrets/logs|all),
  `--dest`, and encryption (auto when secrets are included). Restore snapshots the target's
  current state into `.archive/pre-restore-*` first; `--dry-run` lists without writing.
- **Scheduling is opt-in** — a per-volume `schedule` in `config/backup.json` + `backup.sh
  run-due` that the OWNER's cron calls (no forced daemon), consistent with the memory-review
  cron model. Encryption: AES-256-CBC/PBKDF2 with `config/.backup-key` (`backup.sh init`;
  key + `backups/` are gitignored). Injection-safe config edits (argv, never interpolated).

## 13. Skill tag system (IMPLEMENTED — install-time remap, repo-side auto-strip)
**Historical context:** the validator gates on canonical `metadata.tags` while the runtime's
`skill_registry.py` reads `metadata.hermes.tags` — so validated skills could promote on zero
tags. That gap is now closed by the provider-adaptive tag lifecycle:

- **Repo standard:** skills ship canonical `metadata.tags` ONLY (7+ enterprise / 5+ basic).
- **Install/update remap:** `skill-creator/scripts/skill_enhance.py` detects the active
  provider(s) (`detect_providers()` — HERMES_*/OPENCLAW_*/OPENAI_* env, `HEMLOCK_MODE`;
  `--provider` overrides) and copies canonical tags into `metadata.<provider>.tags`
  (hermes/openclaw/openai) — additive, idempotent, canonical untouched. First-start seeding in
  `docker/entrypoint.sh` runs the same remap, so the runtime-consumed block is always populated.
- **Repo-side auto-strip:** `skill-creator/scripts/normalize_tags.py` strips provider blocks
  back to standard; a self-contained **post-commit git hook** (transmitted by skill-installer on
  every install — live `.git/hooks/post-commit`, dormant `.githooks/`, foreign hooks chained)
  strips + amends automatically at repo submission. Provider docs links live in
  `skill-creator/references/provider-tag-remapping.md`.

**Packaging note (DONE):** `package_skills.py` preserves guardrail artifacts
(`.loop-log.jsonl`, `.gate.json`, …) at the skill root (excludes only the transient
`.loop.lock`).

## 10. Status / pending
Built + validated: mode toggle, HEMLOCK_HOME alias, agent operating standard + mandatory memory
search + logging, memory tree, crash-safe context-dump, per-volume git + rollback, path-guard,
all-tools + lazy-skills OpenClaw config, **runtime-root global knowledge system** (§11:
append-only `knowledge/` + classified link DB + self-healing watcher + gateway capture hook;
legacy `docs-indexer.sh` also hardened against the same interpolation-injection class),
**owner-driven backup/restore** (§12: FULL + CUSTOM modes, encrypted, opt-in scheduling, menu 8).
Also built + validated (2026-07-08): **provider-adaptive skill tag system (§13)** — remap on
install/update + post-commit auto-strip, hard-tested end to end; **17-skill validated seed**
(all pass skill-creator enterprise validation; canonical repo auto-commits version bumps via
guardrail monitor cron); **agent identity layer** (§4 — constitution at t=0 + identity hash,
verified by provisioning a scratch agent); gateway port moved to **1437**. Pending: **long-run**
full de-brand + semantic/vector memory (then upgrade the mandatory search — and knowledge
search — to vector). Before rebuild: revoke the OpenRouter/Telegram test tokens in `.env` /
`runtime/.env`.
