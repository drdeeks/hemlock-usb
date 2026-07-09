# Entrypoint Dual-Mode Pattern

## attach_agent() Function

```bash
attach_agent() {
    local agent_id="${1:?agent id required}"
    local container="${2:-}"  # Optional: external container name for multi-container mode
    local vol="hemlock-agent-$agent_id"
    local mount_point="/agents/$agent_id"
    local workspace="$mount_point/workspace"
    
    if [[ -d "$workspace" ]]; then
        local tmp=$(mktemp)
        
        if [[ -n "$container" ]]; then
            # Multi-container mode: register external container as MCP server
            log "Attaching agent $agent_id via external container: $container"
            jq --arg id "$agent_id" --arg container "$container" --arg workspace "$workspace" \
                '.agents.list += [{"id": $id, "workspace": $workspace}] | 
                 .mcp.servers += {($id): {"command": "docker", "args": ["exec", "-i", $container, "python3", "-m", "mcp_bridge"], "env": {"AGENT_ID": $id, "HERMES_HOME": $workspace}}}' \
                "$GATEWAY_CONFIG" > "$tmp" && mv "$tmp" "$GATEWAY_CONFIG"
        else
            # Single-container mode: run MCP bridge in gateway container
            log "Attaching agent $agent_id (single-container mode)"
            jq --arg id "$agent_id" --arg workspace "$workspace" \
                '.agents.list += [{"id": $id, "workspace": $workspace}] | 
                 .mcp.servers += {($id): {"command": "python3", "args": ["-m", "mcp_bridge"], "env": {"AGENT_ID": $id, "HERMES_HOME": $workspace}}}' \
                "$GATEWAY_CONFIG" > "$tmp" && mv "$tmp" "$GATEWAY_CONFIG"
        fi
        
        log "Agent $agent_id attached at $workspace"
        return 0
    else
        error "Agent workspace not found at $workspace"
        return 1
    fi
}
```

## Key Differences

| Aspect | Single-Container Mode | Multi-Container Mode |
|--------|----------------------|---------------------|
| MCP command | `python3 -m mcp_bridge` | `docker exec -i <container> python3 -m mcp_bridge` |
| Process lifecycle | Gateway owns bridge process | Agent container owns bridge process |
| Resource isolation | Shared cgroup | Per-container cgroup |
| API key injection | Read from volume `.env` | Passed as `-e` env var at `docker run` |
| OOM behavior | Kills gateway + all agents | Kills only that agent's container |
| `/proc` visibility | Sees all agent PIDs | Only sees own container PIDs |

## Gateway Config (openclaw.json) Structure

```json
{
  "gateway": { "port": 18789, "bind": "0.0.0.0", "token": "..." },
  "agents": { "defaults": { "workspace": "/workspace", "skills": [] }, "list": [...] },
  "channels": { "telegram": { "accounts": {}, "defaultAccount": "" } },
  "bindings": [],
  "mcp": { "servers": {
    "agent-1": { "command": "python3", "args": ["-m", "mcp_bridge"], "env": {...} },
    "agent-2": { "command": "docker", "args": ["exec", "-i", "hemlock-agent-2", "python3", "-m", "mcp_bridge"], "env": {...} }
  }}
}
```