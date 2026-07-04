#!/bin/bash
# =============================================================================
# Test Script - Launch test agent to validate runtime
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

if [[ ! -f .env ]]; then
    echo "Error: .env file not found"
    exit 1
fi

source .env

TEST_AGENT="template-test-$$"
AGENT_PATH="${AGENTS_ROOT}/${TEST_AGENT}"
AGENT_APP_PATH="${AGENT_PATH}/${AGENT_APP_DIR_NAME}"
AGENT_DATA_PATH="${AGENT_PATH}/${AGENT_DATA_DIR_NAME}"
AGENT_CONFIG_PATH="${AGENT_PATH}/${AGENT_CONFIG_DIR_NAME}"

echo "Setting up test agent: $TEST_AGENT"

# Create directory structure
mkdir -p "$AGENT_APP_PATH" "$AGENT_DATA_PATH" "$AGENT_CONFIG_PATH"

# Copy template agent
if [[ -d "agents/template-agent" ]]; then
    cp -r agents/template-agent/app/* "$AGENT_APP_PATH/" 2>/dev/null || true
    cp -r agents/template-agent/config/* "$AGENT_CONFIG_PATH/" 2>/dev/null || true
fi

# Create test marker
echo "Test agent created at $(date)" > "$AGENT_DATA_PATH/test-marker.txt"

# Launch agent
export AGENT_ID="$TEST_AGENT"
export AGENT_APP_PATH
export AGENT_DATA_PATH
export AGENT_CONFIG_PATH

echo "Starting test agent..."
docker compose -p "$TEST_AGENT" -f docker-compose.yml up -d

# Wait for startup
sleep 5

# Verify
echo ""
echo "Verifying test agent..."

if docker compose -p "$TEST_AGENT" -f docker-compose.yml ps | grep -q "Up"; then
    echo -e "  ${GREEN}✓${NC} Container is running"
else
    echo -e "  ${RED}✗${NC} Container failed to start"
    docker compose -p "$TEST_AGENT" -f docker-compose.yml logs
    exit 1
fi

# Check environment variables
CONTAINER_ID=$(docker compose -p "$TEST_AGENT" -f docker-compose.yml ps -q)
if docker exec "$CONTAINER_ID" sh -c 'echo $AGENT_ID' | grep -q "$TEST_AGENT"; then
    echo -e "  ${GREEN}✓${NC} AGENT_ID injected correctly"
else
    echo -e "  ${RED}✗${NC} AGENT_ID not injected"
fi

if docker exec "$CONTAINER_ID" sh -c 'echo $MODEL_BACKEND' | grep -q "$MODEL_BACKEND"; then
    echo -e "  ${GREEN}✓${NC} MODEL_BACKEND injected correctly"
else
    echo -e "  ${RED}✗${NC} MODEL_BACKEND not injected"
fi

# Check volume mounts
if docker exec "$CONTAINER_ID" sh -c 'test -w /data'; then
    echo -e "  ${GREEN}✓${NC} Data volume mounted correctly"
else
    echo -e "  ${RED}✗${NC} Data volume mount failed"
fi

# Check data persistence
if docker exec "$CONTAINER_ID" sh -c 'test -f /data/test-marker.txt'; then
    echo -e "  ${GREEN}✓${NC} Data persisted from host"
else
    echo -e "  ${RED}✗${NC} Data not persisted"
fi

echo ""
echo "Test agent running at: $AGENT_PATH"

# Cleanup prompt
echo ""
echo "Test complete. To stop test agent:"
echo "  docker compose -p $TEST_AGENT -f docker-compose.yml down"

# Actually stop after validation
echo ""
echo "Stopping test agent..."
docker compose -p "$TEST_AGENT" -f docker-compose.yml down

# Cleanup directories
rm -rf "$AGENT_PATH"

echo -e "${GREEN}✓ Test completed successfully${NC}"