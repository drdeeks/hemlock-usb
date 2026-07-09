# Hemlock Wrapper Script & CLI

## Hemlock Wrapper (`/scripts/hemlock`)

```bash
#!/usr/bin/env bash
# Hemlock wrapper - launches the TUI
# This can be symlinked to /usr/local/bin/hemlock

# If running inside container, execute TUI directly
if [[ -f /.dockerenv ]] || [[ -n "${CONTAINER:-}" ]]; then
    exec /scripts/hemlock-tui
fi

# Otherwise exec into the container
exec docker exec -it hemlock-runtime /scripts/hemlock-tui
```

## Usage

```bash
# Add to shell config
echo 'alias hemlock="docker exec -it hemlock-runtime /scripts/hemlock-tui"' >> ~/.bashrc
source ~/.bashrc

# Now available everywhere
hemlock
```

## Inside Container

```bash
# Direct TUI
/entrypoint.sh tui
# or
/scripts/hemlock-tui

# Legacy runtime.sh (thin wrapper)
/scripts/runtime.sh
# If no args → launches TUI
# With args → delegates to entrypoint.sh
```

## Entrypoint CLI Commands

```bash
# Core gateway
gateway                          # Start OpenClaw Gateway (PID 1)
tui                              # Launch interactive TUI

# Agent lifecycle
agent-create <id> [model] [name]  # Create agent workspace + identity files
agent-attach <id>                 # Register MCP bridge in gateway config
agent-detach <id>                 # Unregister agent from gateway
agent-delete <id>                 # Destroy agent volume
agent-list                        # List from gateway + volumes

# Agent export/import
agent-export <id> [minimal|standard|full] [dest]
agent-import <src> <new_id> [mode]

# Skills
copy-skills <id> [skill1 skill2...]  # Copy skills from /skills to agent

# Crew lifecycle
crew-create <name> <agent_ids...>
crew-attach <name>
crew-detach <name>
crew-delete <name>
crew-list

# Skills volume
populate-skills [src]  # Populate /skills from /skills-source or arg
```

## Export/Import Workflow

### Export Agent
```bash
# From container
/entrypoint.sh agent-export analyst standard ./backup
# Creates: ./backup/analyst-standard-20260613-143022.tar.gz

# Modes:
# - minimal: agent.json, SOUL.md, IDENTITY.md, USER.md, TOOLS.md, MEMORY.md, STARTUP.md, HEARTBEAT.md, avatars/, tools/
# - standard: minimal + config.yaml, .env, .secrets/, HEARTBEAT.md, skills/, latest 5 sessions/, latest 5 memory/
# - full: entire volume
```

### Import Agent
```bash
# From container
/entrypoint.sh agent-import ./backup/analyst-standard-20260613.tar.gz analyst-restored standard
# Creates volume hemlock-agent-analyst-restored + extracts
# Then: /entrypoint.sh agent-attach analyst-restored
```

### Export Crew
```bash
/entrypoint.sh crew-export trading-desk full ./backup
# Includes all member agent volumes + crew config
```

## Runtime Wrapper (`/scripts/runtime.sh`)

```bash
#!/usr/bin/env bash
# Hemlock Management Console Entry Point
# This is a thin wrapper that either launches TUI or delegates to entrypoint.sh

# If no args, launch TUI
if [[ $# -eq 0 ]]; then
    exec /scripts/hemlock-tui
fi

# Otherwise delegate to entrypoint.sh
exec /entrypoint.sh "$@"
```

## Quick Start

```bash
# 1. Build
cd /home/ubuntu/hemlock-minimal
docker build -t hemlock/runtime:latest -f Dockerfile.runtime .

# 2. Start
docker compose up -d

# 3. Health check
timeout 5 bash -c '</dev/tcp/localhost/18789'

# 4. Run TUI
hemlock
# or
docker exec -it hemlock-runtime /scripts/hemlock-tui
```