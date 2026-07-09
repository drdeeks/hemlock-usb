# Official Docs Integration Pattern

This document captures the **validated integration pattern** from official Hermes and OpenClaw documentation.

## Sources Consulted

| Source | URL | Key Findings |
|--------|-----|--------------|
| Hermes Architecture | https://hermes-agent.nousresearch.com/docs/developer-guide/architecture | Entry points, agent loop internals, API modes, turn lifecycle |
| Hermes MCP | https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp | MCP server connection, automatic tool discovery |
| OpenClaw Multi-Agent | https://docs.openclaw.ai/concepts/multi-agent | Isolated agents, channel accounts, bindings, agentDir |
| OpenClaw Agent Loop | https://docs.openclaw.ai/concepts/agent-loop | Intake → context → inference → tools → streaming → persistence |
| OpenClaw Agent Runtimes | https://docs.openclaw.ai/concepts/agent-runtimes | Runtime vs provider vs model vs channel layers |
| OpenClaw Sub-agents | https://docs.openclaw.ai/tools/subagents | Background runs, sessions_spawn, sessions_yield |
| OpenClaw Telegram | https://docs.openclaw.ai/channels/telegram | Pairing, DM policy, groups, allowFrom |
| OpenClaw Config Tools | https://docs.openclaw.ai/gateway/config-tools | Tool profiles, MCP servers, sandbox tools |
| OpenClaw System Prompt | https://docs.openclaw.ai/concepts/system-prompt | Three-layer prompt assembly, provider contributions |

## Validated Architecture Decision

### Who Runs The Show?

| Layer | Component | Role | Owner |
|-------|-----------|------|-------|
| **Gateway (Control Plane)** | **OpenClaw Gateway** | Message routing, Telegram, sessions, auth, bindings | **OpenClaw** |
| **Agent Runtime** | **Hermes Brain** | Cognition, agent loop, tool execution, memory | **Hermes** |
| **MCP Provider** | **OpenClaw** | Exposes `mcp_bridge` as MCP servers to Hermes | **OpenClaw** |
| **Channel** | **Telegram (OpenClaw)** | DMs, groups, pairing, commands | **OpenClaw** |

**✅ OpenClaw RUNS THE SHOW** — it owns:
- Gateway process (port 18789)
- Telegram bot connection (grammY)
- Session management + transcript persistence (file-based, write-locked)
- Agent routing via bindings
- System prompt assembly (three layers)

**Hermes runs as MCP servers** — each agent = 1 MCP server registered in OpenClaw config.

### Data Flow

```
OpenClaw Gateway (Single Process)
├─ Telegram (grammY) ──► Bindings ──► Agent Routing
├─ Sessions (file-based, write-locked) ──► Transcript persistence
├─ Queueing (per-session lane + global lane) ──► Concurrency control
└─ MCP Client (stdio) ──► Spawns python3 -m mcp_bridge per agent
                            │
                            ▼
                   Hermes MCP Bridge (per agent)
                   ├─ Reads AGENT_ID from env
                   ├─ Loads workspace: STARTUP.md, IDENTITY.md, MEMORY.md, USER.md, TOOLS.md
                   ├─ Builds Hermes AIAgent with agent-specific config
                   └─ Starts MCP stdio server (JSON-RPC over stdio)
```

### Gateway Config (Single Source of Truth)

```json
{
  "gateway": { "port": 18789, "bind": "0.0.0.0", "token": "***", "mode": "local" },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "***",
      "dmPolicy": "pairing",
      "groups": {
        "crew-trading-desk": { "requireMention": true }
      }
    }
  },
  "agents": {
    "defaults": { 
      "workspace": "/workspace",
      "model": "openrouter/anthropic/claude-sonnet-4",
      "subagents": { "model": "openrouter/anthropic/claude-sonnet-4" }
    },
    "list": [
      { "id": "analyst", "workspace": "/workspace/agents/analyst" },
      { "id": "executor", "workspace": "/workspace/agents/executor" }
    ]
  },
  "bindings": [
    { "match": { "channel": "telegram", "accountId": "default" }, "agentId": "analyst" }
  ],
  "mcp": {
    "servers": {
      "analyst": { "command": "python3", "args": ["-m", "mcp_bridge"], "env": { "AGENT_ID": "analyst" } },
      "executor": { "command": "python3", "args": ["-m", "mcp_bridge"], "env": { "AGENT_ID": "executor" } }
    }
  },
  "tools": {
    "profile": "full",
    "sandbox": { "tools": { "alsoAllow": ["bundle-mcp"] } }
  }
}
```

Key config points:
- `"mode": "local"` required in gateway object
- `mcp.servers` uses provider-safe prefixes for sandbox tools
- `tools.sandbox.tools.alsoAllow: ["bundle-mcp"]` required for MCP tools in sandbox
- `agents.defaults.subagents.model` for sub-agent model selection

## Tool Initiation Protocol

### Correct Sequence

1. **OpenClaw Starts Gateway**
   ```bash
   exec su agent -c "OPENCLAW_CONFIG_PATH=/workspace/gateway/openclaw.json openclaw gateway run"
   ```

2. **Gateway Auto-Registers MCP Servers**
   - Reads `mcp.servers` config
   - Spawns `python3 -m mcp_bridge` per agent via stdio

3. **Hermes MCP Bridge Initializes**
   ```python
   # mcp_bridge.py
   # 1. Reads AGENT_ID from env
   # 2. Loads agent workspace (/workspace/agents/<id>/)
   # 3. Reads STARTUP.md, IDENTITY.md, MEMORY.md, USER.md, TOOLS.md
   # 4. Builds Hermes AIAgent with agent-specific config
   # 5. Starts MCP stdio server
   ```

4. **Telegram Commands Work Natively (OpenClaw side)**
   - `/subagents list` → OpenClaw built-in
   - `/focus <session>` → OpenClaw built-in
   - `/session idle 30m` → OpenClaw built-in
   - DM routing → OpenClaw bindings

**Hermes never sees these commands** — they're handled at Gateway level.

## Self-Learning: Both Layers

### Hermes Side (MCP Server)
- Via `memory` tool + `session_search` + LTM consolidation (config-driven)
- STARTUP.md injected at session start (our implementation)
- IDENTITY.md + MEMORY.md + USER.md + TOOLS.md → System prompt context

### OpenClaw Side (Gateway)
- Via session transcripts + bootstrap files + skill loading
- System prompt auto-assembled per run (three layers)
- Provider plugins contribute cache-aware prompt guidance

## Per-Agent Workspace (Validated)

```
/workspace/agents/<agent_id>/
├── agent.json          # Identity + model (OpenClaw reads)
├── SOUL.md             # Personality (injected into system prompt)
├── IDENTITY.md         # Core identity (Hermes STARTUP reads)
├── MEMORY.md           # Curated LTM (Hermes STARTUP reads)
├── USER.md             # User profile (Hermes STARTUP reads)
├── TOOLS.md            # Tool guidelines (Hermes STARTUP reads)
├── STARTUP.md          # MANDATORY pre-session injection (Hermes reads FIRST)
├── config.yaml         # Hermes runtime config
├── .env                # API keys (600 perms)
├── memory/
│   ├── short-term/     # Daily raw memories (auto-expire)
│   ├── long-term/      # Promoted memories (pre-consolidation)
│   ├── pending/        # Awaiting consolidation
│   └── archived/       # Old consolidated
├── sessions/           # Session markers
├── skills/             # Installed skills
├── tools/              # Custom tools
├── .secrets/           # Secrets (default perms, NO 700)
├── logs/
├── projects/
└── shared-skills -> /shared-skills
```

## Memory Hierarchy (Critical)

| Location | Purpose | Lifetime | Owner |
|----------|---------|----------|-------|
| `memory/short-term/` | Daily raw memories, auto-expire | Days | Hermes |
| `memory/long-term/` | Promoted memories (pre-consolidation) | Weeks | Hermes |
| `memory/pending/` | Items awaiting consolidation | Active | Hermes |
| `memory/archived/` | Old consolidated memories | Months+ | Hermes |
| `MEMORY.md` | **Curated LTM** (manual consolidation) | Permanent | Hermes |

## Build Pitfalls (from docs + testing)

| Pitfall | Solution |
|---------|----------|
| OpenClaw npm deps peer conflicts | `npm install --production --legacy-peer-deps` |
| Node.js version | Use Node 20.x LTS via nodesource |
| Entrypoint permissions | `chown -R agent:agent` before `su agent` |
| Gateway config mode | Must include `"mode": "local"` |
| JSON in entrypoint heredoc | Use jq/python, not nested heredocs |
| Runtime.sh sourcing | Add `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` |
| Docker CLI in image | Install `docker.io` in Dockerfile |
| 700 permissions | Never use — default perms sufficient |

## Key Differences from Previous Architecture

| Aspect | Old (Incorrect) | New (Validated) |
|--------|-----------------|-----------------|
| Gateway owner | Hermes | **OpenClaw** |
| Telegram handling | Hermes | **OpenClaw** |
| Session management | Hermes | **OpenClaw** |
| Agent routing | Hermes | **OpenClaw (bindings)** |
| System prompt | Hermes | **OpenClaw (3 layers)** |
| MCP registration | Manual | **OpenClaw config** |
| Sub-agents | Hermes | **OpenClaw (sessions_spawn)** |
| Hermes role | Gateway + brain | **MCP server only** |