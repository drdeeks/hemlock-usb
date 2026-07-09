---
name: hemlock-minimal
description: 'Single-container Hemlock runtime: OpenClaw Gateway (control plane) +
  Hermes Brain (cognition) over MCP, with agents/crews isolated as named Docker volumes.
  Use when: building the minimal image, deploying the single-container runtime, wiring
  gateway config interactively, running health doctor checks, managing agent/crew
  volumes, or exporting/importing runtime state.'
version: 0.1.1
license: MIT
metadata:
  category: devops
  tags:
  - hemlock minimal runtime
  - single container deployment
  - openclaw gateway container
  - hermes brain mcp
  - agent volume isolation
  - runtime health doctor
  - export import runtime state
---

# Hemlock Minimal - OpenClaw Gateway + Hermes Brain

Single-container runtime for autonomous agent orchestration.

## Architecture

- **Layer 1 (Base)**: Python 3.12-slim with agent user, base packages
- **Layer 2 (Runtime)**: OpenClaw Gateway + Hermes Brain + EntryPoint
- **Layer 3 (Reference)**: Skills, health validators, scripts (copied into image)
- **Layer 4 (Isolation)**: Named volumes (`hemlock-agent-<id>`, `hemlock-crew-<name>`)

### Correct Integration Pattern (from official docs)

| Layer | Component | Role | Source |
|-------|-----------|------|--------|
| **Gateway (Control Plane)** | **OpenClaw Gateway** | Message routing, Telegram, sessions, auth, bindings | OpenClaw Multi-Agent |
| **Agent Runtime** | **Hermes Brain** | Cognition, agent loop, tool execution, memory | Hermes Architecture |
| **MCP Provider** | **OpenClaw** | Exposes `mcp_bridge` as MCP servers to Hermes | Hermes MCP + OpenClaw Config |
| **Channel** | **Telegram (OpenClaw)** | DMs, groups, pairing, commands | OpenClaw Telegram |

**✅ OpenClaw RUNS THE SHOW** — it owns:
- Gateway process (port 18789)
- Telegram bot connection
- Session management + transcript persistence
- Agent routing via bindings
- System prompt assembly

**Hermes runs as MCP servers** — each agent = 1 MCP server registered in OpenClaw config.

### Data Flow

```
OpenClaw Gateway (Single Process)
├─ Telegram (grammY) ──► Bindings ──► Agent Routing
├─ Sessions (file-based) ──► Transcript persistence
└─ MCP Client (stdio) ──► Spawns python3 -m mcp_bridge per agent
                            │
                            ▼
                   Hermes MCP Bridge (per agent)
                   ├─ Reads STARTUP.md, IDENTITY.md, MEMORY.md, USER.md, TOOLS.md
                   ├─ Builds Hermes AIAgent with agent-specific config
                   └─ Starts MCP stdio server
```

## Key Design Decisions

| Decision | Implementation |
|----------|----------------|
| Single container | Gateway + Hermes + Manager = 1 process |
| No bind mounts | All state in named Docker volumes |
| Volume-per-agent | `hemlock-agent-<id>` = complete workspace |
| Volume-per-crew | `hemlock-crew-<name>` = crew config + member refs |
| Shared skills | `/shared-skills` (read-only, symlinked into agents) |
| MCP registration | Gateway config JSON, `python3 -m mcp_bridge` per agent |
| Health check | TCP port 18789 (`timeout 5 bash -c '</dev/tcp/localhost/18789'`) |
| No restart policy | Prevents restart storms during debugging |
| OpenClaw owns gateway | Telegram, sessions, bindings, MCP config |
| Hermes owns cognition | Agent loop, tools, memory, LTM consolidation |
| Telegram commands | Stay in OpenClaw (handled at gateway level) |

### Per-Agent Workspace Structure (Critical)

When an agent is created, its volume is initialized with a complete workspace:

```
/workspace/ (inside agent volume)
├── agent.json          # Identity + model config
├── SOUL.md             # Agent personality/purpose
├── IDENTITY.md         # Detailed identity + core principles
├── TOOLS.md            # Available tools + guidelines
├── USER.md             # User profile + working agreement
├── MEMORY.md           # Curated long-term memory (LTM) - single file
├── STARTUP.md          # Pre-session injection protocol (MANDATORY)
├── HEARTBEAT.md        # Agent heartbeat configuration
├── config.yaml         # Runtime config with consolidation settings
├── .env                # API keys (600 perms)
├── avatars/            # Agent avatars (for minimal export)
├── tools/              # Custom tools (for minimal export)
├── skills/             # Copied from /skills (NOT symlinked)
├── memory/             # FLAT - NO subdirectories
│   ├── 20260613-meeting-notes.md
│   ├── 20260613-api-discovery.md
│   ├── session-20260613T143022.md
│   └── ... (all flat files)
├── sessions/           # Session markers
│   └── session-20260613T143022.md
├── .secrets/           # Encrypted secrets (default perms, NO 700)
├── logs/
├── media/
├── projects/
├── config/
├── cron/
└── # NO symlinks for skills - agents COPY what they need
```

### Memory Hierarchy (Critical Distinction)

| Location | Purpose | Lifetime |
|----------|---------|----------|
| `memory/` | Flat STM files (daily raw memories) | Days |
| `MEMORY.md` | **Curated long-term memory** (manual consolidation) | Permanent |

**Critical**: `MEMORY.md` is the **curated long-term memory** (manual consolidation). The `memory/` directory contains flat session files only — NO `short-term/`, `long-term/`, `pending/`, `archived/` subdirectories. Consolidation is a deliberate action — promote items from `memory/` → `MEMORY.md`.

> **Rule**: Never mix curated memory (MEMORY.md) with raw daily memories (memory/). The agent reads MEMORY.md at startup; session files accumulate and are curated into MEMORY.md. DO NOT create subdirectories in memory/.

## Build

```bash
cd hemlock-minimal
docker build -t hemlock/runtime:latest -f Dockerfile.runtime .
# OpenClaw deps (run once):
docker run -d --name hemlock-fix --entrypoint sleep hemlock/runtime:latest infinity
# OPENCLAW_NPM_DIR defaults to the in-image install: $OPENCLAW_HOME/lib/node_modules/openclaw (OPENCLAW_HOME=/opt/openclaw)
docker exec -u root hemlock-fix bash -c "cd ${OPENCLAW_NPM_DIR} && npm install --production --legacy-peer-deps"
docker commit hemlock-fix hemlock/runtime:latest
docker rm -f hemlock-fix
```

## Deploy

```bash
docker compose up -d
./scripts/runtime.sh
```

## Management Console (Interactive TUI)

Run `hemlock` (alias) or `/entrypoint.sh tui`:

```just
╔════════════════════════════════════════════════════════════════════════════════╗
║                           HEMLOCK MINIMAL - TUI                              ║
║  Runtime: RUNNING  Gateway: HEALTHY  Agents: 3  Crews: 1  Skills: 87          ║
╚═══════════════════════════════════════════════════════════════════════════════╝

  ► 🚀 System Control        - Start/Stop/Restart/Status/Health
    👤 Agent Management      - Create/Attach/Detach/Delete/Export/Import
    👥 Crew Management       - Create/Attach/Detach/Delete/List
    🔧 Gateway Config        - View/Edit/Validate/Tokens/Channels
    📦 Skills & Volumes      - Populate/Backup/Restore/Cleanup
    💬 iMessage & Channels   - Configure/Test/Pair/Telegram/Discord
    📤 Import/Export         - Agent/Crew packages (minimal|standard|full)
    💾 Backup/Restore        - Full system backup & disaster recovery
    📊 Health & Stats        - System health, MCP bridges, resources
    🔧 Settings              - Models, Providers, Environment
    🚪 Exit

↑/↓ Navigate  Enter: Select  q: Quit
```

## Gateway Interactive Configuration (NEW)

**Option 5 in Hemlock TUI** provides full interactive gateway configuration:

| Menu | Capabilities |
|------|--------------|
| **1) Agents Management** | Create, Attach, Configure (model, skills, MCP, resources), Export/Import, Delete, View details |
| **2) Crews Management** | Create, Attach, Configure (channel, agents), Export/Import, Delete, View members |
| **3) Gateway Settings** | Token, Telegram, iMessage, MCP servers, Network ports, Plugins, Reset |
| **4) Skills Management** | List 157+, Copy to agent, Install, View details, Update all |
| **5) Resource Allocation** | Port mappings, CPU/memory defaults, Persistence mode (rw/ro), Isolation level |
| **6) Backup/Restore** | Export/Import agent/crew, Full system backup, Restore from backup |

### Per-Agent Configuration

```bash
# In gateway interactive menu → 1) Agents → 4) Configure agent
# Options:
1) Change model (claude-sonnet-4, gpt-4, etc.)
2) Configure MCP server (command + args)
3) Copy skills from shared-skills (157+)
4) Set resource limits (CPU, memory, pids_limit)
5) Environment variables (.env)
6) View full config (agent.json, config.yaml, .env)
```

### Per-Crew Configuration

```bash
# In gateway interactive menu → 2) Crews → 4) Configure crew
# Options:
- Channel name
- Agent membership
- Export/Import
```

### Gateway Settings

```bash
# In gateway interactive menu → 3) Gateway Settings
1) View/change gateway token
2) Configure Telegram (bot token, account)
3) Configure iMessage (remote Mac SSH)
4) Configure MCP servers (add/remove per agent)
5) Configure network ports (add/remove compute ports)
6) Configure plugins (name + path)
7) Reset gateway config
```

### Hemlock Wrapper Script (`/scripts/hemlock`)

```bash
#!/usr/bin/env bash
# Hemlock wrapper - launches the TUI
# If running inside container, execute TUI directly
if [[ -f /.dockerenv ]] || [[ -n "${CONTAINER:-}" ]]; then
    exec /scripts/hemlock-tui
fi

# Otherwise exec into the container
exec docker exec -it hemlock-runtime /scripts/hemlock-tui
```

Add to host: `alias hemlock="docker exec -it hemlock-runtime /scripts/hemlock-tui"`

## Entrypoint (`entrypoint.sh`)

Commands:
- `gateway` — start OpenClaw Gateway with auto-attach
- `agent-create <id> [model] [name]` — create agent volume + workspace
- `agent-attach <id>` — register MCP bridge in gateway config
- `agent-detach <id>` — remove from gateway config
- `agent-delete <id>` — destroy volume
- `agent-list` — list from gateway + volumes
- `crew-create <name> <agents...>` — create crew volume
- `crew-attach <name>` — attach all member agents
- `crew-detach <name>` — detach all member agents
- `crew-list` — list crews from volumes

## Export/Import Modes

See [references/export-import-modes.md](references/export-import-modes.md) for the fixed mode definitions and detailed flows.

## iMessage Integration

See [references/imessage-integration.md](references/imessage-integration.md) — SSH tunnel to a Mac running `imsg`; the only supported method.

## Enterprise Blueprint Integration

Hemlock Minimal includes the `enterprise-blueprint` skill for generating and maintaining enterprise-grade technical blueprints with synchronized checklists.

### Location

```
${DEPLOY_HOME:-$HOME}/hemlock-minimal/
├── blueprint/
│   ├── blueprint.md      # Master specification (Enterprise Grade validated)
│   ├── checklist.md      # Phase-synchronized enforcement checklist
│   └── project.json      # Project metadata
└── skills/
    └── enterprise-blueprint/  # Full blueprint toolkit (installed from drdeeks repo)
```

### Blueprint Toolkit Usage

```bash
cd ${DEPLOY_HOME:-$HOME}/hemlock-minimal/skills/enterprise-blueprint

# Validate blueprint (100% passing = Enterprise Grade)
python3 scripts/validate_blueprint.py ../../blueprint/blueprint.md --json

# Sync checklist after blueprint changes
python3 scripts/generate_checklist.py ../../blueprint/blueprint.md --sync

# Assign agents to phases/modules
python3 scripts/assign_agents.py ../../blueprint --assign "architect:PHASE-1"
python3 scripts/assign_agents.py ../../blueprint --assign "mcp-engineer:MOD-002"
python3 scripts/assign_agents.py ../../blueprint --report
```

### Blueprint Status (Current)

- **Validation**: 48/48 checks PASSED (Enterprise Grade)
- **Phases**: 8 (Pre-Build → Launch & Live Ops)
- **Modules**: 14 (Gateway Core, MCP Bridge, Hermes Loop, Volume Mgr, Telegram, iMessage, Session Mgr, Agent Identity, Memory Hierarchy, Startup Injection, Skill Installer, Export/Import, Multiboot USB, Health/Doctor)
- **Feature Flags**: 14 (FEAT_*)
- **Change Log**: CL-001 (initial creation)

### Creating New Blueprints

```bash
python3 scripts/init_blueprint.py "New Project" \
  --path ./output/new-project \
  --phases "Pre-Build,Foundation,Core,Integration,Launch"
```

### Pre-Startup Injection Protocol (STARTUP.md) — CRITICAL

Every agent session **must** begin with a mandatory startup sequence. This is enforced via the auto-generated `STARTUP.md` in each agent's workspace.

### Mandatory Startup Sequence

**The agent MUST read these files IN ORDER before responding to ANY user input:**

```
1. IDENTITY.md      - Who you are, core principles
2. MEMORY.md        - Your curated long-term memory
3. USER.md          - User profile and working agreement
4. TOOLS.md         - Available tools and guidelines
5. STARTUP.md       - This file (you are here)
```

### Mandatory First Message

The agent **MUST** output this exact message as its FIRST response — NO OTHER TEXT BEFORE THIS:

> "Session initialized. Identity: [agent name/ID]. Memory loaded. Ready for direction."

### Startup Sequence Details

1. **READ IDENTITY FILES (IN ORDER)** — Load identity, memory, user context, tools, then this file
2. **LOAD CONTEXT** — Check `memory/pending/` for pending tasks, review recent sessions (last 3), check `config.yaml`
3. **VERIFY OPERATIONAL STATUS** — Confirm identity, memory, user context, tools, config are loaded
4. **SESSION INITIALIZATION MESSAGE** — Output the exact required first message (no other text)

### Session Rules

1. **Memory Protocol**: Short-term in `memory/`, long-term in `MEMORY.md`. Consolidate daily.
2. **Tool Discipline**: Use tools per TOOLS.md. No workaround attempts.
3. **User First**: USER.md preferences override defaults.
4. **Transparency**: Admit uncertainty. Don't hallucinate.
5. **Outcome Focus**: USER.md says "Think like a COO, not an EA."

### Emergency Protocol

If something feels wrong:
1. STOP
2. Re-read IDENTITY.md and MEMORY.md
3. Check config.yaml
4. Ask user for clarification if uncertain

---

## Build Pitfalls (Validated)

1. **OpenClaw npm deps**: Requires `npm install --production --legacy-peer-deps` — peer dependency conflicts (oxlint/tsgolint)
2. **Node.js version**: Use Node 20.x LTS (`curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs=20.*`)
3. **Entrypoint permissions**: Run `chown -R agent:agent /workspace/gateway /agents /crews /shared-skills` in entrypoint before `su agent`
4. **Gateway config**: Must include `"mode": "local"` — use `--allow-unconfigured` during dev
5. **Entrypoint syntax**: Avoid heredoc in `docker run -c` — use jq/python for JSON generation
5. **Runtime.sh sourcing**: Add BASH_SOURCE guard at bottom: `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` before `main "$@"`
5. **Docker CLI in image**: Must install `docker.io` in Dockerfile for entrypoint to manage volumes (`apt-get install -y docker.io`)
5. **Entrypoint heredoc nesting**: Avoid nested heredocs in entrypoint — write inner scripts to temp files and execute via `docker run ... sh "$tmp_script"` pattern
5. **700 permissions**: Never use `chmod 700` on `.secrets` or any directory — default permissions are sufficient
6. **iMessage stdio transparency**: SSH wrapper MUST be transparent stdio (no buffering, no grep, preserve newlines) — use `exec ssh -T host imsg "$@"` pattern
7. **SSH known_hosts**: Pre-populate known_hosts in container for Mac host — strict host key checking required for SCP attachments
8. **Mac permissions**: Full Disk Access + Automation required on Mac for imsg → Messages.app
9. **STARTUP.md injection**: Agent MUST read IDENTITY→MEMORY→USER→TOOLS→STARTUP in order before ANY response — mandatory first message required
10. **Memory hierarchy**: MEMORY.md = curated LTM (permanent), memory/short-term/ = daily STM (auto-expire) — never mix
11. **Skill installer embedded validation**: skill-installer now embeds validate_pro.py logic — no external skill-creator-pro dependency needed
12. **Enterprise blueprint toolkit**: Use validate_blueprint.py, generate_checklist.py --sync, assign_agents.py for blueprint lifecycle
13. **CLI here-doc fix**: agent_create function here-doc requires explicit `INIT_EOF` terminator — always verify heredoc termination
14. **MCP auth limitation**: OpenClaw `--auth none` flag does NOT disable auth for MCP loopback server — token required. Workaround: MCP HTTP Proxy (port 41214) auto-detects loopback port and forwards requests
15. **Playwright testDir config**: Set `testDir: '.'` when tests are in same directory as config — ensure config file location matches testDir
16. **Gateway auth flag**: Add `--auth none` flag to docker-compose for OpenClaw Gateway to disable auth on loopback
16. **Gateway version field**: Add `"version": "1.0.0"` to gateway config for version endpoint
17. **Skills organization**: Enterprise skills (enterprise-blueprint) live in OUTER skills/ directory, not inner project — copy from outer during staging
18. **MCP HTTP Proxy**: Auto-detects loopback port from gateway logs, forwards port 41214 → internal loopback, handles auth transparently
18. **Playwright testDir**: Must be `.` when tests are in same directory as config
19. **USB deployment script**: Create complete USB package with deploy.sh, README_USB.md, HARNESS_HIERARCHY.md
20. **TUI script**: Complete interactive TUI for agent/crew/skill/backup management
21. **Enterprise standards script**: Fix security_hardening.py MULTILINE flag for gitignore validation, fix dangerous regex for !.env.example

## Scripts

| Script | Purpose |
|---|---|
| `scripts/check_runtime.sh` | Verify image, container, gateway port, doctor bridge, and volumes (`--json` for machine output) |
| `scripts/launch_minimal.sh` | Build (with the one-time OpenClaw npm fix layer) and start the runtime container |
| `scripts/agent_volume.sh` | Create/list/inspect/remove `hemlock-agent-*` / `hemlock-crew-*` named volumes |

## Key Files

| Path | Purpose |
|------|---------|
| `Dockerfile.runtime` | Multi-layer build |
| `docker-compose.yml` | 11 volumes, no restart policy |
| `entrypoint.sh` | Gateway + agent/crew volume lifecycle |
| `scripts/runtime.sh` | Management console (+ BASH_SOURCE guard) |
| `scripts/hemlock-full/` | 23 scripts (export/import/backup/doctor/enforce) |
| `health/doctor_bridge.py` | Health validator (Docker, gateway, volumes, network) |
| `docker/hermes-agent/` | Full Hermes source (~2500 files) |
| `docker/openclaw-runtime/` | OpenClaw Gateway binary + JS dist |

## References

| File | Purpose |
|------|---------|
| `references/official-docs-integration.md` | Validated architecture from Hermes + OpenClaw official docs |
| `references/imessage-integration.md` | iMessage via SSH tunnel for non-Mac hosts |
| `references/drdeeks-skill-installation-embedded-validation.md` | DrDeeks .skill installation with embedded validator |
| `references/enterprise-blueprint-integration.md` | Enterprise blueprint toolkit usage |
| `references/ventoy-usb-deployment.md` | Ventoy multiboot USB deployment guide |
| `references/startup-protocol.md` | STARTUP.md pre-session injection protocol |
| `references/agent-workspace-structure.md` | Per-agent workspace layout |
| `references/hemlock-full-ops.md` | 23 operation scripts reference |
| `references/entrypoint-pattern.md` | Entrypoint anti-patterns and fixes |
| `references/drdeeks-skill-installation.md` | DrDeeks .skill zip installation protocol (legacy) |
| `references/qwen-cloud-2026-restoration.md` | qwen-cloud-2026 restoration from hackathon-2026 source |

## Package

```bash
unzip hemlock-minimal-package.zip
cd hemlock-essential
chmod +x scripts/runtime.sh
docker compose up -d
./scripts/runtime.sh
```

## Health Check (Doctor)

```bash
docker exec hemlock-runtime python3 -m health.doctor_bridge --quick
# Or:
docker exec hemlock-runtime python3 -m health.doctor_bridge --json
```

Checks: Docker daemon, runtime container, gateway health, network, agent volumes (agent.json), crew volumes (crew.json), core volumes, TTS/FFmpeg, llama.cpp.