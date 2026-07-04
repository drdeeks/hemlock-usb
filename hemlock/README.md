# Hemlock Agent Runtime

Dockerized AI agent orchestration platform. Runs inside a container with Bash orchestration, Python health checks, and Node.js openclaw gateway.

---

## Quick Start

```bash
# Launch via master menu
bash ../menu.sh   # → Option 8: Hemlock TUI

# Or directly
export HEMLOCK_DIR=$(pwd)/hemlock-runtime
bash hemlock-tui

# Or via the hemlock CLI
bash hemlock-runtime/scripts/hemlock menu
```

## Architecture

```
hemlock/
├── DEPLOY.sh                    # Master deploy (system + USB + Hemlock)
├── hemlock-tui                  # Wrapper to launch TUI
├── hemlock-runtime/
│   ├── scripts/
│   │   ├── hemlock              # Host CLI entrypoint
│   │   ├── runtime.sh           # In-container TUI menu (1334 lines)
│   │   ├── hemlock-stage.sh     # Import/export staging
│   │   ├── agent-*.sh           # Agent lifecycle (create/delete/export/import/start/stop/monitor)
│   │   ├── crew-*.sh            # Crew lifecycle (create/dissolve/export/import/join/leave/start/stop)
│   │   ├── docker/              # Docker-specific scripts (import/export/backup/restore)
│   │   ├── system/              # System scripts (doctor, security, hardware, models)
│   │   ├── self-healing/        # Health checks
│   │   ├── lib/common.sh        # Shared utilities
│   │   └── health-check.sh      # Health validation
│   ├── docker-compose.runtime.yml  # Primary compose (runtime/agent/doctor/setup)
│   ├── docker-compose.yml          # Framework compose (single framework service)
│   ├── Dockerfile.runtime          # Runtime image
│   ├── Dockerfile.agent            # Agent image
│   ├── Dockerfile.crew             # Crew image
│   ├── Dockerfile.doctor           # Doctor image
│   ├── Makefile                    # Build targets
│   └── volumes/                    # Persistent data
│       ├── imports/.request        # Staging protocol
│       ├── agents/                 # Agent workspaces
│       ├── crews/                  # Crew workspaces
│       ├── models/                 # AI models
│       ├── skills/                 # Skill packages
│       └── config/                 # Runtime config
└── hemlock-minimal/
    └── skills/                    # 84 agent skill packages
```

## Container Lifecycle

```bash
# Start runtime
docker compose -f docker-compose.runtime.yml up -d

# Check status
docker ps | grep hemlock_runtime

# Stop runtime
docker compose -f docker-compose.runtime.yml down

# Rebuild images
docker compose -f docker-compose.runtime.yml build
```

## CLI Commands

```bash
hemlock menu            # Launch TUI menu
hemlock status          # Check runtime status
hemlock shell           # Open shell in container
hemlock import FILE     # Import file to container
hemlock export FILE     # Export file from container
hemlock crew-import     # Import crew
hemlock crew-export     # Export crew
hemlock list-imports    # List staged imports
hemlock up              # Start containers
hemlock down            # Stop containers
```

## Import/Export Staging

Files are staged via a `volumes/imports/.request` protocol:

1. **Host → Container:** Place file in `volumes/imports/.request/`, the `watch_requests` loop picks it up
2. **Container → Host:** Run `hemlock export FILE` inside the TUI, then run the printed host command

## Ports

| Port | Service |
|------|---------|
| 18789 | Openclaw gateway (Node.js) |
| 41214 | MCP proxy |
| 22 | SSH (forwarded from host) |

## Post-Deploy Steps

```bash
source ~/.profile
source ~/.cargo/env
tailscale up
docker ps | grep hemlock
```
