# Hemlock Runtime

![License](https://img.shields.io/badge/license-MIT-green)
![Python](https://img.shields.io/badge/python-3.8%2B%20stdlib-blue)
![Docker](https://img.shields.io/badge/build-Docker%20BuildKit%200-2496ED?logo=docker&logoColor=white)
![Runtime](https://img.shields.io/badge/runtime-OpenClaw%20%2B%20Hermes%20%2B%20MCP-6f42c1)
![Secrets](https://img.shields.io/badge/secrets-encrypted%20JSON%20only-critical)
![Status](https://img.shields.io/badge/status-active%20development-yellow)

A portable, self-hosted multi-agent runtime. **OpenClaw** owns the control plane (identity,
context, the agent loop); **Hermes** provides cognition (a per-agent "brain" served over
**MCP**); the two are bridged so each agent gets an isolated brain. The whole thing is built to
run from a Docker image or a Ventoy USB, on hardware as small as a 4 GB / 1.87 GHz machine.

> **Design creed:** informative, optional, interactive — never forced restrictions. Nothing is
> lost, everything is reversible, and the owner can always see and manage their own data.

> **Independent system:** this runtime is its own individually owned system. It ships inside the
> USB-Hemlock repo for convenience, but it has no dependency on the USB platform (and vice
> versa) — build and run it on any Docker host, use it for whatever you want.

---

## Architecture

```
                        ┌─────────────────────────────────────────┐
   platforms  ───────▶  │  OpenClaw  (control plane)              │
 (telegram/etc)         │  • identity + context injection         │
                        │  • runs the agent loop                  │
                        │  • LAZY-loads skills                     │
                        │            │  MCP handshake              │
                        │            ▼                             │
                        │  Hermes brain-<agent>  (cognition)      │
                        │  • per-agent, isolated                   │
                        │  • data + reasoning, no identity         │
                        └─────────────────────────────────────────┘
   persistence:  container /data   +   Ventoy USB .dat images (by purpose)
```

- **One run-mode toggle — `HEMLOCK_MODE`** (`full` | `hermes` | `openclaw`).
- **Agent home — `HEMLOCK_HOME`** (canonical), with `HERMES_HOME` kept as a non-breaking alias.
- **Identity ownership:** OpenClaw injects `AGENTS.md` / `SOUL.md` / `TOOLS.md` / `IDENTITY.md` /
  `USER.md` / `HEARTBEAT.md` / `MEMORY.md`. The Hermes brain is cognition + data only — it never
  owns identity.

---

## Quick start

**One installer, every variation** — Hemlock is always the combined runtime (control plane +
cognition over MCP, one system); the variants only differ in what's baked in:

```bash
./install.sh                      # interactive picker
./install.sh --variant full       # everything baked, plug ready       (~4.2GB)
./install.sh --variant lean       # no baked toolchain, adaptable      (~870MB)
./install.sh --variant minimal    # daemon + brain + access/menu/health (~2GB)
./install.sh --variant full --usb # build + copy image onto USB persistence
./install.sh --load hemlock.tar.gz  # load a prebuilt image
./install.sh --native             # run with no container at all
```

Or by hand:

```bash
# Build the runtime image (plain builder; this machine target is intentionally modest)
DOCKER_BUILDKIT=0 docker build -t hemlock:latest -f Dockerfile.runtime .

# Run it (full mode)
docker run --rm -it -e HEMLOCK_MODE=full -v hemlock-data:/data hemlock:latest

# Or drive the interactive owner menu (build, backup, knowledge, USB, gate…)
scripts/runtime.sh
```

The image bakes only what the build needs (`docker/`, `health/`, `scripts/`,
`agents/workspace-template/`, `shared/skills/`). It does **not** bake `.env`, real agent data, or
secrets — see [`.dockerignore`](.dockerignore).

---

## What's built

| System | Where | Summary |
|---|---|---|
| **Run modes** | `docker/entrypoint.sh` | Single `HEMLOCK_MODE` toggle (full/hermes/openclaw). |
| **Per-agent brains** | `docker/hermes-agent/` | Isolated `brain-<name>` per agent over MCP, validated by a live handshake. |
| **Per-agent volumes** | `agents/`, `crews/` | Each agent/crew is a git repo with a daily auto-commit watcher + rollback. |
| **Global knowledge base** | `knowledge/`, `scripts/knowledge*` | Append-only store + classified link DB + self-healing watcher + a gateway capture hook (any link an agent receives is captured). |
| **Backup & restore** | `scripts/backup.sh` (menu 8) | Owner-driven. FULL (entire state, incl. Ventoy `.dat` images) **or** CUSTOM (pick a volume + categories). Encrypted; opt-in scheduling; you are never forced to dump everything. |
| **Memory discipline** | `agents/workspace-template/` | Mandatory memory-search-first, crash-safe context dumps, unlimited daily memory, `USER.md` owner-model corpus. |
| **Skills (LAZY)** | `shared/skills/` | 17 enterprise-validated skills (below), loaded on demand via a compact in-prompt index. |
| **Agent identity layer** | `agents/workspace-template/.agent/` | Constitution loaded at t=0 (values, standards, hard constraints), 3 internalized habits, enforcer config. `agent-create.sh` fills placeholders and stamps a sha256 identity hash into `<agent-id>.json`; `inject-context.sh` injects the constitution right after SOUL.md. |
| **Guardrail / gate** | `shared/skills/guardrail-enforcement/` | HMAC-signed, hash-chained audit log (`.loop-log.jsonl`) + a monitor that auto-commits version bumps + git-hook enforcement. |

### Bundled skills
All 17 pass skill-creator enterprise validation and are canonically maintained in a separate
repo (auto-committed there by a guardrail watcher on every version bump), then synced into
`shared/skills/`; a daily self-healing updater keeps the container copy current.

`skill-creator` · `skill-installer` · `guardrail-enforcement` · `enterprise-blueprint` ·
`portable-usb-manager` (absorbed `unified-usb-skill`) · `loop-enforcer` ·
`agent-identity-architecture` · `agent-wake-up` · `autonomous-crew-integration` ·
`crew-knowledge-system` · `enterprise-organization` · `hackathon-manager` ·
`hemlock-minimal` · `kanban-orchestrator` · `knowledge-indexer` · `tool-enforcement` ·
`tv-sitcom-mcp`

---

## Security posture

- **Secrets are encrypted JSON, managed only via `secret.sh`.** They are never piped in plain
  text, never printed verbatim, and never committed. The owner *can* view and manage their own.
- **`.gitignore` is surgical:** it excludes secret/state *data* (sessions, `*.db`, dumps, backups,
  keys) while keeping vendored runtime source and structure markers (`.gitkeep`, `*.example`).
- **The gate's signing key** lives `0600` under `~/.config/gate/hmac.key` — outside the repo,
  never inside a shipped `.skill`.
- **Never** `chmod 700/600` anything except `.secrets/`.

> ⚠️ Before pushing or rebuilding: **revoke any live OpenRouter / Telegram test tokens upstream**
> and clear session logs (they have leaked keys before).

---

## Repository layout

```
docker/        entrypoint, config generator, Hermes agent, self-healing daemons
health/        health checks
scripts/       runtime.sh (owner menu), backup.sh, knowledge*, docs-indexer…
agents/        workspace-template (baked) + real agents (volumes, not baked)
shared/skills/ the 5 LAZY skills baked into the image
knowledge/     append-only global knowledge store (runtime root)
Dockerfile.runtime   the image build
AGENTS.md      the authoritative project overview (read this next)
```

---

## Status

**Active development.** Built and validated: run-mode toggle, per-agent brains + MCP handshake,
per-agent git volumes, the knowledge system, owner-driven backup/restore (incl. Ventoy layer),
memory discipline, the skill/guardrail toolchain, the provider-adaptive skill-tag system
(install-time remap + repo-side auto-strip; `AGENTS.md` §13), the 17-skill validated seed, and
the agent identity layer (constitution at t=0 + identity hash). Gateway port is **1437**
(host OpenClaw keeps 18789 — no collision). **In progress / not yet claimed done:**
end-to-end autonomous crews, full de-brand, semantic/vector memory. Component status is tracked
honestly in `AGENTS.md` — if it isn't listed as validated there, treat it as unverified.

## License

MIT.
