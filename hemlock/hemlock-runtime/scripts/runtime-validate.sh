#!/bin/bash
# =============================================================================
# Runtime Validation Script
# Validates the entire runtime structure and configuration
# =============================================================================

# Use +e to not exit on errors so we can collect all results
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

validate_yaml() {
    local file="$1"
    if docker compose -f "$file" config &> /dev/null; then
        pass "Valid YAML: $(basename "$file")"
        return 0
    else
        fail "Invalid YAML: $(basename "$file")"
        return 1
    fi
}

validate_directory() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        pass "Directory exists: $(basename "$dir")"
        return 0
    else
        fail "Directory missing: $dir"
        return 1
    fi
}

validate_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        pass "File exists: $(basename "$file")"
        return 0
    else
        fail "File missing: $file"
        return 1
    fi
}

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Runtime Validation Script                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Check directory structure
echo "=== Directory Structure ==="
validate_directory "${RUNTIME_ROOT}/hermes"
validate_directory "${RUNTIME_ROOT}/hermes/config"
validate_directory "${RUNTIME_ROOT}/canonical"
validate_directory "${RUNTIME_ROOT}/agents"
validate_directory "${RUNTIME_ROOT}/scripts"
validate_directory "${RUNTIME_ROOT}/backups"
validate_directory "${RUNTIME_ROOT}/logs"

# Check essential files
echo ""
echo "=== Essential Files ==="
validate_file "${RUNTIME_ROOT}/docker-compose.yml"
validate_file "${RUNTIME_ROOT}/.env"
validate_file "${RUNTIME_ROOT}/hermes/Dockerfile"
validate_file "${RUNTIME_ROOT}/hermes/entrypoint.sh"
validate_file "${RUNTIME_ROOT}/hermes/config/config.yaml"

# Validate YAML
echo ""
echo "=== Configuration Validation ==="
validate_yaml "${RUNTIME_ROOT}/docker-compose.yml"

# Check scripts
echo ""
echo "=== Scripts ==="
for script in hermes-run.sh hermes-stop.sh hermes-logs.sh runtime-doctor.sh agent-create.sh agent-import.sh agent-export.sh; do
    if [[ -x "${RUNTIME_ROOT}/scripts/${script}" ]]; then
        pass "Executable: $script"
    else
        fail "Not executable: $script"
    fi
done

# Check agents
echo ""
echo "=== Agents ==="
if [[ -d "${RUNTIME_ROOT}/agents/template-agent" ]]; then
    pass "Template agent exists"
else
    fail "Template agent missing"
fi

# Count existing agents
agent_count=$(find "${RUNTIME_ROOT}/agents" -maxdepth 1 -type d ! -name "template-agent" ! -name "agents" 2>/dev/null | wc -l)
if [[ $agent_count -gt 0 ]]; then
    pass "Agents found: $agent_count"
else
    warn "No agents found (only template)"
fi

# Docker validation
echo ""
echo "=== Docker Environment ==="
if command -v docker &> /dev/null; then
    pass "Docker is installed"
    if docker info &> /dev/null; then
        pass "Docker daemon is running"
    else
        fail "Docker daemon is not running"
    fi
else
    fail "Docker is not installed"
fi

# Summary
echo ""
echo "=== Summary ==="
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Warnings:${NC} $WARN"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✓ Validation passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Validation failed${NC}"
    exit 1
fi