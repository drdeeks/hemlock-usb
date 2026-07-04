# =============================================================================
# OpenClaw Enterprise Framework - Makefile
# 
# Docker management commands for building, testing, and deploying
# 
# Usage:
#   make help                   # Show available commands
#   make build                  # Build all Docker images
#   make up                     # Start all services
#   make down                  # Stop all services
#   make clean                 # Remove containers and volumes
#   make export                # Export all agents as Docker images
#   make push                  # Build and push all images to registry
# =============================================================================

.PHONY: help build up down clean test export import push pull logs shell \
        build-framework build-agents build-agent build-crew export-agent \
        export-crews export-crew import-crew import-agent push-crew pull \
        logs-service shell-service ps images clean-all restart up-logs \
        health validate status env

# =============================================================================
# Configuration
# =============================================================================
DOCKER_COMPOSE ?= docker compose
DOCKER ?= docker

# =============================================================================
# Help
# =============================================================================
help:
	@echo "OpenClaw Enterprise Framework - Docker Management"
	@echo ""
	@echo "Available commands:"
	@echo ""
	@echo "BUILD:"
	@echo "  build                    # Build all Docker images"
	@echo "  build-framework          # Build only framework image"
	@echo "  build-agents             # Build all agent images"
	@echo "  build-agent AGENT_ID=<id> # Build specific agent image"
	@echo "  build-crew CREW_ID=<id>  # Build specific crew image"
	@echo ""
	@echo "ORCHESTRATION:"
	@echo "  up                       # Start all services (daemon mode)"
	@echo "  up-logs                  # Start all services with logs"
	@echo "  down                     # Stop all services"
	@echo "  restart                  # Restart all services"
	@echo ""
	@echo "CLEANUP:"
	@echo "  clean                    # Remove containers, networks, volumes"
	@echo "  clean-all                # Full system prune (Docker)"
	@echo ""
	@echo "EXPORT/IMPORT:"
	@echo "  export                   # Export all agents as Docker images"
	@echo "  export-agent AGENT_ID=<id> # Export specific agent"
	@echo "  export-crews             # Export all crews as Docker images"
	@echo "  export-crew CREW_ID=<id> # Export specific crew"
	@echo "  import IMAGE=<image>     # Import agent from Docker image"
	@echo "  import-crew IMAGE=<image> # Import crew from Docker image"
	@echo ""
	@echo "REGISTRY:"
	@echo "  push                     # Build and push all images to registry"
	@echo "  push-crew IMAGE=<image>  # Push crew image to registry"
	@echo "  pull                     # Pull all images from registry"
	@echo ""
	@echo "DEBUGGING:"
	@echo "  logs                     # Show all service logs"
	@echo "  logs-service SERVICE=<svc> # Show logs for specific service"
	@echo "  shell-service SERVICE=<svc> # Open shell in running service"
	@echo "  ps                       # List running containers"
	@echo "  images                   # List Docker images"
	@echo "  status                   # Show framework status"
	@echo "  health                   # Check service health"
	@echo ""
	@echo "VALIDATION:"
	@echo "  test                     # Run health checks"
	@echo "  validate                 # Validate docker-compose configuration"
	@echo "  env                      # Show environment template"
	@echo ""

# =============================================================================
# Build Commands
# =============================================================================

build:
	@echo "Building all Docker images..."
	@docker compose -f docker-compose.yml build

build-framework:
	@echo "Building framework image..."
	@docker build --target framework -t openclaw/enterprise-framework:latest -t openclaw/enterprise-framework:1.0.0 -f Dockerfile .

build-agents:
	@echo "Building all agent images..."
	@./scripts/docker/build-images.sh agents

build-agent:
	@if [ -z "$(AGENT_ID)" ]; then \
		echo "Error: AGENT_ID is required"; \
		echo "Usage: make build-agent AGENT_ID=my-agent"; \
		exit 1; \
	fi
	@echo "Building agent image: $(AGENT_ID)..."
	@$(DOCKER) build -t "openclaw/agent-$(AGENT_ID):latest" \
		--build-arg AGENT_ID=$(AGENT_ID) \
		-f Dockerfile.agent .


build-crew:
	@if [ -z "$(CREW_ID)" ]; then \
		echo "Error: CREW_ID is required"; \
		echo "Usage: make build-crew CREW_ID=my-crew"; \
		exit 1; \
	fi
	@echo "Building crew image: $(CREW_ID)..."
	@$(DOCKER) build -t "openclaw/crew-$(CREW_ID):1.0.0" -t "openclaw/crew-$(CREW_ID):latest" \
		-f Dockerfile.crew --build-arg CREW_ID=$(CREW_ID) .


# =============================================================================
# Docker Compose Commands
# =============================================================================

up:
	@echo "Starting all services..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml up -d

up-logs:
	@echo "Starting all services with logs..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml up

down:
	@echo "Stopping all services..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml down

restart:
	@echo "Restarting all services..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml restart

# =============================================================================
# Cleanup Commands
# =============================================================================

clean:
	@echo "Cleaning up containers, networks, and volumes..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml down -v --rmi local

clean-all:
	@echo "Removing ALL stopped containers, unused networks, dangling images..."
	@docker system prune -f

# =============================================================================
# Export/Import Commands
# =============================================================================

export:
	@echo "Exporting all agents as Docker images..."
	@./scripts/docker/export-agent.sh -a

export-agent:
	@echo "Exporting agent: $@"
	@./scripts/docker/export-agent.sh $@

import:
	@echo "Importing agent from image: $@"
	@./scripts/docker/import-agent.sh $@

export-crews:
	@echo "Exporting all crews as Docker images..."
	@./scripts/docker/export-crew.sh -a

export-crew:
	@echo "Exporting crew: $@"
	@./scripts/docker/export-crew.sh $@

import-crew:
	@echo "Importing crew from image: $@"
	@./scripts/docker/import-crew.sh $@

# =============================================================================
# Registry Commands
# =============================================================================

push:
	@echo "Building and pushing all images to registry..."
	@./scripts/docker/build-images.sh push

push-crew:
	@echo "Pushing crew image: $@"
	@docker push $@

pull:
	@echo "Pulling all images from registry..."
	@docker pull openclaw/enterprise-framework:latest
	@docker pull openclaw/agent:latest
	@docker pull openclaw/gateway:latest

# =============================================================================
# Logging and Debugging
# =============================================================================

logs:
	@echo "Showing logs for all services..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml logs -f

logs-service:
	@echo "Showing logs for service: $@"
	@$(DOCKER_COMPOSE) -f docker-compose.yml logs -f $@

shell-service:
	@echo "Opening shell in service: $@"
	@$(DOCKER_COMPOSE) -f docker-compose.yml exec $@ sh

ps:
	@echo "Running containers:"
	@$(DOCKER_COMPOSE) -f docker-compose.yml ps

images:
	@echo "Docker images:"
	@docker images | grep openclaw

# =============================================================================
# Testing Commands
# =============================================================================

test:
	@echo "Running health checks..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml ps -q | xargs -I {} docker inspect -f '{{.Name}}: {{.State.Health.Status}}' {} || true

# =============================================================================
# Additional Useful Commands
# =============================================================================

health:
	@echo "Checking service health..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml ps

status:
	@echo "Framework status:"
	@$(DOCKER_COMPOSE) -f docker-compose.yml ps

env:
	@echo "Environment variables for Hemlock:"
	@grep -v '^#' .env.template 2>/dev/null || echo "Note: .env.template not found"

validate:
	@echo "Validating docker-compose.yml..."
	@docker-compose config -f docker-compose.yml > /dev/null && echo "✅ Configuration valid" || echo "❌ Configuration invalid"

.DEFAULT_GOAL := help
