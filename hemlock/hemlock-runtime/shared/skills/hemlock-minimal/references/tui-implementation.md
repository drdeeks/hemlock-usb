# Hemlock TUI Implementation

## Overview

The Hemlock TUI (`/scripts/hemlock-tui`) provides a full interactive terminal interface for managing the Hemlock Minimal system. It replaces the old `runtime.sh` menu with a proper arrow-key navigable interface.

## Entry Points

- `hemlock` (alias) → `docker exec -it hemlock-runtime /scripts/hemlock-tui`
- `/entrypoint.sh tui` (inside container)
- `/scripts/hemlock` (wrapper script)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        HEMLOCK TUI                              │
├─────────────────────────────────────────────────────────────────┤
│  Main Menu (11 options)                                         │
│  ├── 1. System Control                                          │
│  │   ├── Build Image                                            │
│  │   ├── Start/Stop/Restart Runtime                             │
│  │   ├── System Status                                           │
│  │   └── Doctor (Health Check)                                   │
│  ├── 2. Agent Management                                        │
│  │   ├── List All Agents                                        │
│  │   ├── Create/Attach/Detach/Delete Agent                      │
│  │   ├── Export/Import Agent (minimal|standard|full)           │
│  │   ├── Copy Skills to Agent                                    │
│  │   └── View Agent Workspace                                    │
│  ├── 3. Crew Management                                         │
│  │   ├── List/Create/Attach/Detach/Delete Crews                │
│  ├── 4. Gateway Config                                          │
│  │   ├── View/Validate Config                                   │
│  │   ├── iMessage/Telegram Configuration                        │
│  ├── 5. Skills & Volumes                                        │
│  │   ├── Populate Skills / List Skills                          │
│  │   ├── Backup/Restore All Volumes                             │
│  │   └── Cleanup Unused Volumes                                 │
│  ├── 6. iMessage & Channels                                     │
│  │   ├── Test/Pair iMessage                                     │
│  │   └── Configure Telegram                                     │
│  ├── 7. Import/Export                                           │
│  │   ├── Agent/Crew Import/Export (minimal|standard|full)      │
│  ├── 8. Backup/Restore                                          │
│  ├── 9. Health & Stats                                          │
│  │   ├── System Health / MCP Bridges / Resources                │
│  ├── 10. Settings                                               │
│  │   ├── Models, Providers, Environment                         │
├─────────────────────────────────────────────────────────────────┤
│  Navigation: ↑/↓ = move, Enter = select, q/Esc = back/quit     │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Details

### Main Components (`/scripts/hemlock-tui`)

1. **Data Fetching Functions**
   - `get_runtime_status()` — Docker container state
   - `get_gateway_health()` — TCP port 18789 check
   - `get_agent_count()` / `get_crew_count()` — Volume counts
   - `get_attached_agents()` — Gateway config parsing
   - `get_skills_count()` — Skills volume contents

2. **Rendering Functions**
   - `draw_header()` — Status bar with runtime/gateway/agents/crews/skills
   - `draw_main_menu()` — 11-option menu with selection highlight
   - `draw_agent_list()` — Attached + all agents table

3. **Input Handling**
   - Raw terminal mode (`stty -echo`)
   - Arrow keys via escape sequences (`\x1b[A` / `\x1b[B`)
   - Enter for selection, q/Esc for back/quit
   - Cleanup on exit (`trap cleanup EXIT INT TERM`)

4. **Sub-menu Pattern**
   - Each sub-menu uses same selection logic
   - Actions delegate to `/entrypoint.sh` commands
   - Status feedback after each action
   - `read -p "Press Enter..."` for confirmation

### Key UI Features

| Feature | Implementation |
|---|---|
| Header | Real-time status: Runtime, Gateway, Agents, Crews, Skills |
| Selection | Green highlight (`►`) with ANSCII colors |
| Data | Live queries via `docker exec`, `docker volume`, `jq` |
| Actions | Delegates to `/entrypoint.sh` for consistency |
| Cleanup | `trap cleanup EXIT INT TERM` restores terminal |

### Wrapper Scripts

**`/scripts/hemlock`** (host alias target):
```bash
if [[ -f /.dockerenv ]]; then
    exec /scripts/hemlock-tui
fi
exec docker exec -it hemlock-runtime /scripts/hemlock-tui
```

**`/scripts/runtime.sh`** (legacy compatibility):
```bash
if [[ $# -eq 0 ]]; then
    exec /scripts/hemlock-tui
fi
exec /entrypoint.sh "$@"
```

## Installation

The TUI is built into the Docker image:
```dockerfile
COPY scripts/hemlock-tui /scripts/hemlock-tui
RUN chmod +x /scripts/hemlock-tui
COPY scripts/hemlock /scripts/hemlock
RUN chmod +x /scripts/hemlock
```

## Usage

```bash
# From host (with alias)
alias hemlock="docker exec -it hemlock-runtime /scripts/hemlock-tui"
hemlock

# From container
/entrypoint.sh tui
# or
/scripts/hemlock-tui
```

## Design Principles

1. **No CLI memorization** — All operations discoverable via menus
2. **Real-time status** — Header always shows live system state
3. **Delegation** — TUI calls `/entrypoint.sh` for actual operations
4. **Consistency** — Same command paths whether via TUI or CLI
5. **Safety** — Confirmation prompts for destructive actions (delete)
6. **Responsiveness** — Non-blocking health checks, cached where possible