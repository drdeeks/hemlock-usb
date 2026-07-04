#!/bin/bash
# Agent Control Script (start/stop/restart)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <command> <agent_id> [--force]"
    echo "Commands: start, stop, restart, status"
    exit 1
fi

COMMAND=$1
AGENT_ID=$2
FORCE=${3:-}

# Validate agent
echo "Checking agent $AGENT_ID..."
if ! agent_exists "$AGENT_ID"; then
    echo "Error: Agent $AGENT_ID does not exist"
    exit 1
fi

# Get container name
CONTAINER_NAME=$(get_agent_container "$AGENT_ID")

# Execute command
case $COMMAND in
    start)
        echo "Starting agent $AGENT_ID..."
        
        # Check if already running
        if is_service_running "$CONTAINER_NAME"; then
            echo "Agent $AGENT_ID is already running"
            exit 0
        fi
        
        # Start the agent
        docker-compose -f "$DOCKER_COMPOSE_FILE" up -d "$CONTAINER_NAME"
        
        # Verify it started
        if is_service_running "$CONTAINER_NAME"; then
            echo "Agent $AGENT_ID started successfully"
            log "INFO" "Agent $AGENT_ID started"
            agent_log "$AGENT_ID" "INFO" "Agent started"
        else
            echo "Error: Failed to start agent $AGENT_ID"
            log "ERROR" "Failed to start agent $AGENT_ID"
            exit 1
        fi
        ;;
    
    stop)
        echo "Stopping agent $AGENT_ID..."
        
        # Check if running
        if ! is_service_running "$CONTAINER_NAME"; then
            echo "Agent $AGENT_ID is not running"
            exit 0
        fi
        
        # Stop the agent
        docker-compose -f "$DOCKER_COMPOSE_FILE" stop "$CONTAINER_NAME"
        
        # Verify it stopped
        if ! is_service_running "$CONTAINER_NAME"; then
            echo "Agent $AGENT_ID stopped successfully"
            log "INFO" "Agent $AGENT_ID stopped"
            agent_log "$AGENT_ID" "INFO" "Agent stopped"
        else
            echo "Error: Failed to stop agent $AGENT_ID"
            log "ERROR" "Failed to stop agent $AGENT_ID"
            if [ "$FORCE" == "--force" ]; then
                echo "Forcing stop..."
                docker rm -f "$CONTAINER_NAME"
                echo "Agent $AGENT_ID force stopped"
                log "WARNING" "Agent $AGENT_ID force stopped"
            else
                exit 1
            fi
        fi
        ;;
    
    restart)
        echo "Restarting agent $AGENT_ID..."
        "$0" stop "$AGENT_ID" $FORCE
        sleep 2
        "$0" start "$AGENT_ID"
        echo "Agent $AGENT_ID restarted successfully"
        ;;
    
    status)
        if is_service_running "$CONTAINER_NAME"; then
            echo "Agent $AGENT_ID is RUNNING"
            docker ps --filter "name=$CONTAINER_NAME"
        else
            echo "Agent $AGENT_ID is STOPPED"
        fi
        ;;
    
    *)
        echo "Error: Unknown command $COMMAND"
        echo "Available commands: start, stop, restart, status"
        exit 1 ;;
esac