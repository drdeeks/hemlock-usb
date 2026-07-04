#!/usr/bin/env python3
"""
create_crew.py - Create crew folders with agent specifics, blueprints, and configurations

This script generates a complete crew folder structure based on the project-manager
templates and the create_agents.py/finalize_agents.py patterns.

Each crew folder contains:
  - Crew configuration (crew.json)
  - Agent assignments and roles
  - Workflow configurations
  - Blueprints for agent setup
  - Communication standards
  - Quality gates and compliance rules

Usage:
    python create_crew.py <crew_name> [options]

Options:
    --template <name>    Use a specific template (default: project-manager)
    --agents <list>     Comma-separated list of agent IDs to assign
    --workflow <file>   Custom workflow file
    --overwrite         Overwrite existing crew folder
    --list-templates    List available templates
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional

# Root directory
ROOT_DIR = Path(__file__).resolve().parent.parent
CREWS_DIR = ROOT_DIR / "crews"
AGENTS_DIR = ROOT_DIR / "agents"
PLUGINS_DIR = ROOT_DIR / "plugins"
CREW_TEMPLATES_DIR = PLUGINS_DIR / "crews" / "project-manager" / "templates"
CREW_RULES_DIR = PLUGINS_DIR / "crews" / "rules"

# =============================================================================
# TEMPLATES
# =============================================================================

# Default crew configuration template
CREW_CONFIG_TEMPLATE = {
    "crew_id": "",
    "name": "",
    "description": "",
    "version": "1.0.0",
    "status": "active",
    "created_at": "",
    "updated_at": "",
    "agents": [],
    "workflows": {
        "primary": "",
        "fallback": "",
        "error_handling": ""
    },
    "communication": {
        "protocol": "structured_json",
        "validation": "schema_based",
        "error_propagation": "cascading_with_context"
    },
    "quality_gates": {
        "validation_required": True,
        "quality_metrics": True,
        "multi_point_check": True
    },
    "compliance": {
        "security_level": "enterprise_grade",
        "audit_logging": "comprehensive",
        "performance_tracking": "real_time"
    },
    "metadata": {
        "template": "project-manager",
        "category": "generic"
    }
}

# Default agent blueprint template
AGENT_BLUEPRINT_TEMPLATE = {
    "agent_id": "",
    "agent_name": "",
    "role": "",
    "specialization": "",
    "tier": "secondary",
    "cooperative_level": "high",
    "model": "",
    "backup_model": "",
    "capabilities": [],
    "integration_points": [],
    "workflow_file": "",
    "rules_file": "",
    "environment_file": "",
    "interchangeable": True,
    "enterprise_compliance": {
        "accuracy_standard": "99.9%",
        "communication_protocol": "structured_json",
        "error_handling": "comprehensive_with_fallback",
        "output_validation": "rigorous_multi_point_check",
        "security_level": "enterprise_grade",
        "audit_logging": "comprehensive",
        "performance_monitoring": "real_time"
    },
    "metadata": {
        "assigned_at": "",
        "status": "active"
    }
}

# Default workflow template
WORKFLOW_TEMPLATE = {
    "version": "1.0",
    "name": "",
    "description": "",
    "phases": [
        {"id": "ingest", "description": "Ingest inputs, validate schema, normalize."},
        {"id": "plan", "description": "Construct step plan with explicit I/O contracts."},
        {"id": "execute", "description": "Perform steps, capture artifacts, stream status."},
        {"id": "validate", "description": "Validate outputs, run quality gates and policies."},
        {"id": "handoff", "description": "Emit final payloads and crew notifications."}
    ],
    "artifacts": [
        "plan.md",
        "runlog.ndjson",
        "metrics.json"
    ],
    "error_policy": {
        "retries": 2,
        "backoff": "exponential",
        "on_fail": "emit_incident"
    },
    "quality_gates": {
        "validation_required": True,
        "schema_compliance": True,
        "context_preservation": True
    }
}

# Crew communication standards
COMMUNICATION_STANDARDS = {
    "version": "1.0",
    "protocols": {
        "message_format": "structured_json",
        "required_fields": [
            "agent_name",
            "agent_id",
            "category",
            "message_type",
            "timestamp",
            "payload"
        ],
        "status_values": ["ok", "warn", "error"],
        "response_timeout": "30s"
    },
    "naming_conventions": {
        "agents": "category-locked, purpose-descriptive; kebab-case slugs",
        "files": "lowercase with dashes; no spaces",
        "directories": "lowercase with dashes; no spaces"
    },
    "error_handling": {
        "on_validation_failure": "emit incident to crew/incident_response.json",
        "retry_policy": {
            "retries": 2,
            "backoff": "exponential"
        },
        "escalation": {
            "critical_failures": "immediate",
            "warnings": "after_2_retries"
        }
    },
    "security": {
        "input_sanitization": "required",
        "output_encryption": "for_sensitive_data",
        "compliance_standards": ["SOC2", "ISO27001", "GDPR"]
    }
}

# =============================================================================
# CREW CATEGORY CONFIGURATIONS
# =============================================================================

CREW_CATEGORIES = {
    "project-manager": {
        "description": "Manages project lifecycle, resource allocation, and delivery pipelines",
        "default_workflow": "project-management",
        "recommended_agents": [
            "enterprise-resource-allocator",
            "agile-process-strategist",
            "delivery-pipeline-accelerator"
        ],
        "rules_files": [
            "enterprise_workflow.json",
            "project_structure_analysis.json",
            "follow_through_protocol.json"
        ]
    },
    "development": {
        "description": "Software development and code optimization",
        "default_workflow": "development",
        "recommended_agents": [
            "microservices-systems-architect",
            "algorithm-optimization-specialist",
            "code-profiling-specialist",
            "memory-management-engineer"
        ],
        "rules_files": [
            "debugging_methodology.json",
            "quality_gates.json",
            "optimization_standards.json"
        ]
    },
    "security": {
        "description": "Security auditing, vulnerability testing, and compliance",
        "default_workflow": "security-audit",
        "recommended_agents": [
            "zero-trust-security-architect",
            "encryption-and-pki-specialist",
            "enterprise-vulnerability-tester",
            "soc2-compliance-auditor",
            "gdpr-privacy-engineer"
        ],
        "rules_files": [
            "security_measures.json",
            "error_handling_standards.json",
            "master_implementation_checklist.json"
        ]
    },
    "data": {
        "description": "Data processing, analysis, and optimization",
        "default_workflow": "data-processing",
        "recommended_agents": [
            "postgresql-optimization-specialist",
            "algorithm-optimization-specialist",
            "enterprise-message-queue-engineer"
        ],
        "rules_files": [
            "targeted_intervention.json",
            "quality_gates.json"
        ]
    },
    "content": {
        "description": "Content creation, media production, and brand management",
        "default_workflow": "content-production",
        "recommended_agents": [
            "ai-image-generation-specialist",
            "ai-video-content-producer",
            "brand-consistency-director"
        ],
        "rules_files": [
            "comprehensive_project_structure_agent_rules.json"
        ]
    },
    "infrastructure": {
        "description": "Infrastructure management, deployment, and scaling",
        "default_workflow": "infrastructure",
        "recommended_agents": [
            "microservices-systems-architect",
            "api-gateway-and-load-engineer",
            "service-mesh-orchestrator",
            "enterprise-message-queue-engineer"
        ],
        "rules_files": [
            "quality_gates.json",
            "error_handling_standards.json"
        ]
    }
}


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def ensure_directory(path: Path) -> Path:
    """Ensure directory exists, create if not."""
    path.mkdir(parents=True, exist_ok=True)
    return path


def copy_template_template(src: Path, dest: Path) -> None:
    """Copy template file with variable substitution."""
    if src.exists():
        content = src.read_text()
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)


def load_agents_manifest() -> Dict[str, Any]:
    """Load agent configurations from the agents directory."""
    agents = {}
    
    if AGENTS_DIR.exists():
        # Load from active agents
        active_dir = AGENTS_DIR / "active"
        if active_dir.exists():
            for json_file in active_dir.glob("*.json"):
                try:
                    with open(json_file, 'r') as f:
                        agent = json.load(f)
                    agents[agent.get('agent_name', '')] = agent
                except Exception as e:
                    print(f"Warning: Could not load {json_file}: {e}")
        
        # Load from archive
        archive_dir = AGENTS_DIR / "archive"
        if archive_dir.exists():
            for json_file in archive_dir.glob("*.json"):
                try:
                    with open(json_file, 'r') as f:
                        agent = json.load(f)
                    agents[agent.get('agent_name', '')] = agent
                except Exception as e:
                    print(f"Warning: Could not load {json_file}: {e}")
    
    return agents


def get_agent_env_file(agent_id: str) -> Optional[str]:
    """Get environment file path for an agent."""
    env_dir = AGENTS_DIR / "envs"
    if env_dir.exists():
        env_file = env_dir / f"{agent_id}.env"
        if env_file.exists():
            return str(env_file)
    
    # Try in agent directory
    agent_dir = AGENTS_DIR / agent_id
    if agent_dir.exists():
        for env_pattern in ["agent.env", ".env", "agent-local.env"]:
            env_file = agent_dir / env_pattern
            if env_file.exists():
                return str(env_file)
    
    return None


def get_agent_rules_file(agent_id: str) -> Optional[str]:
    """Get rules file path for an agent."""
    rules_dir = AGENTS_DIR / "rules"
    if rules_dir.exists():
        rules_file = rules_dir / f"{agent_id}-rules.md"
        if rules_file.exists():
            return str(rules_file)
    
    return None


# =============================================================================
# CREW GENERATION
# =============================================================================

def generate_crew_folder(crew_name: str, template: str = "project-manager", 
                         agents: Optional[List[str]] = None,
                         workflow: Optional[str] = None,
                         overwrite: bool = False) -> Dict[str, Any]:
    """
    Generate a complete crew folder with all necessary files.
    
    Args:
        crew_name: Name of the crew to create
        template: Template to use (default: project-manager)
        agents: List of agent IDs to assign to the crew
        workflow: Custom workflow file path
        overwrite: Whether to overwrite existing folder
    
    Returns:
        Dictionary with information about the created crew
    """
    from datetime import datetime
    import uuid
    
    crew_dir = CREWS_DIR / crew_name
    
    # Check if crew already exists
    if crew_dir.exists():
        if not overwrite:
            raise FileExistsError(
                f"Crew '{crew_name}' already exists at {crew_dir}. "
                f"Use --overwrite to replace."
            )
        else:
            print(f"Overwriting existing crew: {crew_name}")
            shutil.rmtree(str(crew_dir))
    
    # Create directory structure
    print(f"Creating crew folder: {crew_name}")
    
    # Define subdirs
    subdirs = [
        crew_dir / "agents",
        crew_dir / "config",
        crew_dir / "workflows",
        crew_dir / "rules",
        crew_dir / "memory",
        crew_dir / "projects",
        crew_dir / "blueprints",
    ]
    
    for d in subdirs:
        ensure_directory(d)
    
    # Create crew ID
    crew_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"crew.{crew_name}"))
    created_at = datetime.utcnow().isoformat() + "Z"
    
    # Get category config
    category_config = CREW_CATEGORIES.get(template, CREW_CATEGORIES["project-manager"])
    
    # =========================================
    # 1. Create crew configuration (crew.json)
    # =========================================
    crew_config = CREW_CONFIG_TEMPLATE.copy()
    crew_config.update({
        "crew_id": crew_id,
        "name": crew_name,
        "description": category_config.get("description", ""),
        "created_at": created_at,
        "updated_at": created_at,
        "metadata": {
            "template": template,
            "category": template,
            "created_by": "create_crew.py"
        },
        "workflows": {
            "primary": f"./workflows/{template}_workflow.json",
            "fallback": "./workflows/error_handling.json",
            "error_handling": "./workflows/incident_response.json"
        }
    })
    
    crew_json_path = crew_dir / "crew.json"
    with open(crew_json_path, 'w') as f:
        json.dump(crew_config, f, indent=2)
    print(f"  Created: crew.json")
    
    # =========================================
    # 2. Create agent blueprints
    # =========================================
    if agents:
        agents_manifest = load_agents_manifest()
        crew_config["agents"] = []
        
        for agent_id in agents:
            blueprint = AGENT_BLUEPRINT_TEMPLATE.copy()
            
            # Try to get agent info from manifest
            agent_info = None
            for agent_name, agent_data in agents_manifest.items():
                if agent_data.get('agent_name') == agent_id or agent_data.get('slug') == agent_id:
                    agent_info = agent_data
                    break
            
            if agent_info:
                blueprint.update({
                    "agent_id": agent_info.get('agent_id', agent_id),
                    "agent_name": agent_id,
                    "specialization": agent_info.get('specialization', ''),
                    "model": agent_info.get('default_model', agent_info.get('model', '')),
                    "backup_model": agent_info.get('backup_model', agent_info.get('backup_ggfu', '')),
                    "capabilities": agent_info.get('specialized_capabilities', []),
                    "integration_points": agent_info.get('integration_points', []),
                    "workflow_file": agent_info.get('workflow_file', ''),
                    "rules_file": agent_info.get('rules_file', ''),
                    "environment_file": agent_info.get('environment_file', '')
                })
            else:
                blueprint.update({
                    "agent_id": agent_id,
                    "agent_name": agent_id,
                    "role": "member",
                    "specialization": "General purpose",
                    "workflow_file": f"../agents/workflow/agent/{template}_workflow.json",
                    "rules_file": f"../agents/rules/{agent_id}-rules.md",
                    "environment_file": f"../agents/envs/{agent_id}.env"
                })
            
            # Save blueprint
            blueprint_path = crew_dir / "blueprints" / f"{agent_id}.json"
            with open(blueprint_path, 'w') as f:
                json.dump(blueprint, f, indent=2)
            print(f"  Created: blueprints/{agent_id}.json")
            
            # Add to crew config
            crew_config["agents"].append({
                "agent_id": agent_id,
                "blueprint_file": f"./blueprints/{agent_id}.json",
                "role": blueprint.get("role", "member")
            })
        
        # Update crew config with agents
        with open(crew_json_path, 'w') as f:
            json.dump(crew_config, f, indent=2)
    
    # =========================================
    # 3. Create workflows
    # =========================================
    
    # Main crew workflow
    crew_workflow = WORKFLOW_TEMPLATE.copy()
    crew_workflow.update({
        "name": f"{crew_name}_workflow",
        "description": f"Primary workflow for {crew_name} crew"
    })
    
    workflow_path = crew_dir / "workflows" / f"{template}_workflow.json"
    with open(workflow_path, 'w') as f:
        json.dump(crew_workflow, f, indent=2)
    print(f"  Created: workflows/{template}_workflow.json")
    
    # Error handling workflow
    error_workflow = WORKFLOW_TEMPLATE.copy()
    error_workflow.update({
        "name": "error_handling",
        "description": "Error handling workflow for crew",
        "phases": [
            {"id": "detect", "description": "Detect and classify errors"},
            {"id": "triage", "description": "Triage error severity and impact"},
            {"id": "mitigate", "description": "Implement mitigation strategies"},
            {"id": "escalate", "description": "Escalate to appropriate level"},
            {"id": "resolve", "description": "Resolve and verify fix"},
            {"id": "postmortem", "description": "Document lessons learned"}
        ]
    })
    
    error_workflow_path = crew_dir / "workflows" / "error_handling.json"
    with open(error_workflow_path, 'w') as f:
        json.dump(error_workflow, f, indent=2)
    print(f"  Created: workflows/error_handling.json")
    
    # Incident response workflow
    incident_workflow = WORKFLOW_TEMPLATE.copy()
    incident_workflow.update({
        "name": "incident_response",
        "description": "Incident response workflow",
        "phases": [
            {"id": "acknowledge", "description": "Acknowledge incident"},
            {"id": "assess", "description": "Assess impact and scope"},
            {"id": "contain", "description": "Contain incident spread"},
            {"id": "remediate", "description": "Remediate root cause"},
            {"id": "recover", "description": "Restore normal operations"},
            {"id": "review", "description": "Post-incident review"}
        ]
    })
    
    incident_workflow_path = crew_dir / "workflows" / "incident_response.json"
    with open(incident_workflow_path, 'w') as f:
        json.dump(incident_workflow, f, indent=2)
    print(f"  Created: workflows/incident_response.json")
    
    # =========================================
    # 4. Copy rules from templates
    # =========================================
    rules_files = category_config.get("rules_files", [])
    
    # Also include global rules
    all_rules = rules_files + [
        "quality_gates.json",
        "error_handling_standards.json",
        "master_implementation_checklist.json"
    ]
    
    for rule_file in all_rules:
        # Try to copy from plugin rules directory
        source_rule = CREW_RULES_DIR / rule_file
        if source_rule.exists():
            dest_rule = crew_dir / "rules" / rule_file
            shutil.copy2(str(source_rule), str(dest_rule))
            print(f"  Created: rules/{rule_file} (from plugins)")
        else:
            # Create a reference to the plugin location
            dest_rule = crew_dir / "rules" / rule_file
            dest_rule.parent.mkdir(parents=True, exist_ok=True)
            dest_rule.write_text(json.dumps({
                "rule_type": rule_file.replace('.json', ''),
                "source": f"../../plugins/crews/rules/{rule_file}",
                "note": "This file should be copied from plugins/crews/rules/"
            }, indent=2))
            print(f"  Created: rules/{rule_file} (reference)")
    
    # =========================================
    # 5. Create communication standards
    # =========================================
    comm_standards_path = crew_dir / "config" / "communication-standards.json"
    with open(comm_standards_path, 'w') as f:
        json.dump(COMMUNICATION_STANDARDS, f, indent=2)
    print(f"  Created: config/communication-standards.json")
    
    # =========================================
    # 6. Create SOUL.md for the crew
    # =========================================
    crew_soul = f"""# {crew_name} Crew

## Identity
- **Crew ID:** {crew_id}
- **Name:** {crew_name}
- **Template:** {template}
- **Created:** {created_at}
- **Status:** active

## Purpose
{category_config.get('description', 'A specialized crew for collaborative AI tasks.')}

## Category
{template}

## Composition
- **Agents:** {len(agents or [])} assigned
- **Workflow:** {template}
- **Compliance:** Enterprise Grade

## Operational Standards
- Communication Protocol: Structured JSON
- Error Handling: Comprehensive with fallback
- Validation: Multi-point quality gates
- Security: Enterprise grade encryption and compliance

## Success Criteria
- 99.9% accuracy standard
- Real-time performance tracking
- Comprehensive audit logging
- Fault-tolerant operations
"""
    
    soul_path = crew_dir / "SOUL.md"
    soul_path.write_text(crew_soul)
    print(f"  Created: SOUL.md")
    
    # =========================================
    # 7. Create MEMORY.md for the crew
    # =========================================
    crew_memory = f"""# {crew_name} Crew - Memory

## Long-term Knowledge

### Crew History
- **Created:** {created_at}
- **Template:** {template}
- **Version:** 1.0.0

### Lessons Learned
*[To be populated during operations]*

### Key Decisions
*[Document major operational decisions here]*

### Best Practices
*[Add crew-specific best practices as they emerge]*

## Patterns and Anti-patterns

### What Works Well
- [ ] List successful strategies

### What to Avoid
- [ ] List anti-patterns to avoid
"""
    
    memory_path = crew_dir / "MEMORY.md"
    memory_path.write_text(crew_memory)
    print(f"  Created: MEMORY.md")
    
    # =========================================
    # 8. Create README.md
    # =========================================
    readme = f"""# {crew_name} Crew

A specialized crew created using the `{template}` template.

## Overview

This crew was generated by `create_crew.py` and includes:

- **{len(agents or [])} Agents** assigned with specific roles
- **Workflow configurations** for coordinated operations
- **Quality gates** and compliance standards
- **Error handling** and incident response workflows

## Quick Start

1. Assign agents to the crew
2. Configure agent-specific parameters
3. Activate the crew using Hermes
4. Monitor operations using the dashboard

## Configuration

- **Main Config:** `crew.json` - Crew metadata and agent assignments
- **Blueprints:** `blueprints/` - Individual agent configurations
- **Workflows:** `workflows/` - Operational workflows
- **Rules:** `rules/` - Compliance and operational rules
- **Communication:** `config/communication-standards.json`

## Usage

```bash
# Activate the crew
hermes crew activate {crew_name}

# Check status
hermes crew status {crew_name}

# Deactivate
hermes crew deactivate {crew_name}
```

## Files Generated

- [x] crew.json
- [x] SOUL.md
- [x] MEMORY.md
- [x] README.md
- [x] workflows/{template}_workflow.json
- [x] workflows/error_handling.json
- [x] workflows/incident_response.json
- [x] config/communication-standards.json
- [x] rules/* (from templates)
"""
    if agents:
        readme += f"\n- [x] blueprints/{{agent}}.json for each agent\n"
    
    readme_path = crew_dir / "README.md"
    readme_path.write_text(readme)
    print(f"  Created: README.md")
    
    # =========================================
    # 9. Create .gitignore
    # =========================================
    gitignore = """# Crew-specific ignore patterns
*.pyc
__pycache__/
.DS_Store
.env
*.enc
.secrets/
logs/
temp/
"""
    
    gitignore_path = crew_dir / ".gitignore"
    gitignore_path.write_text(gitignore)
    print(f"  Created: .gitignore")
    
    # Return info
    return {
        "crew_name": crew_name,
        "crew_id": crew_id,
        "crew_dir": str(crew_dir),
        "template": template,
        "agents": agents or [],
        "files_created": [
            "crew.json",
            "SOUL.md",
            "MEMORY.md",
            "README.md",
            "workflows/{template}_workflow.json",
            "workflows/error_handling.json",
            "workflows/incident_response.json",
            "config/communication-standards.json",
            ".gitignore"
        ] + ([f"blueprints/{a}.json" for a in (agents or [])] if agents else []),
        "success": True
    }


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Create crew folders with agent specifics, blueprints, and configurations"
    )
    parser.add_argument(
        "crew_name",
        nargs="?",
        help="Name of the crew to create"
    )
    parser.add_argument(
        "--template",
        default="project-manager",
        choices=list(CREW_CATEGORIES.keys()),
        help="Template to use for the crew"
    )
    parser.add_argument(
        "--agents",
        type=lambda s: s.split(",") if s else None,
        help="Comma-separated list of agent IDs to assign"
    )
    parser.add_argument(
        "--workflow",
        help="Custom workflow file path"
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing crew folder"
    )
    parser.add_argument(
        "--list-templates",
        action="store_true",
        help="List available templates and exit"
    )
    parser.add_argument(
        "--output",
        help="Output directory (default: ./crews)"
    )
    
    args = parser.parse_args()
    
    # List templates and exit
    if args.list_templates:
        print("Available Crew Templates:")
        print("=" * 50)
        for template_name, config in CREW_CATEGORIES.items():
            print(f"\n{template_name}:")
            print(f"  Description: {config.get('description', 'N/A')}")
            print(f"  Default Workflow: {config.get('default_workflow', 'N/A')}")
            print(f"  Recommended Agents: {len(config.get('recommended_agents', []))}")
            if config.get('recommended_agents'):
                for agent in config.get('recommended_agents', [])[:3]:
                    print(f"    - {agent}")
                if len(config.get('recommended_agents', [])) > 3:
                    print(f"    ... and {len(config.get('recommended_agents', [])) - 3} more")
        print("\n" + "=" * 50)
        print(f"\nUsage: {sys.argv[0]} <crew_name> --template <template_name>")
        return 0
    
    # Check if crew name is provided
    if not args.crew_name:
        print("Error: Crew name is required")
        print(f"Usage: {sys.argv[0]} <crew_name> [options]")
        print(f"Use --list-templates to see available templates")
        return 1
    
    # Set output directory if provided
    if args.output:
        global CREWS_DIR
        CREWS_DIR = Path(args.output).resolve()
    
    # Ensure crews directory exists
    ensure_directory(CREWS_DIR)
    
    # Set global agents dir if custom output
    if args.output:
        global AGENTS_DIR
        global PLUGINS_DIR
        AGENTS_DIR = CREWS_DIR.parent / "agents"
        PLUGINS_DIR = CREWS_DIR.parent / "plugins"
    
    try:
        # Generate the crew
        result = generate_crew_folder(
            crew_name=args.crew_name,
            template=args.template,
            agents=args.agents,
            workflow=args.workflow,
            overwrite=args.overwrite
        )
        
        print("\n" + "=" * 50)
        print(f"Crew '{args.crew_name}' created successfully!")
        print("=" * 50)
        print(f"\nLocation: {result['crew_dir']}")
        print(f"Crew ID: {result['crew_id']}")
        print(f"Template: {result['template']}")
        if result['agents']:
            print(f"Agents: {', '.join(result['agents'])}")
        print(f"\nFiles created:")
        for f in result['files_created']:
            print(f"  - {f}")
        
        print(f"\nNext steps:")
        print(f"  1. Review and customize crew.json")
        print(f"  2. Update agent blueprints as needed")
        print(f"  3. Assign additional rules and constraints")
        print(f"  4. Test the crew with a small task")
        
        return 0
        
    except FileExistsError as e:
        print(f"Error: {e}")
        return 1
    except Exception as e:
        print(f"Error creating crew: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
