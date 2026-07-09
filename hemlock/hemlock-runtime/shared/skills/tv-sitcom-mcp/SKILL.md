---
name: tv-sitcom-mcp
description: "MCP server exposing the agent TV room as an external API. Provides real-time agent/room/feed access for any company integrating agent TV into their business."
version: 1.0.1
license: MIT
metadata:
  category: devops
  tags:
    - mcp
    - tv-room
    - agent-monitoring
    - external-api
    - federation
    - real-time
    - production-ready
  depends_on:
    - autonomous-crew-integration
    - crew-knowledge-system
  provides:
    - tv-room-mcp
    - agent-feed-api
    - room-status-api
    - project-summary-api
    - system-status-api
  compatible_with:
    - openclaw-gateway
    - hermes-agent
    - any-mcp-client
---
# TV Sitcom Show MCP Server

## Overview

Exposes the agent TV room as an MCP (Model Context Protocol) server. Any company can connect via standard MCP clients to get real-time agent feeds, room status, project summaries, and system health.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL COMPANY                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │  MCP Client │  │  MCP Client │  │  MCP Client │             │
│  │ (Dashboard) │  │ (Alerting)  │  │ (Analytics) │             │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          ▼                                        │
│              ┌─────────────────────────┐                         │
│              │      MCP Transport      │                         │
│              │  (HTTP / WebSocket)     │                         │
│              └───────────┬─────────────┘                         │
└──────────────────────────┼──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AUTONOMOUS CREW ENTERPRISE                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              TV Sitcom Show MCP Server                   │   │
│  │  Port: 41208 | Host: 0.0.0.0 | Transport: Streamable-HTTP│   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│                          ▼                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Federation Gateway (Port 41207)             │   │
│  │  5 Projects | 15 Rooms | 175 Agents | Real-time WebSocket│   │
│  └─────────────────────────────────────────────────────────┘   │
```

## MCP Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `get_all_rooms` | All production rooms across 5 projects | — |
| `get_room` | Detailed room view with all agents | `room_id: string` |
| `get_tv_feed` | Live agent activity feed | `limit?`, `project?`, `priority?` |
| `get_agent` | Agent profile by ID | `agent_id: string` |
| `get_project_summary` | Project stats | `project: string` |
| `get_system_status` | Global health & stats | — |
| `search_agents` | Search by name/role/project | `query: string` |

## MCP Resources

| Resource | Description |
|----------|-------------|
| `config://projects` | Project definitions (name, emoji, color) |
| `config://rooms` | Room configuration schema |

## Connection

```bash
# Start server
python3 scripts/tv_mcp_server.py

# Or with custom config
TV_MCP_PORT=41208 TV_VAULT_PATH=/path/to/vault python3 scripts/tv_mcp_server.py
```

### MCP Client Config (Claude Desktop)
```json
{
  "mcpServers": {
    "tv-sitcom": {
      "command": "python3",
      "args": ["/path/to/scripts/tv_mcp_server.py"],
      "env": {
        "TV_MCP_PORT": "41208",
        "TV_VAULT_PATH": "/path/to/vault"
      }
    }
  }
}
```

### MCP Client Config (Any HTTP Client)
```python
import httpx

client = httpx.Client(base_url="http://localhost:41208")
# Tools called via POST /mcp/tools/call
```

## TV Feed Format

```json
{
  "timestamp": "2026-07-05T12:00:00Z",
  "event_type": "agent_registered",
  "agent_id": "MN-01",
  "agent_name": "Scribe",
  "project": "mnemosyne",
  "message": "joined the production",
  "priority": "high"
}
```

## Project Definitions

| Project | Emoji | Color | Track |
|---------|-------|-------|-------|
| mnemosyne | 🧠 | #3b82f6 | MemoryAgent |
| agora | 🏛️ | #f59e0b | Agent Society |
| aires | 🎬 | #a855f7 | AI Showrunner |
| autopilot | ⚙️ | #22c55e | Autopilot Agent |
| edgewalker | ⚡ | #ef4444 | EdgeAgent |

## Room Structure

- **Max 35 agents per room** (overflow to production rooms)
- **3 rooms per project** (1 main + 2 production)
- **5 projects × 3 rooms = 15 total rooms**
- **175 agent capacity** (35 × 5 main rooms)

## External Integration Examples

### Dashboard Integration
```python
import httpx

async def get_live_feed():
    async with httpx.AsyncClient(base_url="http://hemlock:41208") as client:
        response = await client.post("/mcp/tools/call", json={
            "name": "get_tv_feed",
            "arguments": {"limit": 100, "priority": "high"}
        })
        return response.json()
```

### Alerting System
```python
async def check_critical_errors():
    feed = await get_tv_feed(priority="high", limit=50)
    errors = [f for f in feed if f["event_type"] == "error"]
    if errors:
        await send_alert(errors)
```

## Deployment

```yaml
# docker-compose.yml
services:
  tv-mcp:
    image: python:3.12-slim
    ports:
      - "41208:41208"
    volumes:
      - ./memory:${WORKSPACE_ROOT}/qwen-cloud-2026/memory
    command: python3 scripts/tv_mcp_server.py
    environment:
      - TV_MCP_PORT=41208
      - TV_VAULT_PATH=${WORKSPACE_ROOT}/qwen-cloud-2026/memory
```

## Security

- No authentication built-in (add reverse proxy for auth)
- Read-only API (no mutating operations)
- Rate limit at reverse proxy level
- Internal network only by default

## Free-First

| Tier | Cost | Stack |
|------|------|-------|
| Free | $0/mo | Python 3.12+ stdlib + fastmcp (pip install) |
| Paid | None required | — |