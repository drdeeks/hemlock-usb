# TV Sitcom MCP — Integration Guide

## Overview

This guide explains how to integrate the TV Sitcom MCP server into your business systems.

## Prerequisites

1. TV MCP server running on port 41208
2. MCP client library installed
3. Valid authentication token

## Integration Patterns

### 1. Dashboard Integration

Connect a monitoring dashboard to display real-time agent activity:

```python
from mcp_client import MCPClient

client = MCPClient("http://localhost:41208")

# Get room status
rooms = client.call("rooms")
print(f"Active rooms: {rooms['count']}")

# Get agent feed
feed = client.call("feed")
for item in feed['feed']:
    print(f"{item['agent']}: {item['action']}")
```

### 2. Alerting Integration

Set up alerts for specific agent actions:

```python
from mcp_client import MCPClient

client = MCPClient("http://localhost:41208")

# Monitor feed for alerts
feed = client.call("feed")
for item in feed['feed']:
    if item['action'] == 'error':
        send_alert(f"Agent {item['agent']} encountered an error")
```

### 3. Analytics Integration

Collect metrics for analysis:

```python
from mcp_client import MCPClient

client = MCPClient("http://localhost:41208")

# Get system status
status = client.call("status")
metrics = {
    "agents": status['agents'],
    "rooms": status['rooms'],
    "uptime": status['uptime']
}
store_metrics(metrics)
```

## Configuration

### Server Configuration

```json
{
  "server": {
    "host": "0.0.0.0",
    "port": 41208,
    "workers": 4
  },
  "auth": {
    "type": "bearer",
    "tokens": ["your-token-here"]
  }
}
```

### Client Configuration

```python
config = {
    "server_url": "http://localhost:41208",
    "token": "your-token-here",
    "timeout": 5,
    "retries": 3
}
```

## Best Practices

1. **Use connection pooling** for high-throughput scenarios
2. **Implement retry logic** for transient failures
3. **Cache responses** when real-time data isn't critical
4. **Monitor rate limits** to avoid throttling
5. **Use WebSocket** for real-time feed updates