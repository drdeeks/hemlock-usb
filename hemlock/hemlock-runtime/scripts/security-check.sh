#!/bin/bash
# =============================================================================
# Security Check Script
# Verifies security configuration and best practices
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
echo -e "${BLUE}║   Security Check Script                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# Network Isolation
# =============================================================================

echo "=== Network Isolation ==="

# Check icc: false in docker-compose
if grep -q "enable_icc.*false" "${RUNTIME_ROOT}/docker-compose.yml" 2>/dev/null; then
    pass "Inter-container communication (icc) is disabled"
else
    fail "Inter-container communication (icc) is NOT disabled"
fi

# Check for network isolation
if grep -q "network.*:" "${RUNTIME_ROOT}/docker-compose.yml" 2>/dev/null; then
    pass "Custom networks are configured"
else
    warn "No custom networks found"
fi

# Check if containers are on isolated networks
shopt -s nullglob
for container in $(docker ps --format "{{.Names}}" 2>/dev/null); do
    NETWORKS=$(docker inspect --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$container" 2>/dev/null)
    if echo "$NETWORKS" | grep -q "agents_net\|bridge"; then
        log "  $container is on isolated network"
    fi
done

# =============================================================================
# Capability Dropping
# =============================================================================

echo ""
echo "=== Linux Capabilities ==="

if grep -q "cap_drop" "${RUNTIME_ROOT}/docker-compose.yml" 2>/dev/null; then
    CAP_DROP=$(grep "cap_drop" "${RUNTIME_ROOT}/docker-compose.yml" | head -1)
    if echo "$CAP_DROP" | grep -q "ALL"; then
        pass "All capabilities are dropped (cap_drop: ALL)"
    else
        warn "Some capabilities are dropped but not ALL"
    fi
else
    fail "cap_drop is NOT configured"
fi

# =============================================================================
# Security Options
# =============================================================================

echo ""
echo "=== Security Options ==="

if grep -q "no-new-privileges" "${RUNTIME_ROOT}/docker-compose.yml" 2>/dev/null; then
    pass "No new privileges is configured"
else
    fail "No new privileges is NOT configured"
fi

if grep -q "read_only.*true" "${RUNTIME_ROOT}/docker-compose.yml" 2>/dev/null; then
    pass "Read-only filesystem is configured"
else
    warn "Read-only filesystem is NOT configured"
fi

if grep -q "tmpfs" "${RUNTIME_ROOT}/docker-compose.yml" 2>/dev/null; then
    pass "Tmpfs is configured for sensitive directories"
else
    warn "Tmpfs is NOT configured"
fi

# =============================================================================
# User Isolation
# =============================================================================

echo ""
echo "=== User Isolation ==="

if grep -q "user:" "${RUNTIME_ROOT}/docker-compose.yml" 2>/dev/null; then
    USER_CONFIG=$(grep "user:" "${RUNTIME_ROOT}/docker-compose.yml" | head -1)
    if echo "$USER_CONFIG" | grep -q "1000:1000\|AGENT_UID"; then
        pass "Agents run as non-root user (UID 1000)"
    else
        warn "Custom user configuration found"
    fi
else
    warn "No explicit user configuration"
fi

# =============================================================================
# Secret Management
# =============================================================================

echo ""
echo "=== Secret Management ==="

# Check for hardcoded secrets in config files
HARDCODED=$(grep -r "password.*=.*['\"][^'\"]*['\"]" "${RUNTIME_ROOT}" --include="*.yml" --include="*.yaml" --include="*.json" 2>/dev/null | grep -v node_modules | grep -v "\.env" | wc -l)

if [[ $HARDCODED -gt 0 ]]; then
    warn "Potential hardcoded secrets found: $HARDCODED occurrences"
    grep -r "password.*=.*['\"][^'\"]*['\"]" "${RUNTIME_ROOT}" --include="*.yml" --include="*.yaml" --include="*.json" 2>/dev/null | grep -v node_modules | grep -v "\.env" | head -3 | while read -r line; do
        log "  Found: $(echo "$line" | cut -d: -f2- | tr -s ' ')"
    done
else
    pass "No obvious hardcoded secrets found"
fi

# Check .env file exists and is protected
if [[ -f "${RUNTIME_ROOT}/.env" ]]; then
    ENV_PERMS=$(stat -c "%a" "${RUNTIME_ROOT}/.env" 2>/dev/null || stat -f "%Lp" "${RUNTIME_ROOT}/.env" 2>/dev/null)
    if [[ "$ENV_PERMS" == "600" ]] || [[ "$ENV_PERMS" == "400" ]]; then
        pass ".env file has secure permissions ($ENV_PERMS)"
    else
        warn ".env file has insecure permissions ($ENV_PERMS), should be 600"
    fi
else
    warn ".env file not found"
fi

# =============================================================================
# API Keys and Tokens
# =============================================================================

echo ""
echo "=== API Key Security ==="

# Check for API key placeholders
PLACEHOLDERS=$(grep -r "your-api-key\|CHANGE_ME\|placeholder\|sk-or-" "${RUNTIME_ROOT}/" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.sh" 2>/dev/null | grep -v node_modules | grep -v "\.env" | wc -l)

if [[ $PLACEHOLDERS -gt 0 ]]; then
    warn "API key placeholders found: $PLACEHOLDERS"
else
    pass "No API key placeholders found"
fi

# =============================================================================
# Container Security
# =============================================================================

echo ""
echo "=== Container Security ==="

shopt -s nullglob
for container in $(docker ps --format "{{.Names}}" 2>/dev/null); do
    # Skip if not our container
    if ! echo "$container" | grep -qE "^(openclaw|oc-|gateway)"; then
        continue
    fi
    
    # Check if running as root
    USER=$(docker exec "$container" id -u 2>/dev/null || echo "unknown")
    if [[ "$USER" == "0" ]]; then
        warn "Container $container is running as root"
    else
        pass "Container $container is running as non-root (UID: $USER)"
    fi
    
    # Check for privileged mode
    if docker inspect --format='{{.HostConfig.Privileged}}' "$container" 2>/dev/null | grep -q "true"; then
        fail "Container $container is in PRIVILEGED mode!"
    else
        pass "Container $container is not privileged"
    fi
done

# =============================================================================
# File Permissions
# =============================================================================

echo ""
echo "=== File Permissions ==="

shopt -s nullglob
for script in "${RUNTIME_ROOT}"/scripts/*.sh; do
    if [[ -f "$script" ]]; then
        PERMS=$(stat -c "%a" "$script" 2>/dev/null || stat -f "%Lp" "$script" 2>/dev/null)
        # Check if world-writable (o+w) or world-executable (o+x)
        if [[ "$PERMS" =~ [1367]$ ]] || [[ "$PERMS" =~ [1367] ]]; then
            warn "Script $(basename "$script") is world-writable (permissions: $PERMS)"
        else
            pass "Script $(basename "$script") has secure permissions"
        fi
    fi
done

# Check SSH keys (if any)
if [[ -d "${RUNTIME_ROOT}/.ssh" ]]; then
    warn ".ssh directory found in runtime"
    SSH_KEYS=$(find "${RUNTIME_ROOT}/.ssh" -type f 2>/dev/null | wc -l)
    log "  $SSH_KEYS SSH keys found"
fi

# =============================================================================
# Docker Socket Access
# =============================================================================

echo ""
echo "=== Docker Socket Access ==="

SOCKET_ACCESS=$(docker ps --format '{{.Names}}' 2>/dev/null | while read -r container; do
    if docker inspect --format='{{range .Mounts}}{{.Source}}{{end}}' "$container" 2>/dev/null | grep -q "/var/run/docker.sock"; then
        echo "$container"
    fi
done | wc -l)

if [[ $SOCKET_ACCESS -gt 0 ]]; then
    warn "$SOCKET_ACCESS containers have Docker socket access"
else
    pass "No containers have Docker socket access"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "=== Summary ==="
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Warnings:${NC}  $WARN"
echo ""

if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    echo -e "${GREEN}✓ All security checks passed!${NC}"
    exit 0
elif [[ $FAIL -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Security checks passed with warnings${NC}"
    echo ""
    echo "Review warnings above and address them for improved security."
    exit 0
else
    echo -e "${RED}✗ Security checks failed!${NC}"
    echo ""
    echo "Critical security issues found. Please fix the failures above."
    exit 1
fi