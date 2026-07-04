#!/bin/bash
# =============================================================================
# Validation Script - Verify runtime structure and configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
    local description="$1"
    local command="$2"
    echo -n "  Checking: $description ... "
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASS=$((PASS+1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAIL=$((FAIL+1))
    fi
}

echo ""
echo "=== Runtime Validation ==="
echo ""

# Directory structure
echo "1. Directory Structure:"

if [[ -d "agents" ]]; then
    echo -e "  ${GREEN}✓${NC} agents/"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} agents/"
    FAIL=$((FAIL+1))
fi

if [[ -d "models" ]]; then
    echo -e "  ${GREEN}✓${NC} models/"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} models/"
    FAIL=$((FAIL+1))
fi

if [[ -d "backups" ]]; then
    echo -e "  ${GREEN}✓${NC} backups/"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} backups/"
    FAIL=$((FAIL+1))
fi

if [[ -d "logs" ]]; then
    echo -e "  ${GREEN}✓${NC} logs/"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} logs/"
    FAIL=$((FAIL+1))
fi

if [[ -d "scripts" ]]; then
    echo -e "  ${GREEN}✓${NC} scripts/"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} scripts/"
    FAIL=$((FAIL+1))
fi

# Scripts are executable
echo ""
echo "2. Script Permissions:"
for script in scripts/*.sh; do
    if [[ -f "$script" ]]; then
        if [[ -x "$script" ]]; then
            echo -e "  ${GREEN}✓${NC} $(basename "$script")"
            PASS=$((PASS+1))
        else
            echo -e "  ${RED}✗${NC} $(basename "$script") not executable"
            FAIL=$((FAIL+1))
        fi
    fi
done

# Required files
echo ""
echo "3. Required Files:"

if [[ -f ".env" ]]; then
    echo -e "  ${GREEN}✓${NC} .env"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} .env"
    FAIL=$((FAIL+1))
fi

if [[ -f "docker-compose.yml" ]]; then
    echo -e "  ${GREEN}✓${NC} docker-compose.yml"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} docker-compose.yml"
    FAIL=$((FAIL+1))
fi

if [[ -f "Makefile" ]]; then
    echo -e "  ${GREEN}✓${NC} Makefile"
    PASS=$((PASS+1))
else
    echo -e "  ${RED}✗${NC} Makefile"
    FAIL=$((FAIL+1))
fi

# .env validation
echo ""
echo "4. Environment Variables:"
if [[ -f ".env" ]]; then
    source .env 2>/dev/null || true
    if [[ -n "${RUNTIME_ROOT:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} RUNTIME_ROOT defined"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} RUNTIME_ROOT not defined"
        FAIL=$((FAIL+1))
    fi

    if [[ -n "${AGENTS_ROOT:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} AGENTS_ROOT defined"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} AGENTS_ROOT not defined"
        FAIL=$((FAIL+1))
    fi

    if [[ -n "${MODEL_BACKEND:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} MODEL_BACKEND defined"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} MODEL_BACKEND not defined"
        FAIL=$((FAIL+1))
    fi

    if [[ -n "${DEFAULT_MODEL:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} DEFAULT_MODEL defined"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} DEFAULT_MODEL not defined"
        FAIL=$((FAIL+1))
    fi
fi

# Docker compose validation
echo ""
echo "5. Docker Compose:"
if command -v docker >/dev/null 2>&1; then
    # Create temporary .env with required variables for syntax validation
    # These are normally injected by agent-run.sh at runtime
    TEMP_ENV=$(mktemp)
    cat > "$TEMP_ENV" << 'TEMPLATE'
RUNTIME_ROOT=./runtime
AGENTS_ROOT=${RUNTIME_ROOT}/agents
MODELS_ROOT=${RUNTIME_ROOT}/models
BACKUP_ROOT=${RUNTIME_ROOT}/backups
LOGS_ROOT=${RUNTIME_ROOT}/logs
AGENT_IMAGE=node:20-bullseye
AGENT_CPU_LIMIT=1.0
AGENT_MEM_LIMIT=512m
AGENT_TMPFS=/tmp
AGENT_UID=1000
AGENT_GID=1000
AGENT_NETWORK=agents_net
AGENT_APP_DIR_NAME=app
AGENT_DATA_DIR_NAME=data
AGENT_CONFIG_DIR_NAME=config
AGENT_DB_NAME=state.db
MODEL_BACKEND=ollama
OLLAMA_HOST=http://host.docker.internal:11434
LLAMACPP_HOST=http://host.docker.internal:8080
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_API_KEY=
DEFAULT_MODEL=mistral/devstral-2512
MODEL_TEMPERATURE=0.7
MODEL_MAX_TOKENS=2048
AGENT_ID=validation-test
AGENT_APP_PATH=/tmp/validation/app
AGENT_DATA_PATH=/tmp/validation/data
AGENT_CONFIG_PATH=/tmp/validation/config
TEMPLATE

    # Run validation with temp env
    if docker compose --env-file "$TEMP_ENV" -f docker-compose.yml config > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} docker-compose.yml is valid YAML"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC} docker-compose.yml has syntax errors"
        FAIL=$((FAIL+1))
    fi
    rm -f "$TEMP_ENV"
else
    echo -e "  ${YELLOW}⚠${NC} Docker not available for validation"
fi

# Summary
echo ""
echo "===================="
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✓ Runtime validation passed${NC}"
    exit 0
else
    echo -e "${RED}✗ Runtime validation failed${NC}"
    exit 1
fi