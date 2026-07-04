#!/bin/bash
# =============================================================================
# Crew Blueprint System - Wrapper for Python implementation
# Incorporates autonomous-crew logic: Agent types, workflows, blueprints, checkpoints
#
# This is a thin wrapper around the Python implementation in scripts/py/crew_blueprint.py
#
# Usage:
#   ./scripts/crew-blueprint.sh <command> [options]
#
# Commands:
#   create <crew_name> [--agents <types>] [--project <name>]
#   list                        List all crew blueprints
#   show <crew_name>            Show blueprint details
#   set-phase <crew> <phase>   Set workflow phase
#   checkpoint <crew> <desc>    Create a checkpoint
#   list-cp <crew>             List checkpoints
#   validate <crew>             Validate success criteria
#   list-types                 List available agent types
#   list-phases                List workflow phases
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/py/crew_blueprint.py"

# Execute Python script
if [[ -f "$PY_SCRIPT" ]]; then
    exec python3 "$PY_SCRIPT" "$@"
else
    echo "Error: Python script not found at $PY_SCRIPT" >&2
    exit 1
fi
