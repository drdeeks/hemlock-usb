# TV Sitcom MCP — Deployment Guide

## Overview

This guide covers deploying the TV Sitcom MCP server in production environments.

## Deployment Options

### 1. Standalone Deployment

Run the MCP server as a standalone process:

```bash
# Start the server
python3 scripts/tv_mcp_server.py --host 0.0.0.0 --port 41208

# Or with systemd
sudo systemctl start tv-mcp-server
```

### 2. Docker Deployment

Run in a Docker container:

```dockerfile
FROM python:3.12-slim

WORKDIR /app
COPY . .
RUN pip install -r requirements.txt

EXPOSE 41208
CMD ["python3", "scripts/tv_mcp_server.py"]
```

```bash
# Build and run
docker build -t tv-mcp-server .
docker run -p 41208:41208 tv-mcp-server
```

### 3. Kubernetes Deployment

Deploy to Kubernetes:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tv-mcp-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: tv-mcp-server
  template:
    metadata:
      labels:
        app: tv-mcp-server
    spec:
      containers:
      - name: tv-mcp-server
        image: tv-mcp-server:latest
        ports:
        - containerPort: 41208
        env:
        - name: AUTH_TOKEN
          valueFrom:
            secretKeyRef:
              name: tv-mcp-secrets
              key: auth-token
```

## Configuration

### Environment Variables

```bash
# Server configuration
TV_MCP_HOST=0.0.0.0
TV_MCP_PORT=41208
TV_MCP_WORKERS=4

# Authentication
AUTH_TOKEN=your-secret-token

# Logging
LOG_LEVEL=INFO
LOG_FILE=/var/log/tv-mcp-server.log
```

### Configuration File

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
  },
  "logging": {
    "level": "INFO",
    "file": "/var/log/tv-mcp-server.log"
  }
}
```

## Monitoring

### Health Checks

```bash
# Check server health
curl http://localhost:41208/health

# Check room status
curl http://localhost:41208/rooms
```

### Metrics

```bash
# Get system status
curl http://localhost:41208/status

# Get agent feed
curl http://localhost:41208/feed
```

## Scaling

### Horizontal Scaling

Run multiple instances behind a load balancer:

```nginx
upstream tv_mcp {
    server 127.0.0.1:41208;
    server 127.0.0.1:41209;
    server 127.0.0.1:41210;
}

server {
    listen 80;
    location / {
        proxy_pass http://tv_mcp;
    }
}
```

### Vertical Scaling

Increase workers for higher throughput:

```bash
# Increase workers
python3 scripts/tv_mcp_server.py --workers 8
```

## Security

### Authentication

Use Bearer tokens for authentication:

```bash
# With token
curl -H "Authorization: Bearer your-token" http://localhost:41208/health
```

### Rate Limiting

Implement rate limiting to prevent abuse:

```python
from flask_limiter import Limiter

limiter = Limiter(app, default_limits=["100 per minute"])
```

### TLS/SSL

Enable TLS for secure connections:

```bash
# Generate self-signed certificate
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365

# Run with TLS
python3 scripts/tv_mcp_server.py --tls --cert cert.pem --key key.pem
```