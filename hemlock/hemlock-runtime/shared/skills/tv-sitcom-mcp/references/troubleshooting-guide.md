# TV Sitcom MCP — Troubleshooting Guide

## Overview

This guide covers common issues and solutions for the TV Sitcom MCP server.

## Common Issues

### 1. Server Won't Start

**Symptoms:**
- Server fails to start
- Port already in use error

**Solutions:**

```bash
# Check if port is in use
lsof -i :41208

# Kill process using the port
kill -9 <PID>

# Or use a different port
python3 scripts/tv_mcp_server.py --port 41209
```

### 2. Authentication Errors

**Symptoms:**
- 401 Unauthorized errors
- Token rejected

**Solutions:**

```bash
# Verify token is valid
curl -H "Authorization: Bearer your-token" http://localhost:41208/health

# Check token configuration
cat config.json | jq '.auth.tokens'
```

### 3. Connection Timeouts

**Symptoms:**
- Client connections timeout
- Slow response times

**Solutions:**

```bash
# Check server status
curl http://localhost:41208/status

# Increase timeout in client
config = {"timeout": 10}

# Check network connectivity
ping localhost
```

### 4. Empty Feed

**Symptoms:**
- Feed endpoint returns empty array
- No agent activity shown

**Solutions:**

```bash
# Check if agents are connected
curl http://localhost:41208/status

# Verify agent configuration
cat config.json | jq '.agents'

# Restart agents
systemctl restart hermes-agents
```

### 5. High Memory Usage

**Symptoms:**
- Server consuming excessive memory
- Out of memory errors

**Solutions:**

```bash
# Monitor memory usage
top -p $(pgrep -f tv_mcp_server)

# Reduce feed history
# In config.json:
# "feed_history": 100

# Restart server
systemctl restart tv-mcp-server
```

## Debug Mode

Enable debug mode for detailed logging:

```bash
# Start with debug logging
python3 scripts/tv_mcp_server.py --debug

# Or set environment variable
export TV_MCP_DEBUG=true
python3 scripts/tv_mcp_server.py
```

## Log Analysis

### Check Logs

```bash
# View recent logs
tail -f /var/log/tv-mcp-server.log

# Search for errors
grep "ERROR" /var/log/tv-mcp-server.log

# Search for warnings
grep "WARN" /var/log/tv-mcp-server.log
```

### Common Log Messages

| Message | Meaning | Solution |
|---------|---------|----------|
| `Connection refused` | Server not running | Start server |
| `Token expired` | Authentication token expired | Generate new token |
| `Rate limit exceeded` | Too many requests | Wait or increase limits |
| `Agent disconnected` | Agent lost connection | Check agent status |

## Performance Issues

### Slow Response Times

```bash
# Check server load
uptime

# Monitor response times
curl -w "@curl-format.txt" -o /dev/null -s http://localhost:41208/health

# Increase workers
python3 scripts/tv_mcp_server.py --workers 8
```

### High CPU Usage

```bash
# Monitor CPU usage
top -p $(pgrep -f tv_mcp_server)

# Reduce polling frequency
# In config.json:
# "poll_interval": 5
```

## Recovery Procedures

### Server Crash Recovery

```bash
# Check if server is running
systemctl status tv-mcp-server

# Restart if crashed
sudo systemctl restart tv-mcp-server

# Check logs for crash reason
journalctl -u tv-mcp-server --since "1 hour ago"
```

### Data Recovery

```bash
# Backup current data
cp /var/lib/tv-mcp-server/data.json /backup/

# Restore from backup
cp /backup/data.json /var/lib/tv-mcp-server/
```

## Getting Help

### Check Documentation

- API Reference: `references/api-reference.md`
- Integration Guide: `references/integration-guide.md`
- Deployment Guide: `references/deployment-guide.md`

### Contact Support

- Email: support@example.com
- Slack: #tv-mcp-support
- GitHub: https://github.com/.../tv-sitcom-mcp