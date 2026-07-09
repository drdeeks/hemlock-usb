# Dual-Mode Entrypoint Pattern — Single vs Multi-Container

## Overview

The Hemlock entrypoint supports **two modes** of agent execution, controlled by the `AGENT_MODE` setting in `runtime.sh`:

| Mode | Description | Use Case |
|------|-------------|----------|
| **single** (default) | Agents run as MCP bridges *inside* gateway container | Low resource overhead, simple deployment |
| **multi** | Each agent runs in its **own container** | Hard isolation, resource limits, independent scaling |

## Architecture Comparison

### Single-Container Mode (Default)

```
┌─────────────────────────────────────────────────────────┐
│  hemlock-runtime Container                              │
│  ┌─────────────────┐  ┌─────────────────────────────┐  │
│  │  OpenClaw       │  │  Hermes Brain               │  │
│  │  Gateway        │◄─►│  MCP Bridges (per agent)  │  │
│  │  Port 18789     │    │  python3 -m mcp_bridge    │  │
│  └─────────────────┘    └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

- All agents share the gateway process
- MCP bridges run as subprocesses in gateway container
- Lower memory overhead, single point of control

### Multi-Container Mode

```
┌─────────────────────────────────────────────────────────────────┐
│  hemlock-runtime (Gateway)                                      │
│  ┌─────────────────┐                                            │
│  │  OpenClaw       │                                            │
│  │  Gateway        │                                            │
│  │  Port 18789     │                                            │
│  └─────────────────┘                                            │
│         ▲                                                         │
│         │ Docker network + docker exec                           │
│  ┌──────┴──────┐  ┌──────────────────┐  ┌──────────────────┐   │
│  │ hemlock-    │  │ hemlock-agent-  │  │ hemlock-agent-   │   │
│  │ agent-A     │  │ B               │  │ C ...           │   │
│  └─────────────┘  └─────────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

- Each agent runs in its own container
- Gateway connects via `docker exec -i <container> python3 -m mcp_bridge`
- Hard isolation, resource limits, independent restarts

## Configuration

### runtime.sh Toggle

```bash
# In runtime.sh - option 0 toggles mode
load_config() {
    AGENT_MODE="${AGENT_MODE:-single}"  # single | multi
}
```

### EntryPoint Logic (`entrypoint.sh attach_agent`)

```bash
attach_agent() {
    local agent_id="${1:?agent id required}"
    local container="${2:-}"  # Optional: external container for multi-mode
    
    if [[ -n "$container" ]]; then
        # Multi-container mode: register external container
        jq --arg id "$agent_id" --arg container "$container" --arg ws "$workspace" \
            '.agents.list += [{"id": $id, "workspace": $ws}] | 
             .mcp.servers += {($id): {"command": "docker", "args": ["exec", "-i", $container, "python3", "-m", "mcp_bridge"], "env": {"AGENT_ID": $id, "HERMES_HOME": $ws}}}' \
            "$GATEWAY_CONFIG" > "$tmp" && mv "$tmp" "$GATEWAY_CONFIG"
    else
        # Single-container mode: MCP bridge in gateway
        jq --arg id "$agent_id" --arg ws "$workspace" \
            '.agents.list += [{"id": $id, "workspace": $ws}] | 
             .mcp.servers += {($id): {"command": "python3", "args": ["-m", "mcp_bridge"], "env": {"AGENT_ID": $id, "HERMES_HOME": $ws}}}' \
            "$GATEWAY_CONFIG" > "$tmp" && mv "$tmp" "$GATEWAY_CONFIG"
    fi
}
```

## Toggle Workflow

```bash
./scripts/runtime.sh
# Select option 0: "Agent Mode: Toggle (current: single)"
# → Switches to "multi"
# → Future agent-attach creates separate containers
```

## When to Use Multi-Container Mode

| Scenario | Recommended Mode |
|----------|------------------|
| Development / Testing | single (default) |
| Production with resource limits | multi |
| Agents need different resource limits | multi |
| Agents need independent restarts | multi |
| Security isolation required | multi |
| Simple deployment | single |

## Implementation Details

### Single-Container Attach
```bash
# MCP server registered as local subprocess
.mcp.servers += {
  "agent-id": {
    "command": "python3",
    "args": ["-m", "mcp_bridge"],
    "env": {"AGENT_ID": "agent-id", "HERMES_HOME": "/workspace"}
  }
}
```

### Multi-Container Attach
```bash
# MCP server registered as docker exec
.mcp.servers += {
  "agent-id": {
    "command": "docker",
    "args": ["exec", "-i", "hemlock-agent-agent-id", "python3", "-m", "mcp_bridge"],
    "env": {"AGENT_ID": "agent-id", "HERMES_HOME": "/workspace"}
  }
}
```

### Container Creation (runtime.sh)
```bash
agent_start_container() {
    local id="${1:?agent id required}"
    local vol="hemlock-agent-$id"
    local container="hemlock-agent-$id"
    
    docker run -d \
        --name "$container" \
        --network hemlock \
        -v "$vol:/workspace" \
        -e AGENT_ID="$id" \
        -e MODEL="$model" \
        -e OPENROUTER_API_KEY=*** \
        -e HERMES_HOME="/workspace" \
        --restart unless-stopped \
        hemlock/runtime:latest \
        python3 -m mcp_bridge
}
```

## Switching Modes

```bash
# In runtime.sh
0)  # Toggle agent mode
    if [[ "$AGENT_MODE" == "single" ]]; then
        AGENT_MODE="multi"
        log "Switched to MULTI-CONTAINER mode"
    else
        stop_all_agent_containers
        AGENT_MODE="single"
        log "Switched to SINGLE-CONTAINER mode"
    fi
    save_config
    ;;
```

## Key Differences

| Aspect | Single-Container | Multi-Container |
|--------|------------------|-----------------|
| **Isolation** | Process-level | Container-level |
| **Resources** | Shared | Per-container limits |
| **Restart** | All agents restart | Individual |
| **Memory** | Lower baseline | Higher baseline |
| **Debugging** | Single container logs | Multiple containers |
| **Scaling** | Vertical only | Horizontal + vertical |

## Migration Path

1. **Start with single-container** for development
2. **Test with multi-container** for staging
3. **Deploy multi-container** for production
4. **Toggle back** if issues arise (agents persist in volumes)