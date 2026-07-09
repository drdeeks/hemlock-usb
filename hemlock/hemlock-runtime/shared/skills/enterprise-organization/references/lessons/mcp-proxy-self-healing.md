## MCP Proxy Manager with Self-Healing

### Architecture
- Gateway runs on main port (18789) for external access
- MCP loopback on random internal port (e.g., 43247) for agent communication
- Proxy (port 41214) auto-detects loopback port from gateway logs
- Proxy forwards `/mcp` requests with auth headers to internal loopback

### Auto-Detection Logic
```python
async def find_mcp_port():
    # 1. Parse gateway logs for "MCP loopback server listening on http://127.0.0.1:<port>/mcp"
    # 2. Use LAST match (most recent gateway restart)
    # 3. Fallback: scan ports 41000-42000 for responding MCP endpoint
```

### Systemd Service for Proxy
```ini
[Unit]
Description=Hemlock MCP Proxy Manager
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /home/ubuntu/hemlock-minimal/scripts/mcp_proxy_manager.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Container Cron Integration
```bash
# Inside container - runs on startup via entrypoint.sh
service cron start
crontab -l | grep -q "pull-drdeeks-daily" || (crontab -l; echo "0 2 * * * /scripts/pull-drdeeks-daily.sh") | crontab -
```

