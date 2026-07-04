#!/usr/bin/env python3
"""
Crew Blueprint Management - Python implementation
Incorporates autonomous-crew logic for Hemlock framework
"""

import json
import os
import sys
import hashlib
from datetime import datetime, timezone
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
CREWS_DIR = ROOT_DIR / "crews"
BLUEPRINTS_DIR = ROOT_DIR / "docs" / "blueprints"
CHECKPOINTS_DIR = ROOT_DIR / "docs" / "checkpoints"

# Agent type definitions from autonomous-crew
AGENT_TYPES = {
    "lead": {
        "description": "Lead agent - Coordinator and manager",
        "workflow": [
            "Create project blueprint",
            "Coordinate agent activities",
            "Monitor progress",
            "Validate results",
            "Create checkpoints"
        ]
    },
    "ui": {
        "description": "UI/UX Specialist - Design and user experience",
        "workflow": [
            "Analyze UI requirements",
            "Design user interface",
            "Implement UI components",
            "Test UI functionality",
            "Optimize user experience"
        ]
    },
    "integration": {
        "description": "Integration Architect - System integration and data flow",
        "workflow": [
            "Analyze system architecture",
            "Design integration points",
            "Implement connections",
            "Test data flow",
            "Optimize performance"
        ]
    },
    "blockchain": {
        "description": "Blockchain & Security - Security implementation and blockchain",
        "workflow": [
            "Analyze security requirements",
            "Implement security measures",
            "Integrate blockchain features",
            "Test security",
            "Validate encryption"
        ]
    },
    "debugger": {
        "description": "Debugger - Issue identification and resolution",
        "workflow": [
            "Identify issues",
            "Analyze root causes",
            "Implement fixes",
            "Test solutions",
            "Document resolutions"
        ]
    },
    "documentation": {
        "description": "Documentation Specialist - Documentation and knowledge management",
        "workflow": [
            "Gather project information",
            "Create documentation structure",
            "Write comprehensive docs",
            "Review and validate",
            "Maintain documentation"
        ]
    },
    "optimization": {
        "description": "Optimization Expert - Performance analysis and optimization",
        "workflow": [
            "Analyze performance",
            "Identify bottlenecks",
            "Implement optimizations",
            "Test improvements",
            "Monitor results"
        ]
    },
    "architecture": {
        "description": "Architecture - System design and organization",
        "workflow": [
            "Analyze requirements",
            "Design system architecture",
            "Create organizational structure",
            "Implement architecture",
            "Validate design"
        ]
    },
    "validation": {
        "description": "Validation Expert - Testing and quality assurance",
        "workflow": [
            "Create test plans",
            "Implement test suites",
            "Execute tests",
            "Validate results",
            "Report findings"
        ]
    }
}

# Workflow phases from autonomous-crew
PHASES = {
    "planning": {
        "description": "Analyze requirements, define success criteria, create detailed plan",
        "steps": [
            "Analyze project requirements",
            "Define success criteria",
            "Identify agent assignments",
            "Create detailed plan"
        ]
    },
    "confirmation": {
        "description": "Review blueprint, validate agent assignments, establish protocols",
        "steps": [
            "Review blueprint",
            "Validate agent assignments",
            "Establish communication protocols",
            "Set up checkpoints"
        ]
    },
    "acting": {
        "description": "Execute tasks autonomously, commit changes, checkpoint regularly",
        "steps": []
    },
    "validation": {
        "description": "End-to-end testing, documentation review, validate against criteria",
        "steps": [
            "End-to-end testing",
            "Documentation review",
            "Blueprint vs actual comparison",
            "Changelog validation"
        ]
    },
    "completed": {
        "description": "All success criteria met, project finished",
        "steps": []
    }
}


def ensure_dirs():
    """Ensure required directories exist"""
    CREWS_DIR.mkdir(parents=True, exist_ok=True)
    BLUEPRINTS_DIR.mkdir(parents=True, exist_ok=True)
    CHECKPOINTS_DIR.mkdir(parents=True, exist_ok=True)


def generate_blueprint_id():
    """Generate a unique blueprint ID"""
    return hashlib.md5(datetime.now().isoformat().encode()).hexdigest()[:8]


def generate_checkpoint_id(description):
    """Generate a checkpoint ID"""
    timestamp = datetime.now(timezone.utc).isoformat()
    return hashlib.md5(f"{timestamp}:{description}".encode()).hexdigest()[:8]


def create_blueprint(crew_name, agent_types=None, project_name=None, success_criteria=None):
    """Create a new crew blueprint"""
    ensure_dirs()
    
    # Set defaults
    if agent_types is None:
        agent_types = ["lead", "ui", "integration", "documentation"]
    if project_name is None:
        project_name = crew_name
    if success_criteria is None:
        success_criteria = [
            "Project completed successfully",
            "All acceptance criteria met",
            "No critical issues remaining"
        ]
    
    # Validate agent types
    for at in agent_types:
        if at not in AGENT_TYPES:
            print(f"Error: Invalid agent type '{at}'. Valid types: {', '.join(AGENT_TYPES.keys())}", file=sys.stderr)
            sys.exit(1)
    
    blueprint_id = generate_blueprint_id()
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # Create agent configurations
    agents = []
    for at in agent_types:
        info = AGENT_TYPES[at]
        agent_id = f"{at}-1"
        display_name = at.replace("-", " ").title()
        
        agents.append({
            "agent_id": agent_id,
            "agent_type": at,
            "display_name": display_name,
            "description": info["description"],
            "workflow": info["workflow"],
            "status": "ready",
            "joined_at": None,
            "completed_tasks": 0
        })
    
    # Build acting phase steps from agent workflows
    acting_steps = []
    for at in agent_types:
        workflow = AGENT_TYPES[at]["workflow"]
        for step in workflow:
            acting_steps.append(f"{at} agent: {step}")
    
    # Update acting phase steps
    PHASES["acting"]["steps"] = acting_steps
    
    # Build workflow steps
    workflow_steps = []
    for phase_name in ["planning", "confirmation", "acting", "validation", "completed"]:
        workflow_steps.append({
            "phase": phase_name,
            "steps": PHASES[phase_name]["steps"]
        })
    
    # Create blueprint
    blueprint = {
        "blueprint_id": blueprint_id,
        "crew_name": crew_name,
        "project_name": project_name,
        "version": "1.0.0",
        "created_at": timestamp,
        "updated_at": timestamp,
        "status": "draft",
        "current_phase": "planning",
        "success_criteria": success_criteria,
        "expected_outcomes": [
            "Project completed successfully",
            "All acceptance criteria met",
            "Documentation up to date",
            "No critical issues"
        ],
        "success_measures": [
            "All success criteria met",
            "All agents completed tasks",
            "Checkpoints created at key milestones"
        ],
        "agent_types": agent_types,
        "agents": agents,
        "workflow_steps": workflow_steps,
        "checkpoints": [],
        "changelog": [],
        "metadata": {
            "created_by": "crew_blueprint.py",
            "framework": "Hemlock Enterprise",
            "source": "autonomous-crew inspired"
        }
    }
    
    # Save blueprint
    blueprint_file = BLUEPRINTS_DIR / f"{crew_name}.json"
    with open(blueprint_file, 'w') as f:
        json.dump(blueprint, f, indent=2)
    
    # Create crew directory and crew.json
    crew_dir = CREWS_DIR / crew_name
    crew_dir.mkdir(parents=True, exist_ok=True)
    
    crew_json = {
        "crew_id": blueprint_id,
        "name": crew_name,
        "description": f"{project_name} crew",
        "version": "1.0.0",
        "blueprint": blueprint_id,
        "agents": [],
        "workflows": {"primary": "autonomous", "fallback": "manual"},
        "status": "draft",
        "created_at": timestamp,
        "updated_at": timestamp,
        "metadata": {"created_by": "crew_blueprint.py", "template": "autonomous-crew"}
    }
    
    with open(crew_dir / "crew.json", 'w') as f:
        json.dump(crew_json, f, indent=2)
    
    # Initialize checkpoints directory
    cp_dir = CHECKPOINTS_DIR / crew_name
    cp_dir.mkdir(parents=True, exist_ok=True)
    (cp_dir / ".gitkeep").touch()
    
    return blueprint_id, len(agents)


def list_blueprints():
    """List all crew blueprints"""
    if not BLUEPRINTS_DIR.exists():
        print("No blueprints directory found")
        return
    
    blueprints = []
    for bp_file in BLUEPRINTS_DIR.glob("*.json"):
        with open(bp_file) as f:
            bp = json.load(f)
        blueprints.append(bp)
    
    if not blueprints:
        print("No blueprints found")
        return
    
    for bp in blueprints:
        print(f"\n  {bp['crew_name']}")
        print(f"    Phase: {bp.get('current_phase', 'unknown')}")
        print(f"    Agents: {len(bp.get('agent_types', []))}")
        print(f"    Checkpoints: {len(bp.get('checkpoints', []))}")
    
    print(f"\nTotal: {len(blueprints)} blueprint(s)")


def show_blueprint(crew_name):
    """Show blueprint details"""
    blueprint_file = BLUEPRINTS_DIR / f"{crew_name}.json"
    if not blueprint_file.exists():
        print(f"Error: Blueprint not found for crew '{crew_name}'", file=sys.stderr)
        sys.exit(1)
    
    with open(blueprint_file) as f:
        bp = json.load(f)
    
    print(f"\nBLUEPRINT: {bp.get('project_name', bp.get('crew_name', 'Unknown'))}")
    print("=" * 80)
    print(f"ID: {bp.get('blueprint_id', 'N/A')}")
    print(f"Version: {bp.get('version', 'N/A')}")
    print(f"Status: {bp.get('status', 'N/A')}")
    print(f"Current Phase: {bp.get('current_phase', 'N/A')}")
    print(f"Created: {bp.get('created_at', 'N/A')}")
    print(f"Updated: {bp.get('updated_at', 'N/A')}")
    
    print(f"\nSUCCESS CRITERIA ({len(bp.get('success_criteria', []))}):")
    for i, sc in enumerate(bp.get('success_criteria', []), 1):
        print(f"  {i}. {sc}")
    
    print(f"\nAGENT TYPES ({len(bp.get('agent_types', []))}):")
    for at in bp.get('agent_types', []):
        print(f"  - {at}")
    
    print(f"\nCHECKPOINTS ({len(bp.get('checkpoints', []))}):")
    if bp.get('checkpoints'):
        for cp in bp.get('checkpoints', []):
            print(f"  - {cp.get('id', 'N/A')}: {cp.get('description', 'N/A')} ({cp.get('timestamp', 'N/A')})")
    else:
        print("  None")
    
    print(f"\nWORKFLOW STEPS:")
    for phase in bp.get('workflow_steps', []):
        print(f"\n  Phase: {phase.get('phase', 'N/A')}")
        for step in phase.get('steps', []):
            print(f"    - {step}")


def set_phase(crew_name, new_phase):
    """Set workflow phase"""
    if new_phase not in PHASES:
        print(f"Error: Invalid phase '{new_phase}'. Valid phases: {', '.join(PHASES.keys())}", file=sys.stderr)
        sys.exit(1)
    
    blueprint_file = BLUEPRINTS_DIR / f"{crew_name}.json"
    if not blueprint_file.exists():
        print(f"Error: Blueprint not found for crew '{crew_name}'", file=sys.stderr)
        sys.exit(1)
    
    with open(blueprint_file) as f:
        bp = json.load(f)
    
    bp['current_phase'] = new_phase
    bp['updated_at'] = datetime.now(timezone.utc).isoformat()
    
    if 'changelog' not in bp:
        bp['changelog'] = []
    
    bp['changelog'].append({
        'timestamp': bp['updated_at'],
        'action': 'phase_change',
        'from_phase': bp.get('current_phase', 'unknown'),
        'to_phase': new_phase,
        'details': f'Phase changed to {new_phase}'
    })
    
    with open(blueprint_file, 'w') as f:
        json.dump(bp, f, indent=2)
    
    return new_phase


def create_checkpoint(crew_name, description):
    """Create a checkpoint"""
    blueprint_file = BLUEPRINTS_DIR / f"{crew_name}.json"
    if not blueprint_file.exists():
        print(f"Error: Blueprint not found for crew '{crew_name}'", file=sys.stderr)
        sys.exit(1)
    
    with open(blueprint_file) as f:
        bp = json.load(f)
    
    timestamp = datetime.now(timezone.utc).isoformat()
    checkpoint_id = generate_checkpoint_id(description)
    current_phase = bp.get('current_phase', 'unknown')
    
    # Save checkpoint file
    cp_dir = CHECKPOINTS_DIR / crew_name
    cp_dir.mkdir(parents=True, exist_ok=True)
    
    checkpoint = {
        "checkpoint_id": checkpoint_id,
        "description": description,
        "timestamp": timestamp,
        "phase": current_phase,
        "crew_name": crew_name
    }
    
    with open(cp_dir / f"{checkpoint_id}.json", 'w') as f:
        json.dump(checkpoint, f, indent=2)
    
    # Update blueprint
    if 'checkpoints' not in bp:
        bp['checkpoints'] = []
    
    bp['checkpoints'].append({
        'id': checkpoint_id,
        'description': description,
        'timestamp': timestamp,
        'phase': current_phase
    })
    bp['updated_at'] = timestamp
    
    if 'changelog' not in bp:
        bp['changelog'] = []
    
    bp['changelog'].append({
        'timestamp': timestamp,
        'action': 'checkpoint_created',
        'checkpoint_id': checkpoint_id,
        'description': description,
        'phase': current_phase
    })
    
    with open(blueprint_file, 'w') as f:
        json.dump(bp, f, indent=2)
    
    return checkpoint_id


def list_checkpoints(crew_name):
    """List checkpoints for a crew"""
    cp_dir = CHECKPOINTS_DIR / crew_name
    if not cp_dir.exists():
        print(f"No checkpoints directory for crew '{crew_name}'")
        return
    
    checkpoints = []
    for cp_file in cp_dir.glob("*.json"):
        with open(cp_file) as f:
            cp = json.load(f)
        checkpoints.append(cp)
    
    if not checkpoints:
        print(f"No checkpoints found for crew '{crew_name}'")
        return
    
    print(f"\nCheckpoints for crew '{crew_name}':")
    for cp in checkpoints:
        print(f"\n  {cp['checkpoint_id']}")
        print(f"    Description: {cp.get('description', 'N/A')}")
        print(f"    Created: {cp.get('timestamp', 'N/A')}")
        print(f"    Phase: {cp.get('phase', 'N/A')}")
    
    print(f"\nTotal: {len(checkpoints)} checkpoint(s)")


def validate_success(crew_name):
    """Validate success criteria"""
    blueprint_file = BLUEPRINTS_DIR / f"{crew_name}.json"
    if not blueprint_file.exists():
        print(f"Error: Blueprint not found for crew '{crew_name}'", file=sys.stderr)
        sys.exit(1)
    
    with open(blueprint_file) as f:
        bp = json.load(f)
    
    criteria = bp.get('success_criteria', [])
    print(f"\nSuccess Criteria ({len(criteria)}):")
    for i, c in enumerate(criteria, 1):
        status = '✓' if bp.get('current_phase') == 'completed' else '✗'
        print(f"  {status} {i}. {c}")
    
    print(f"\nCurrent Phase: {bp.get('current_phase', 'unknown')}")
    print(f"Status: {bp.get('status', 'unknown')}")
    
    if bp.get('current_phase') == 'completed':
        print("\n✓ All success criteria met - Project completed!")
    else:
        print("\n✗ Not all criteria met yet. Continue workflow.")


def list_types():
    """List available agent types"""
    print("\nAvailable Agent Types:")
    for at, info in AGENT_TYPES.items():
        print(f"  - {at}: {info['description']}")


def list_phases():
    """List workflow phases"""
    print("\nWorkflow Phases:")
    for phase, info in PHASES.items():
        print(f"  - {phase}: {info['description']}")


def main():
    if len(sys.argv) < 2:
        print("Usage: crew_blueprint.py <command> [args]", file=sys.stderr)
        print("\nCommands:", file=sys.stderr)
        print("  create <name> [--agents types] [--project name]  Create blueprint", file=sys.stderr)
        print("  list                                          List all blueprints", file=sys.stderr)
        print("  show <name>                                   Show blueprint", file=sys.stderr)
        print("  set-phase <crew> <phase>                     Set workflow phase", file=sys.stderr)
        print("  checkpoint <crew> <desc>                     Create checkpoint", file=sys.stderr)
        print("  list-cp <crew>                               List checkpoints", file=sys.stderr)
        print("  validate <crew>                               Validate success", file=sys.stderr)
        print("  list-types                                   List agent types", file=sys.stderr)
        print("  list-phases                                  List workflow phases", file=sys.stderr)
        sys.exit(1)
    
    command = sys.argv[1]
    args = sys.argv[2:]
    
    try:
        if command == "create":
            # Parse arguments
            crew_name = args[0] if args else None
            agent_types = None
            project_name = None
            success_criteria = None
            
            i = 1
            while i < len(args):
                if args[i] in ["--agents", "-a"] and i + 1 < len(args):
                    agent_types = args[i + 1].split(",")
                    i += 2
                elif args[i] in ["--project", "-p"] and i + 1 < len(args):
                    project_name = args[i + 1]
                    i += 2
                elif args[i] in ["--success", "-s"] and i + 1 < len(args):
                    success_criteria = args[i + 1].split("|")
                    i += 2
                else:
                    print(f"Error: Unknown option {args[i]}", file=sys.stderr)
                    sys.exit(1)
            
            if not crew_name:
                print("Error: Crew name required", file=sys.stderr)
                sys.exit(1)
            
            blueprint_id, num_agents = create_blueprint(crew_name, agent_types, project_name, success_criteria)
            print(f"Created blueprint for crew '{crew_name}' with {num_agents} agents")
            print(f"  ID: {blueprint_id}")
            print(f"  Phase: planning")
        
        elif command == "list":
            list_blueprints()
        
        elif command == "show":
            if not args:
                print("Error: Crew name required", file=sys.stderr)
                sys.exit(1)
            show_blueprint(args[0])
        
        elif command == "set-phase":
            if len(args) < 2:
                print("Error: Crew name and phase required", file=sys.stderr)
                sys.exit(1)
            new_phase = set_phase(args[0], args[1])
            print(f"Phase updated to: {new_phase}")
        
        elif command == "checkpoint":
            if len(args) < 2:
                print("Error: Crew name and description required", file=sys.stderr)
                sys.exit(1)
            cp_id = create_checkpoint(args[0], args[1])
            print(f"Created checkpoint: {cp_id}")
        
        elif command == "list-cp":
            if not args:
                print("Error: Crew name required", file=sys.stderr)
                sys.exit(1)
            list_checkpoints(args[0])
        
        elif command == "validate":
            if not args:
                print("Error: Crew name required", file=sys.stderr)
                sys.exit(1)
            validate_success(args[0])
        
        elif command == "list-types":
            list_types()
        
        elif command == "list-phases":
            list_phases()
        
        else:
            print(f"Error: Unknown command '{command}'", file=sys.stderr)
            sys.exit(1)
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
