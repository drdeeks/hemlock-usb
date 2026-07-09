## OpenClaw Gateway Authentication & MCP Loopback Handling

### Authentication Modes
- `--auth none`: Disables auth for main gateway endpoints only
- `--auth token`: Requires `Authorization: Bearer *** header
- **Loopback auth separate**: MCP loopback server has its own auth (always on)

### MCP Loopback Server Behavior
- Random port assigned on each gateway startup (e.g., 41213, 39925, 43247)
- Port logged in gateway stdout: `MCP loopback server listening on http://127.0.0.1:<port>/mcp`
- Requires `Authorization: Bearer *** where token = gateway config token
- Token changes on every gateway restart (generated via `crypto.randomBytes(32)`)

### Gateway Configuration
```json
{
  "gateway": {"port": 18789, "mode": "local", "token": "test-token-12345"},
  "mcp": {"servers": {"hemlock-mcp": {"command": "python3", "args": ["-m", "mcp_bridge"], "transport": "stdio"}}},
  "agents": {"defaults": {"workspace": "/workspace", "skills": []}, "allowUnconfigured": true}
}
```

### Common Failures & Fixes
| Error | Cause | Fix |
|-------|-------|-----|
| `{"error":"unauthorized"}` on MCP | Loopback auth required | Use `Authorization: Bearer *** header |
| MCP port unreachable | Internal loopback only | Use proxy or test from container |
| Token mismatch | Gateway restarted | Re-read token from `/workspace/gateway/.token` |

