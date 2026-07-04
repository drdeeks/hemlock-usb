#!/bin/bash
# =============================================================================
# Setup Script - One-command bootstrap for new operators
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "=== OpenClaw Runtime Setup ==="
echo ""

# Create .env from template if it doesn't exist
if [[ ! -f ../.env ]]; then
    if [[ -f ../.env.template ]]; then
        cp ../.env.template ../.env
        echo "Created .env from template"
    else
        echo "Error: No .env or .env.template found"
        exit 1
    fi
else
    echo ".env already exists"
fi

# Set script permissions
echo ""
echo "Setting script permissions..."
chmod +x ../scripts/*.sh 2>/dev/null || true
chmod +x ./validate.sh 2>/dev/null || true
chmod +x ./test.sh 2>/dev/null || true
echo "Permissions set"

# Create directory structure
echo ""
echo "Creating directory structure..."
mkdir -p ../agents ../models ../backups ../logs
echo "Directories created"

# Run validation
echo ""
echo "Running validation..."
if ./validate.sh; then
    echo ""
    echo -e "${GREEN}=== Setup Complete ===${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Edit .env with your configuration"
    echo "  2. Copy agent code to agents/<agent-id>/app/"
    echo "  3. Run: make start AGENT_ID=<agent-id>"
    echo ""
    exit 0
else
    echo ""
    echo -e "${RED}=== Setup Failed ===${NC}"
    echo "Please fix the issues above"
    exit 1
fi