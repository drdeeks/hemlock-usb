#!/usr/bin/env python3
"""
Crew Manager - Integrates project-manager with autonomous-crew-integration
Creates crews with blueprint enforcement, identity layer, and chain validation.
"""

import json
import sys
import os
import subprocess
from pathlib import Path
from datetime import datetime, timezone

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

class CrewManager:
    """Manages crew creation with blueprint enforcement and identity layer."""
    
    def __init__(self, workspace_root):
        self.workspace_root = Path(workspace_root)
        self.skills_dir = Path(__file__).parent.parent.parent
        self.crews_dir = self.skills_dir / "crews"
        self.pm_dir = self.crews_dir / "project-manager"
        self.rules_dir = self.crews_dir / "rules"
        
    def create_crew_with_blueprint(self, crew_name, project_dir, blueprint_path=None):
        """Create a crew with full blueprint enforcement and identity layer."""
        
        project_dir = Path(project_dir)
        if not project_dir.exists():
            print(f"Error: Project directory not found: {project_dir}")
            return False
        
        # Find blueprint
        if blueprint_path:
            bp_path = Path(blueprint_path)
        else:
            # Look for blueprint.md in project
            bp_path = project_dir / "blueprint.md"
            if not bp_path.exists():
                # Look for any blueprint
                for f in project_dir.glob("*blueprint*.md"):
                    bp_path = f
                    break
        
        if not bp_path.exists():
            print(f"Error: No blueprint found in {project_dir}")
            return False
        
        print(f"\n{'='*60}")
        print(f"CREW CREATION WITH BLUEPRINT ENFORCEMENT")
        print(f"{'='*60}")
        print(f"Crew: {crew_name}")
        print(f"Project: {project_dir}")
        print(f"Blueprint: {bp_path}")
        print(f"{'='*60}\n")
        
        # Step 1: Create crew using project-manager
        print("[1/6] Creating crew structure...")
        crew_dir = self._create_crew_structure(crew_name, project_dir)
        if not crew_dir:
            return False
        
        # Step 2: Initialize identity layer
        print("[2/6] Initializing identity layer...")
        self._initialize_identity_layer(crew_dir, crew_name)
        
        # Step 3: Create chain from blueprint
        print("[3/6] Creating chain from blueprint...")
        self._create_chain_from_blueprint(crew_dir, project_dir, bp_path)
        
        # Step 4: Generate phase validators
        print("[4/6] Generating phase validators...")
        self._generate_phase_validators(crew_dir, project_dir)
        
        # Step 5: Wire kanban to chain
        print("[5/6] Wiring kanban to chain...")
        self._wire_kanban(crew_dir, project_dir)
        
        # Step 6: Create enforcement rules
        print("[6/6] Creating enforcement rules...")
        self._create_enforcement_rules(crew_dir)
        
        print(f"\n{'='*60}")
        print(f"CREW CREATED SUCCESSFULLY")
        print(f"{'='*60}")
        print(f"Crew directory: {crew_dir}")
        print(f"Identity: {crew_dir / '.agent'}")
        print(f"Chain: {crew_dir / '.blueprint-chain'}")
        print(f"Rules: {crew_dir / 'rules'}")
        print(f"{'='*60}\n")
        
        return True
    
    def _create_crew_structure(self, crew_name, project_dir):
        """Create the crew directory structure."""
        crew_dir = project_dir / f".crew-{crew_name}"
        
        if crew_dir.exists():
            print(f"  Crew directory already exists: {crew_dir}")
            return crew_dir
        
        # Create subdirectories
        for subdir in ["agents", "config", "workflows", "rules", "memory", "projects", "blueprints"]:
            (crew_dir / subdir).mkdir(parents=True, exist_ok=True)
        
        # Create crew.json
        crew_config = {
            "crew_id": crew_name,
            "name": crew_name,
            "description": f"Crew for {project_dir.name}",
            "version": "1.0.0",
            "status": "active",
            "created_at": now_iso(),
            "project_dir": str(project_dir.absolute()),
            "agents": [],
            "workflows": {
                "primary": "./workflows/primary_workflow.json",
                "fallback": "./workflows/error_handling.json"
            },
            "quality_gates": {
                "validation_required": True,
                "quality_metrics": True,
                "multi_point_check": True
            }
        }
        
        crew_json_path = crew_dir / "crew.json"
        with open(crew_json_path, "w") as f:
            json.dump(crew_config, f, indent=2)
        
        print(f"  Created crew directory: {crew_dir}")
        return crew_dir
    
    def _initialize_identity_layer(self, crew_dir, crew_name):
        """Initialize the identity layer for the crew."""
        agent_dir = crew_dir / ".agent"
        agent_dir.mkdir(parents=True, exist_ok=True)
        
        # Create constitution
        constitution = f"""# Crew Constitution
## {crew_name}

### Identity
- Purpose: Execute project blueprint with identity-first architecture
- Principles: Complete deliverables, verify before claiming, honor constitution
- Authority: Project Manager oversees all operations

### Habits
1. identity-enforcement: Verify constitution hash before ANY tool invocation
2. tool-enforcement: Validate workspace hygiene before file writes
3. reflective-loop: Reflect after EVERY tool result
4. blueprint-phase-gate: Run chain verify+complete before claiming phase done

### Enforcement
- All phases must pass validation gates
- No phase skipping allowed
- Deliverables verified before completion
- Self-healing runs every 5 minutes
"""
        
        constitution_file = agent_dir / "constitution.yaml"
        constitution_file.write_text(constitution)
        
        # Create habits file
        habits = {
            "identity-enforcement": {
                "trigger": "Before ANY tool invocation",
                "action": "Verify constitution hash matches",
                "last_triggered": now_iso()
            },
            "tool-enforcement": {
                "trigger": "Before file write / external call",
                "action": "Validate workspace hygiene",
                "last_triggered": now_iso()
            },
            "reflective-loop": {
                "trigger": "After EVERY tool result",
                "action": "Reflect on advancement and violations",
                "last_triggered": now_iso()
            },
            "blueprint-phase-gate": {
                "trigger": "Before claiming phase complete",
                "action": "Run chain verify → complete",
                "last_triggered": now_iso()
            }
        }
        
        habits_file = agent_dir / "habits.json"
        with open(habits_file, "w") as f:
            json.dump(habits, f, indent=2)
        
        print(f"  Initialized identity layer: {agent_dir}")
    
    def _create_chain_from_blueprint(self, crew_dir, project_dir, blueprint_path):
        """Create chain from blueprint."""
        chain_dir = crew_dir / ".blueprint-chain"
        chain_dir.mkdir(parents=True, exist_ok=True)
        
        # Parse blueprint to extract phases
        content = blueprint_path.read_text()
        
        # Simple phase extraction (look for Phase markers)
        import re
        phases = []
        phase_pattern = r"###?\s*Phase\s+(\d+)[^.]*?[:–—]\s*(.+?)(?:\n|$)"
        for match in re.finditer(phase_pattern, content, re.IGNORECASE):
            phase_num = int(match.group(1))
            phase_title = match.group(2).strip()
            phases.append({"num": phase_num, "title": phase_title})
        
        if not phases:
            # Create default phases
            phases = [
                {"num": 0, "title": "Foundation & Infrastructure"},
                {"num": 1, "title": "Core Implementation"},
                {"num": 2, "title": "Integration & Testing"},
                {"num": 3, "title": "Deployment & Operations"}
            ]
        
        # Create chain state
        chain_state = {
            "name": f"{project_dir.name}-blueprint",
            "project": str(project_dir.absolute()),
            "crew": str(crew_dir.absolute()),
            "created_at": now_iso(),
            "blueprint": str(blueprint_path.absolute()),
            "steps": []
        }
        
        for i, phase in enumerate(phases):
            marker_file = chain_dir / f"phase-{phase['num']:02d}-{phase['title'].replace(' ', '-').replace('&', 'and')[:50]}.marker"
            marker_file.write_text(f"Phase {phase['num']} created")
            
            chain_step = {
                "index": phase["num"],
                "path": str(marker_file.absolute()),
                "state": "active" if i == 0 else "locked",
                "validator": None,
                "created_at": now_iso(),
                "verified_at": None,
                "completed_at": None,
                "attempts": 0,
                "title": phase["title"]
            }
            chain_state["steps"].append(chain_step)
        
        # Save chain state
        chain_file = chain_dir / f"{project_dir.name}-blueprint.json"
        with open(chain_file, "w") as f:
            json.dump(chain_state, f, indent=2)
        
        print(f"  Created chain with {len(phases)} phases: {chain_file}")
    
    def _generate_phase_validators(self, crew_dir, project_dir):
        """Generate phase validators."""
        validators_dir = crew_dir / "validators"
        validators_dir.mkdir(parents=True, exist_ok=True)
        
        # Read chain to get phases
        chain_files = list((crew_dir / ".blueprint-chain").glob("*-blueprint.json"))
        if not chain_files:
            print("  No chain found, skipping validator generation")
            return
        
        with open(chain_files[0]) as f:
            chain = json.load(f)
        
        for step in chain["steps"]:
            phase_num = step["index"]
            phase_title = step.get("title", f"Phase {phase_num}")
            
            validator_content = f'''#!/usr/bin/env python3
"""
Phase {phase_num} Validator: {phase_title}
Validates deliverables exist and are non-empty.
"""

import json
import sys
from pathlib import Path

def validate():
    """Validate phase {phase_num} deliverables."""
    project_dir = Path("{project_dir}")
    results = []
    all_passed = True
    
    # Common deliverables
    deliverables = [
        {{"name": "package.json", "path": "package.json", "type": "file", "min_size": 50}},
        {{"name": "README.md", "path": "README.md", "type": "file", "min_size": 100}},
        {{"name": "src directory", "path": "src", "type": "directory"}},
    ]
    
    for deliverable in deliverables:
        path = project_dir / deliverable["path"]
        expected_type = deliverable.get("type", "file")
        min_size = deliverable.get("min_size", 1)
        
        if not path.exists():
            results.append({{
                "deliverable": deliverable["name"],
                "path": str(path),
                "status": "FAIL",
                "reason": "File does not exist"
            }})
            all_passed = False
            continue
        
        if expected_type == "file":
            size = path.stat().st_size
            if size < min_size:
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "FAIL",
                    "reason": f"File too small: {{size}} bytes (min: {{min_size}})"
                }})
                all_passed = False
            else:
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "PASS",
                    "size": size
                }})
        elif expected_type == "directory":
            if not path.is_dir():
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "FAIL",
                    "reason": "Path is not a directory"
                }})
                all_passed = False
            else:
                file_count = len(list(path.rglob("*")))
                results.append({{
                    "deliverable": deliverable["name"],
                    "path": str(path),
                    "status": "PASS",
                    "file_count": file_count
                }})
    
    return {{"passed": all_passed, "results": results}}

if __name__ == "__main__":
    result = validate()
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["passed"] else 1)
'''
            
            validator_file = validators_dir / f"validate-phase-{phase_num:02d}.py"
            validator_file.write_text(validator_content)
            validator_file.chmod(0o755)
        
        print(f"  Generated {len(chain['steps'])} phase validators")
    
    def _wire_kanban(self, crew_dir, project_dir):
        """Wire kanban to chain."""
        # This would wire to the kanban database
        # For now, create a reference
        wire_config = {
            "crew_dir": str(crew_dir.absolute()),
            "project_dir": str(project_dir.absolute()),
            "chain_dir": str(crew_dir / ".blueprint-chain"),
            "kanban_db": str(Path.home() / ".hermes" / "kanban.db"),
            "created_at": now_iso()
        }
        
        wire_file = crew_dir / "config" / "kanban-wiring.json"
        with open(wire_file, "w") as f:
            json.dump(wire_config, f, indent=2)
        
        print(f"  Created kanban wiring config: {wire_file}")
    
    def _create_enforcement_rules(self, crew_dir):
        """Create enforcement rules from crew rules."""
        rules_dir = crew_dir / "rules"
        
        # Copy rules from the crew rules directory
        if self.rules_dir.exists():
            for rule_file in self.rules_dir.glob("*.json"):
                dest = rules_dir / rule_file.name
                if not dest.exists():
                    import shutil
                    shutil.copy2(str(rule_file), str(dest))
        
        print(f"  Created enforcement rules: {rules_dir}")

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Crew Manager - Create crews with blueprint enforcement")
    parser.add_argument("--crew-name", required=True, help="Name of the crew")
    parser.add_argument("--project-dir", required=True, help="Project directory")
    parser.add_argument("--blueprint", help="Path to blueprint.md (optional)")
    parser.add_argument("--workspace", default="${WORKSPACE_ROOT}/qwen-cloud-2026", help="Workspace root")
    args = parser.parse_args()
    
    manager = CrewManager(args.workspace)
    success = manager.create_crew_with_blueprint(
        args.crew_name,
        args.project_dir,
        args.blueprint
    )
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
