#!/bin/bash
# =============================================================================
# Health Check Script
# Comprehensive system health verification
# =============================================================================

set +euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

log() { echo -e "${BLUE}[----]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)) || true; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)) || true; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)) || true; }

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Health Check Script                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Docker health
echo "=== Docker Services ==="
if docker ps &> /dev/null; then
    pass "Docker daemon is responsive"
else
    fail "Docker daemon is not responsive"
fi

# Gateway health
echo ""
echo "=== OpenClaw Gateway ==="
GATEWAY_RUNNING=$(docker ps --filter "name=gateway" --filter "status=running" -q 2>/dev/null)
if [[ -n "$GATEWAY_RUNNING" ]]; then
    pass "Gateway container is running"
    
    # Check gateway health
    if docker exec openclaw-gateway openclaw gateway status &> /dev/null; then
        pass "Gateway is healthy"
    else
        warn "Gateway may not be fully healthy"
    fi
else
    warn "Gateway container is not running"
fi

# Hermes agents
echo ""
echo "=== Hermes Agents ==="
AGENT_COUNT=$(docker ps --filter "name=oc-" --filter "status=running" -q 2>/dev/null | wc -l)
if [[ $AGENT_COUNT -gt 0 ]]; then
    pass "Running agents: $AGENT_COUNT"
    shopt -s nullglob
    for container in $(docker ps --filter "name=oc-" --filter "status=running" --format "{{.Names}}" 2>/dev/null); do
        log "  - $container"
    done
else
    warn "No Hermes agents are running"
fi

# Network connectivity
echo ""
echo "=== Network Connectivity ==="

# Check Ollama
if curl -sf --max-time 2 http://host.docker.internal:11434/api/tags &> /dev/null; then
    pass "Ollama is reachable"
else
    warn "Ollama is not reachable"
fi

# Check gateway port
if curl -sf --max-time 2 http://localhost:18789/health &> /dev/null; then
    pass "Gateway port 18789 is reachable"
else
    warn "Gateway port 18789 is not reachable"
fi

# Check DNS
if ping -c 1 -W 1 host.docker.internal &> /dev/null || \
   curl -sf --max-time 1 http://host.docker.internal &> /dev/null; then
    pass "Docker internal DNS is working"
else
    warn "Docker internal DNS may have issues"
fi

# Disk space
echo ""
echo "=== System Resources ==="

# Disk usage
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ -n "$DISK_USAGE" ]]; then
    if [[ $DISK_USAGE -lt 80 ]]; then
        pass "Disk usage: ${DISK_USAGE}%"
    elif [[ $DISK_USAGE -lt 90 ]]; then
        warn "Disk usage is high: ${DISK_USAGE}%"
    else
        fail "Disk usage is critical: ${DISK_USAGE}%"
    fi
fi

# Memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100)}')
if [[ -n "$MEMORY_USAGE" ]]; then
    if [[ $MEMORY_USAGE -lt 80 ]]; then
        pass "Memory usage: ${MEMORY_USAGE}%"
    elif [[ $MEMORY_USAGE -lt 90 ]]; then
        warn "Memory usage is high: ${MEMORY_USAGE}%"
    else
        fail "Memory usage is critical: ${MEMORY_USAGE}%"
    fi
fi

# CPU load
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
if [[ -n "$LOAD_AVG" ]]; then
    log "Load average: $LOAD_AVG"
fi

# Agent health checks
echo ""
echo "=== Agent Health ==="
shopt -s nullglob
for container in $(docker ps --filter "name=oc-" -q 2>/dev/null); do
    CONTAINER_NAME=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^\///')
    
    # Check if container is healthy
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
    
    if [[ "$STATUS" == "running" ]]; then
        pass "Container $CONTAINER_NAME is running"
        
        if [[ "$HEALTH" == "healthy" ]]; then
            pass "Container $CONTAINER_NAME is healthy"
        elif [[ "$HEALTH" == "unhealthy" ]]; then
            fail "Container $CONTAINER_NAME is unhealthy"
        else
            log "  Health status: $HEALTH"
        fi
    else
        fail "Container $CONTAINER_NAME is $STATUS"
    fi
    
    # Check container uptime
    UPTIME=$(docker inspect --format='{{.State.StartedAt}}' "$container" 2>/dev/null)
    if [[ -n "$UPTIME" ]]; then
        log "  Started: $UPTIME"
    fi
done

# Summary
echo ""
echo "=== Summary ==="
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Warnings:${NC} $WARN"
echo ""

if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    echo -e "${GREEN}✓ All health checks passed!${NC}"
    exit 0
elif [[ $FAIL -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Health checks passed with warnings${NC}"
    exit 0
else
    echo -e "${RED}✗ Health checks failed${NC}"
    exit 1
fi