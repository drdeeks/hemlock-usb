# Hemlock Blueprint — Agent Runtime / Harness / Productivity System

> **Authoritative spec for the Hemlock subsystem.**
> Derived from the original `/home/drdeek/Documents/hemlock/broke_scripts/BLUEPRINT.md`
> (v1.0, May 2026) and amended (June 2026) for the **one-container + dynamic
> per-agent volumes** architecture, the **3-tier exporter**, and the
> **USB/Hemlock separation**. When this spec and `broke_scripts/BLUEPRINT.md`
> disagree, **this file wins** — the original is preserved as the historical
> source.

---

## 0. Relationship to the USB tool

Hemlock and the USB-Hemlock master menu (`menu.sh`) are **two independent
products** that share one entry point. The USB tool is a standalone portable
compute platform. Hemlock is an opt-in agent harness and productivity system
that *runs on* the USB tool (or any compatible Docker host).

| | USB-Hemlock (USB tool) | Hemlock (this spec) |
|---|---|---|
| Purpose | Portable compute platform, Ventoy USB, persistence overlays, dev tooling | Agent runtime: OpenClaw gateway + Hermes cognition + MCP brain |
| Always available | Yes (default menu) | **Opt-in only** — pass `--hemlock` / `-H` to `menu.sh` |
| Authoritative spec | `blueprint/blueprint.md` | This file |
| Runtime | Bash + jq + qemu + systemd on the Docker host | Docker container `hemlock_runtime` |

The Hemlock Manager (menu option 19) is the bridge — it's hidden unless the
user wants Hemlock. Everything in this document is scoped to what happens
*inside* and *around* `hemlock_runtime`.

---

## 1. Architecture (one container, dynamic volumes)

### 1.1 Container topology

**Exactly one persistent container: `hemlock_runtime`.** It runs the gateway,
the MCP brain, the Hermes engine, and a small in-container orchestrator that
manages per-agent and per-crew Docker volumes via the Docker socket.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  hemlock_runtime  (the ONE persistent container)                         │
│                                                                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────────────┐  │
│  │ OpenClaw        │  │ MCP brain       │  │ Hermes engine            │  │
│  │ gateway :18789  │  │ (auto-learn)    │  │ (per-agent loops)        │  │
│  └─────────────────┘  └─────────────────┘  └──────────────────────────┘  │
│                                                                           │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │ Volume Orchestrator (bash + Docker socket)                       │    │
│  │   create/destroy/list/export/import per-agent + per-crew volumes │    │
│  └──────────────────────────────────────────────────────────────────┘    │
│                                                                           │
│  Static mounts (always present):                                         │
│    /var/run/docker.sock           — bind from Docker host                │
│    hemlock_runtime  → /runtime    — gateway/MCP/brain state             │
│    hemlock_skills   → /skills:ro  — shared, daily-updated                │
│    /var/lib/hemlock/agents → /data/agents  — bind for agent vol mount pts│
│    /var/lib/hemlock/crews  → /data/crews   — bind for crew  vol mount pts│
│                                                                           │
│  Dynamic mounts (created at agent/crew creation, removed at destroy):    │
│    hemlock_agent_<id>   → /data/agents/<id>     (named Docker volume)   │
│    hemlock_crew_<name>  → /data/crews/<name>    (named Docker volume)   │
└──────────────────────────────────────────────────────────────────────────┘

Inter-agent communication:
   • A2A only via the gateway (OpenClaw → Telegram/Discord/Slack channels)
   • No shared filesystem between agents
   • No direct agent-to-agent sockets

Docker host (the OS running dockerd — either USB-booted Ubuntu or native):
   • Provides CPU/RAM/network and Docker daemon
   • Filesystem invisible to agents (no host bind mounts except the four
     above, all explicitly scoped)
   • The compute hardware (laptop/desktop CPU/GPU) is consumed
     transparently via the OS — agents have no direct hardware access
```

### 1.2 Dynamic volume attach (the "magic" piece)

You cannot add a volume to a running container via `docker compose`. We solve
this with **a bind-mount mediated by a per-agent loop-mount inside the
runtime**:

1. The runtime container has `/var/lib/hemlock/agents/` bound from the Docker
   host (a normal docker compose bind). This directory is **empty** at start.
2. When the orchestrator creates `hemlock_agent_alice`:
   - `docker volume create --label agent=alice --label framework=hemlock hemlock_agent_alice`
   - From inside the runtime: `mkdir /data/agents/alice` (which creates
     `/var/lib/hemlock/agents/alice` on the Docker host).
   - From inside the runtime, the orchestrator uses the Docker socket to run
     a one-shot privileged helper:
     `docker run --rm --privileged -v /var/lib/hemlock/agents/alice:/dest -v hemlock_agent_alice:/src alpine sh -c "mount --bind /src /dest"`
   - The bind survives until the orchestrator unmounts it (destroy/export).
3. When the orchestrator destroys an agent:
   - Validated export (3-tier; see §6) → optional.
   - Unmount: `umount /var/lib/hemlock/agents/alice` (via the helper).
   - `docker volume rm hemlock_agent_alice`.
   - `rmdir /var/lib/hemlock/agents/alice`.

**Why this works on a running container:** the host-side `/var/lib/hemlock/`
bind exists at container start; we're only manipulating subpaths *inside*
that bind. No container restart required.

**Why we accept the Docker socket mount:** there is no Docker-native way to
do dynamic per-agent volumes without it. Trade-off documented in §10
(Security Model). Gated behind a config flag, opt-in, never default-on.

### 1.3 Process model

All agent loops run **as separate processes inside the single `hemlock_runtime`
container**, not as separate containers. Each agent process:

- Is started by the orchestrator when the agent goes "active".
- Runs as the non-root **`agent`** user (uid 1000).
- Has `HERMES_HOME=/data/agents/<id>` set in its environment.
- Is launched with mount-namespace restrictions: it can read/write
  `/data/agents/<own-id>` and read `/skills`, but **cannot see** any other
  `/data/agents/<other-id>`.
- Routes all gateway traffic through the local OpenClaw on `:18789`.

Mount-namespace isolation uses **`bwrap` (bubblewrap)** — standard
sandboxing tool, available on every Debian/Ubuntu, uses unprivileged user
namespaces, requires no `CAP_SYS_ADMIN`.

```
agent process launch (inside the runtime container):

  bwrap \
    --unshare-all --share-net \
    --ro-bind / / \
    --bind /data/agents/<id> /data/agents/<id> \
    --ro-bind /skills /skills \
    --tmpfs /tmp --tmpfs /var/tmp \
    --proc /proc --dev /dev \
    --setenv HERMES_HOME /data/agents/<id> \
    --setenv AGENT_ID <id> \
    --chdir /data/agents/<id> \
    --uid 1000 --gid 1000 \
    /opt/hermes/bin/hermes-runner
```

`--share-net` lets the agent reach the gateway on `localhost:18789` and the
public internet. Everything else is namespaced away.

---

## 2. Operational modes (unchanged from original blueprint)

| Mode | Trigger | Active | Use |
|---|---|---|---|
| **FULL** *(default)* | no env override | OpenClaw + MCP + Hermes | Production |
| **HERMES_ONLY** | `HERMES_ONLY=1` | MCP + Hermes (no gateway) | Local dev, air-gap |
| **OPENCLAW_ONLY** | `OPENCLAW_ONLY=1` | OpenClaw + MCP (no Hermes brain) | Gateway/routing tests |

Mode is set at container-start time via environment variable. The Hemlock
Manager submenu (option 19) will eventually expose mode switching that does
a `docker compose down && docker compose up -d` with the env override.

---

## 3. Volume types & naming convention

| Volume | Naming | Lifecycle | Mounted at | Contents |
|---|---|---|---|---|
| Runtime state | `hemlock_runtime` (singular, static) | created at first deploy, never destroyed without explicit reset | `/runtime` | OpenClaw state, MCP brain memory, gateway logs |
| Shared skills | `hemlock_skills` (singular, static) | created at first deploy; refreshed daily by systemd timer on the Docker host | `/skills` *(ro)* | Auto-updated skill packages; agents READ and COPY into their own volume |
| Per-agent | `hemlock_agent_<id>` | created on agent create/import; destroyed on user-confirmed agent delete *after* validated export | `/data/agents/<id>` | The agent's *everything* (see §4) |
| Per-crew | `hemlock_crew_<name>` | created on crew create/import; destroyed on user-confirmed dissolve | `/data/crews/<name>` | Crew coordination state |

Labels on every dynamic volume:
- `framework=hemlock`
- `agent=<id>` (for agent volumes) or `crew=<name>` (for crew volumes)
- `created_at=<ISO8601>`

These labels are how the orchestrator lists/filters: `docker volume ls --filter label=framework=hemlock`.

---

## 4. Agent workspace contents (flat structure inside `hemlock_agent_<id>`)

```
/data/agents/<id>/
├── agent.json              # identity + metadata
├── SOUL.md                 # personality / purpose / principles
├── IDENTITY.md             # who/what this agent is
├── USER.md                 # owner preferences
├── HEARTBEAT.md            # periodic task definitions (cron-like)
├── MEMORY.md               # curated long-term wisdom
├── TOOLS.md                # tool documentation
├── AGENTS.md               # workspace structure doc
├── config.yaml             # model + provider + skills + memory config
├── .env                    # agent-specific env vars
│
├── memory/                 # daily memory notes (chronological)
├── sessions/               # conversation transcripts
├── skills/                 # skills COPIED from /skills (own copies)
├── tools/                  # executable scripts
│   ├── enforce.sh          # workspace enforcement
│   ├── secret.sh           # encrypted secret management
│   ├── memory-log.sh       # memory log helper
│   └── TOOLS-GUIDE.md
├── projects/               # active project dirs
├── .secrets/               # encrypted (AES-256-CBC); .secret-key is 0600
├── .backups/               # local backups
├── .archive/               # archived runtime artifacts
├── logs/                   # agent-specific logs
├── media/                  # user-sent media (SACRED — never auto-delete)
├── plugins/                # agent plugins
├── knowledge/              # structured knowledge base
└── workflows/              # workflow definitions
```

Permissions rule (unchanged from original blueprint §9.2):
- Directories: `755` always.
- Files: `644` always.
- Only exception: `.secrets/.secret-key` may be `600`.
- **NEVER `chmod 700`** anywhere. Enforcement scans for and fixes 700.

---

## 5. Agent & crew lifecycle

### 5.1 Create
```bash
hemlock agent create alice --model ollama/qwen3:0.6b
```
1. Validate ID (3-16 chars, lowercase, `[a-z0-9_]`).
2. `docker volume create --label … hemlock_agent_alice`.
3. Bind-attach via the per-agent loop-mount mechanism (§1.2).
4. Copy `workspace-template/` into `/data/agents/alice/`.
5. Generate `agent.json`, default SOUL/USER/MEMORY/AGENTS/IDENTITY/HEARTBEAT.
6. Apply 755/644 permissions.
7. Run `tools/enforce.sh`.
8. (No more `agents/active/` registry — the volume *is* the registration.)

### 5.2 Import
```bash
hemlock agent import alice --source ~/Downloads/alice.tar.gz
```
Source types: `.tar.gz`, `.tgz`, `.tar`, `.zip`, `.tar.bz2`, raw directory.
Auto-detect format. Flatten nested archives.

1. Validate target ID.
2. Volume create + bind-attach (as above).
3. Extract/copy source into `/data/agents/alice/`.
4. Ensure workspace template structure (fill in missing files).
5. Strip macOS artifacts (`__MACOSX`, `.DS_Store`).
6. Apply permissions; run enforce.
7. Optionally prompt for model and channel pairing.

### 5.3 Export — **the 3-tier spec (exact)**

Per user directive, exactly three tiers:

#### MINIMAL
Identity and purpose only. For safe sharing of "who this agent is" without
state or secrets.
- `agent.json`
- `SOUL.md`
- `IDENTITY.md`
- `TOOLS.md`
- `AGENTS.md`
- Any other top-level identity/purpose markdown files

#### STANDARD
MINIMAL plus the everyday working set.
- Everything in MINIMAL
- `MEMORY.md`
- `.secrets/` *(entire dir, encrypted at rest — the recipient needs the
  `.secret-key` to actually use them)*
- `HEARTBEAT.md`
- `tools/` *(entire dir)*
- `skills/` *(the agent's own copies, not the shared `/skills` mount)*
- `sessions/` — **the 5 most recent files by date**
- `memory/` — **the 5 most recent files by date**
- `USER.md`
- Cron jobs *(any `cron/` or `crontab` files)*
- `projects/` *(entire dir)*
- Any `.env` and `config.yaml`

#### FULL
Bit-for-bit volume contents. Every file, hidden included.

Output formats (user picks at export time): `tar.gz` / `tgz` / `tar` / `zip` /
`tar.bz2` / raw directory.

Every export includes:
- `manifest.json` — tier, source agent ID, volume name, timestamp, file count,
  SHA-256 of the archive payload, framework version.
- `manifest.yaml` — same content, YAML form, for human reading.

### 5.4 Validate-then-destroy flow

```
hemlock agent export alice --tier full --format tar.gz --to /tmp/alice-backup.tar.gz
```
1. Create the archive.
2. Compute SHA-256.
3. **Validate**: extract to a scratch dir, walk the tree, verify file count
   and a per-file checksum sample against the manifest.
4. If validation passes AND `--destroy` was passed (or the user confirms when
   running interactively), then **and only then**:
   - Run `hemlock agent delete alice --skip-export` (which unmounts the bind,
     removes the volume, removes the empty mount point).

### 5.5 Crew lifecycle (parallel to agents)

Same operations. Crew volume holds `crew.json`, `crew.yaml`, `SOUL.md`, and
coordination state (the actual agents remain in their own volumes; crew is
just the membership + channel routing + workflow).

---

## 6. Skills — the shared read-only volume

### 6.1 Layout
```
/skills/                       (hemlock_skills volume, mounted RO into runtime)
├── catalog.json               # index of available skills
├── <skill-name>/              # one dir per skill
│   ├── skill.json             # skill manifest
│   ├── main.py / main.sh
│   └── README.md
└── ...
```

### 6.2 Daily update
A **systemd timer on the Docker host** (NOT inside the container, since the
container should not have systemd) refreshes the volume:

```
# /etc/systemd/system/hemlock-skills-refresh.timer
[Unit]
Description=Hemlock shared skills daily refresh

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```
# /etc/systemd/system/hemlock-skills-refresh.service
[Service]
Type=oneshot
ExecStart=/usr/bin/docker run --rm \
  -v hemlock_skills:/skills:rw \
  hemlock:latest python -m skills.refresh
```

### 6.3 Agent usage pattern
Agents *read* `/skills/` and **copy** the skills they want into their own
`/data/agents/<id>/skills/`. Their copies are theirs to modify or remove.
The shared catalog refreshes daily; agents pick up new skills on demand.

---

## 7. Health system

Hemlock Doctor lives at `health/doctor_bridge.py`. Eight categories:

| Category | What it checks |
|---|---|
| `paths` | Directory existence + writability for `HERMES_HOME`, agent dirs, skills, logs, etc. |
| `env` | Required env vars, Python path, Docker detection |
| `identity` | Each agent volume has valid `agent.json` + `SOUL.md` + `config.yaml` |
| `gateway` | OpenClaw gateway reachable on `:18789`; auth token valid |
| `imports` | Python module imports for `hermes`, `openclaw`, `paths.resolver`, etc. |
| `adapters` | Platform adapter configs (Telegram, Discord) parse |
| `orchestration` | Crew configs consistent (every member volume exists) |
| `persistence` | SQLite state DB connects; JSON state files parse |

Modes:
- `--quick` — `paths` + `env` + `imports` only.
- `--json` — JSON output for the Docker healthcheck.
- `--fix` — auto-repair where safe (creates missing dirs, fixes 700 perms).
- `--categories <a,b,c>` — run specific categories only.

Compose healthcheck **uses the JSON mode** and parses the `"healthy"` boolean:
```yaml
healthcheck:
  test: ["CMD", "sh", "-c", "python3 -m health.doctor_bridge --quick --json | python3 -c 'import sys,json; sys.exit(0 if json.load(sys.stdin).get(\"healthy\") else 1)'"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

---

## 8. MCP integration (unchanged)

OpenClaw routes platform messages → MCP → Hermes agent loop → MCP →
OpenClaw → platform. Tools are routed via the MCP brain.

```
User → Platform (Telegram/...) → OpenClaw Gateway → MCP → Hermes (agent loop / brain)
                                                                     │
                                                                     ▼
                                                              Tool execution
                                                                     │
                                                                     ▼
       User ← Platform ← OpenClaw Gateway ← MCP ← ────────────── Response
```

MCP transport: stdio for local (default), HTTP for crew/remote.

---

## 9. Configuration

### 9.1 `.env` (host-side, gitignored)
```bash
# Image & build
HEMLOCK_IMAGE=hemlock:latest

# Gateway
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_GATEWAY_TOKEN=<generated-on-first-run; never empty>

# Docker socket — REQUIRED for dynamic volume orchestration
HEMLOCK_DOCKER_SOCKET=/var/run/docker.sock

# Per-agent bind mount root (Docker host path)
HEMLOCK_AGENTS_ROOT=/var/lib/hemlock/agents
HEMLOCK_CREWS_ROOT=/var/lib/hemlock/crews

# Mode (default = FULL)
# HERMES_ONLY=1
# OPENCLAW_ONLY=1

# Agent defaults
DEFAULT_AGENT_MODEL=ollama/qwen3:0.6b
DEFAULT_AGENT_NETWORK=hemlock_net
```

The gateway token is **generated on first run** (`openssl rand -hex 32`) and
written to `.env` — never ships empty. The `setup-wizard.sh` (or the Hemlock
Manager submenu) handles this.

### 9.2 `config.yaml` (per agent, inside the agent's volume)
```yaml
model:
  default: ollama/qwen3:0.6b
  provider: ollama
  base_url: http://localhost:11434/v1

tools:
  profile: coding

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
  auto_copy_from_shared: false   # opt-in: pull skills from /skills on start
```

### 9.3 Key injection
`scripts/key_inject.py` reads an OpenClaw onboarding JSON (or any
provider-specific config) and maps it into the agent's `.env` + `.secrets/`.

| OpenClaw key | Agent env var | Secret? |
|---|---|---|
| `openrouter.api_key` | `OPENROUTER_API_KEY` | yes |
| `openai.api_key` | `OPENAI_API_KEY` | yes |
| `anthropic.api_key` | `ANTHROPIC_API_KEY` | yes |
| `telegram.bot_token` | `TELEGRAM_BOT_TOKEN` | yes |
| `discord.bot_token` | `DISCORD_BOT_TOKEN` | yes |
| `github.token` | `GITHUB_TOKEN` | yes |
| `inference.provider` | `HERMES_INFERENCE_PROVIDER` | no |
| `inference.base_url` | `OPENAI_BASE_URL` | no |
| `inference.model` | `HERMES_DEFAULT_MODEL` | no |

Secrets land in the agent's `.secrets/` encrypted via `secret.sh`. Non-secrets
go into `.env`.

---

## 10. Security model

### 10.1 Principles
1. **One container, many isolated agent volumes.** Agents share the container's
   process namespace but have isolated mount namespaces via `bwrap`.
2. **Host filesystem invisible to agents.** Only the four declared bind mounts
   exist; nothing else from the Docker host is visible inside the container,
   let alone inside an agent's namespace.
3. **Docker socket is the trust boundary.** Code execution inside the runtime
   container has effective control over Docker. We accept this because the
   runtime is the only thing trusted to call the volume orchestrator, and we
   never give arbitrary agent code shell-out to `docker` (agents run inside
   `bwrap` with a stripped PATH that excludes docker).
4. **Secrets encrypted at rest.** `secret.sh` → AES-256-CBC; key file `0600`.
   This is the only `0600` permission anywhere; `chmod 700` is forbidden.
5. **No `0700` directories anywhere.** Enforcement scans + auto-repairs.

### 10.2 Docker socket caveat
Mounting `/var/run/docker.sock` into the runtime container effectively
grants root on the Docker host to anything that can run code inside the
container. Mitigations:

- Agents run inside `bwrap` with `docker` removed from their PATH.
- The orchestrator binary is owned by `root:root`, mode `0755`, and the
  agent user cannot replace it (read-only rootfs for `/opt/hermes/`).
- The socket mount is gated by `HEMLOCK_DOCKER_SOCKET` env var; if unset,
  the orchestrator refuses to start and the Hemlock Manager menu shows a
  warning instead of letting volumes be created.
- Documented as Hemlock's primary trust assumption.

### 10.3 Network
- Agents share the container's network stack (so they all see `localhost:18789`
  for the gateway).
- Agents have outbound internet access (for web browsing, model APIs, etc.).
- No inbound except via the gateway port (18789).

---

## 11. Menu surface (host-side, in `menu.sh`)

Hemlock is **opt-in only**. Pass `--hemlock` / `-H` (or `HEMLOCK_ENABLED=true`)
to reveal **option 19 Hemlock Manager**, which consolidates:

| Submenu action | What it does |
|---|---|
| Launch in-container TUI | `docker exec -it hemlock_runtime /scripts/runtime.sh` |
| Runtime status | Container state + gateway healthcheck + per-process status |
| Master Deploy | DEPLOY.sh — full stack (system + USB + Hemlock) |
| Mode switch | full / hermes-only / openclaw-only (restarts container with new env) |
| Bootstrap `.env` | Generate gateway token; populate defaults; never overwrite existing values |
| Hemlock Doctor | `docker exec hemlock_runtime python3 -m health.doctor_bridge --fix` |
| Volume management | List / create / destroy per-agent + per-crew volumes |
| Agent CRUD | Create / import / export / delete agents |
| Crew CRUD | Create / import / export / dissolve crews |
| View logs | Per-process filtered: openclaw / mcp-brain / hermes-gateway / all |
| Launch Hemlock Control (GUI) | `chromium --app=http://localhost:18789/#token=<TOKEN> --class=Hemlock-Control` — opens the OpenClaw Control web UI (already served by the gateway) in a chromeless app window. Per CL-012. |

### 11.1 GUI architecture (locked in CL-012)

The Hemlock GUI is the **OpenClaw Control SPA** served by the gateway at
`http://localhost:18789/`, opened via `chromium --app=URL`. NOT a separate
Electron app — Hermes Desktop was the wrong layer for our architecture
(User → OpenClaw → MCP → Hermes; Hermes Desktop bypasses OpenClaw).

Auth: gateway requires `OPENCLAW_GATEWAY_TOKEN`; obtained via
`docker exec hemlock_runtime openclaw dashboard` (prints a tokenized URL).
H7 will pre-fill this in the menu.

**Rebrand (deferred):** fork the OpenClaw Control SPA source from
`docker/openclaw-runtime/`, swap title/favicons/theme names/i18n strings
to "Hemlock". Commit into the image build context so
`docker compose build` produces the rebranded UI. Defer until: OpenClaw
itself is updated to current (out-of-date warning per user 2026-06-25),
H2 ships (UI needs volume orchestrator data), and a quiet machine.


---

## 12. Implementation phases (refined after the cherry-pick survey)

Each phase = one CL entry in `blueprint/blueprint.md` once merged. The
"already-have" column comes from the 2026-06-25 survey of all 6 attempt
directories in `/home/drdeek/Documents/hemlock/` (recorded in CL-009).

| Phase | Work | Already have | Need to do |
|---|---|---|---|
| **H1** | Doctor / health system (§7). | nothing | **Copy `health/` from `broke_scripts/` (== `hemlock_integrated/`, same MD5).** 14 .py, 214L `doctor_bridge.py`, 9 validator categories. |
| **H2** | Volume orchestration (§1.2, §3). | ✅ `scripts/helpers.sh` 315L with 6 `volume_*` helpers (MORE than broke_scripts' 260L); agent-create/import/delete already do `docker volume create/rm` with proper labels. | Add the **bind-mount-into-runtime** lifecycle (§1.2) + an in-container orchestrator script that gates the Docker socket. Wire crew-create/dissolve to mirror the agent pattern. |
| **H3** | Shared `hemlock_skills` volume + daily refresh (§6). | nothing — none of the 6 attempts implements daily refresh | **Build from scratch.** Two systemd files on the Docker host (`.timer` + `.service`) that run `docker run --rm -v hemlock_skills:/skills:rw hemlock:latest python -m skills.refresh`. |
| **H4** | 3-tier exporter (§5.3, §5.4). | ✅ `scripts/agent-export.sh` 806L (MORE than broke_scripts' 775L) — already has MINIMAL/STANDARD/FULL/CUSTOM modes and CORE_IDENTITY/TOOLS/SKILLS/MEMORY/SECRETS/RUNTIME/BACKUPS/MEDIA/PICTURE categories. | **Re-tune the tier contents to match the user's exact spec** (move `tools/` and `skills/` out of MINIMAL into STANDARD; add `sessions/`-5-latest and `memory/`-5-latest behavior). Add the validate-then-destroy flow (§5.4). |
| **H5** | Agent sandboxing via `bwrap` (§1.3). | nothing — none of the 6 attempts uses bwrap/unshare | **Build from scratch.** Wrap the agent-runner launch in `bwrap` with mount-namespace restrictions per §1.3. |
| **H6** | Hemlock Manager submenu fully wired (§11). | ✅ Placeholders present in `menu.sh:_run_hemlock_manager` (CL-008). | Replace placeholders with calls to the H1-H5 work and the existing scripts. |
| **H7** | Bootstrap helpers (`.env` token generation, first-run setup wizard). | ✅ `scripts/setup-wizard.sh` 956L (identical to broke_scripts) — needs token-bootstrap + non-empty `.env` validation. | Surface from the Hemlock Manager menu; auto-generate `OPENCLAW_GATEWAY_TOKEN` if `.env` is empty. |

---

## 13. Cherry-pick survey notes (recorded for future amendments)

Survey performed 2026-06-25 across six attempt directories in
`/home/drdeek/Documents/hemlock/`. Each capability ranked by completeness:

| Capability | Best source | Notes |
|---|---|---|
| Working bash volume helpers | **current `usb-hemlock-split`** (315L `helpers.sh`, 6 `volume_*` fns) | Better than the May 2026 sources. The Python `volume_manager.py` (391L, identical across 4 dirs) is a `/tmp` simulation stub — never wired. Discard. |
| `health/` (doctor system) | `broke_scripts/health/` ≡ `hemlock_integrated/health/` (identical) | Copy verbatim into `usb-hemlock-split/hemlock/hemlock-runtime/health/`. |
| `agent-create.sh` | current (642L) > broke (632L) > integrated (213L) | Use current; minor tweaks per §5.1 only. |
| `agent-import.sh` | current (711L) > broke (708L) | Use current. |
| `agent-export.sh` | current (806L) > broke (775L) > integrated (688L) | Use current; **re-tune tier contents** to match user's exact spec. |
| `agent-delete.sh` | current (207L) > broke (197L) | Use current. |
| `runtime.sh` (in-container TUI) | identical between current and broke (1334L) | Use as-is for now. |
| `setup-wizard.sh` | identical across current, broke, integrated, hemlock (956L) | Use current; add token-bootstrap. |
| Host CLI `scripts/hemlock` | identical 102L | Use as-is. |
| Shared skills + daily refresh | **none** | Build per §6. |
| Sandboxing (bwrap) | **none** | Build per §1.3. |
| Per-agent containers (deprecated path) | broke + integrated have Dockerfile.agent + compose `agent` service | **Deprecated** by this blueprint. Mark `Dockerfile.agent` and the compose `agent` service as legacy; don't extend. |

### Reference docs from `hemlock_snaps/`

The `hemlock_snaps/` attempt includes three high-level planning docs that
informed this blueprint's structure:

- `AUTONOMOUS_RUNTIME_BLUEPRINT.html` (1081L, v2.0) — phases 0-28. Especially:
  Phase 8 Agent Isolation, Phase 20 Skills Distribution, Phase 21/22
  Granular Export/Import, **Phase 23 Volume Isolation Manager** (maps to H2),
  Phase 26 Crew Lifecycle & Dormant State.
- `MASTER_CHECKLIST.md` (701L) — phase checklist counterpart, marks 0-18 as
  complete.
- `BOOTSTRAP_PROGRESS_CHECKLIST.md` (177L) — earlier bootstrap state record.

These are **historical reference only** — this blueprint supersedes them where
they overlap. The phase numbering in those docs (0-28) is **not** the same as
our H1-H7 phases above.

---

## 13. Open questions resolved (for the record)

- **One container vs per-agent containers?** → **One container**, dynamic
  per-agent volumes. Per-agent-container model from the original blueprint
  is explicitly deprecated.
- **Are profile `role` fields agent roles?** → No. `role` in the USB profile
  manifest is a **storage-routing hint only**. Agent/crew role orchestration
  lives in this Hemlock spec.
- **Does Hemlock pre-list in the master menu?** → No. Opt-in via flag.
- **Active/archive agent registries?** → Removed. The volume's existence IS
  the registration.
- **Docker socket mount?** → Yes, required for dynamic volume orchestration.
  Documented trade-off.

---

## 14. Cross-references

- `blueprint/blueprint.md` — the combined USB+Hemlock change log (CL-001+).
  Cross-references this document for Hemlock specifics.
- `/home/drdeek/Documents/hemlock/broke_scripts/BLUEPRINT.md` — the
  original May 2026 blueprint; preserved as historical source. Where this
  file diverges, **this file wins**.
- `usb-hemlock-split/hemlock/hemlock-runtime/scripts/` — the working bash
  scripts (most foundations already exist; see CL-008 survey notes).
- `usb-hemlock-split/menu.sh:_run_hemlock_manager` — the host-side entry
  point (option 19, opt-in).
