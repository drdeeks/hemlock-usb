#!/usr/bin/env python3
"""
Standalone Enterprise Blueprint Skill - Checklist Generator

This is a simplified, standalone enterprise blueprint skill that generates
execution checklists for ANY project blueprint without requiring:
- Crew integration
- Agent management
- Self-healing loops
- Autonomous crew dependencies

It provides:
- Phase-based blueprint parsing
- Granular task generation from checklists
- Validation and verification workflows
- Enterprise-grade documentation structure
"""

import re
import sys
import json
import os
from pathlib import Path
from datetime import datetime

class EnterpriseBlueprintChecker:
    """
    Standalone enterprise blueprint workflow engine.
    
    Generates execution checklists from any project blueprint definition.
    Handles the complete workflow:
    1. Parse blueprint structure and phases
    2. Extract deliverables and requirements
    3. Generate granular execution checklists
    4. Provide validation and verification workflows
    """
    
    def __init__(self, blueprint_path, output_dir=None):
        self.blueprint = Path(blueprint_path).resolve()
        self.output_dir = Path(output_dir) if output_dir else self.blueprint.parent
        self.content = self.blueprint.read_text()
        self.chapters = self._parse_chapters()
        self.phases = self._extract_phases()
        self.tasks = self._extract_tasks()
        
    def _parse_chapters(self):
        """Parse blueprint chapters (Parts I-VII)."""
        chapters = {}
        # Look for chapter headers
        chapter_pattern = r"^## (Part [IVII]+) — ([^\n]+)"
        for match in re.finditer(r"^## (Part [IVII]+)", self.content, re.MULTILINE):
            chapter_id = match.group(1)
            # Find the next chapter or end
            next_match = re.search(r"^## Part ", self.content[match.end():], re.MULTILINE)
            chapter_content = self.content[match.end():next_match.start()] if next_match else self.content[match.end():]
            chapters[chapter_id] = chapter_content.strip()
        return chapters
    
    def _extract_phases(self):
        """Extract all project phases from blueprint with precise pattern matching."""
        phases = []
        
        # Pattern for various phase header formats:
        # ### 0: Foundation
        # ### PHASE-0: Foundation
        # ### 1: Authentication
        phase_pattern = r"^###\s*(?:PHASE-)?(\d+):\s*([^\n]+)"
        
        for match in re.finditer(phase_pattern, self.content, re.MULTILINE):
            phase_num = int(match.group(1))
            title = match.group(2).strip()
            phases.append({
                "number": phase_num,
                "title": title,
                "status": "pending",
                "tasks": []
            })
        
        # Debug output for verification
        print(f"[DEBUG] Parsed {len(phases)} phases from blueprint")
        for phase in phases:
            print(f"[DEBUG] Phase {phase['number']}: {phase['title']}")
        
        return phases
    
    def _extract_tasks_from_phase_section(self, phase_content, phase_num):
        """Extract tasks from a specific phase content section."""
        tasks = []
        
        # Look for task lines with various formats
        # Format 1: **PHASE-1.1** Task description
        # Format 2: - [ ] Task description
        # Format 3: **PHASE-1.V** Validation gate
        
        task_patterns = [
            # Pattern for bold phase headers: **PHASE-1.1** Task description
            r'\*\*PHASE-' + re.escape(phase_num) + r'\.\d+\*\*\s*(.+)',
            # Pattern for bold phase validation: **PHASE-1.V** Validation gate
            r'\*\*PHASE-' + re.escape(phase_num) + r'\.V\*\*\s*(.+)',
            # Pattern for unnumbered tasks with phase validation
            r'\*\*PHASE-\d+\.\d+\*\*\s*(.+)',
            # Pattern for simple unnumbered tasks
            r'- \[ \]\s*(.+)',
        ]
        
        for pattern in task_patterns:
            for match in re.finditer(pattern, phase_content):
                task_desc = match.group(1).strip()
                if task_desc and len(task_desc) > 3:  # Filter out short/empty matches
                    # Determine task type
                    if '**PHASE-' + phase_num + '.' in match.group(0):
                        # Extract step number if available
                        step_match = re.search(r'PHASE-' + re.escape(phase_num) + r'\.(\d+)', match.group(0))
                        step = step_match.group(1) if step_match else None
                        
                        task = {
                            "id": f"{phase_num}.{step or 'V'}",
                            "description": task_desc,
                            "phase": phase_num,
                            "step": step,
                            "status": "pending"
                        }
                    else:
                        task = {
                            "id": f"task-{len(tasks)}",
                            "description": task_desc,
                            "phase": phase_num,
                            "step": None,
                            "status": "pending"
                        }
                    
                    # Avoid duplicates
                    if task not in tasks:
                        tasks.append(task)
        
        return tasks
    
    def _extract_tasks(self):
        """Extract tasks from each phase with comprehensive parsing."""
        tasks = []
        
        # Split content by phase headers for more precise parsing
        phase_sections = []
        
        # Find all phase headers
        phase_headers = list(re.finditer(r"^###\s*(?:PHASE-)?(\d+):\s*([^\n]+)", self.content, re.MULTILINE))
        
        if not phase_headers:
            # Fallback: use simple line-by-line parsing for legacy formats
            lines = self.content.split('\n')
            current_phase = None
            
            for line in lines:
                # Check for phase header
                if re.match(r'^###\s*(?:PHASE-)?(\d+):', line):
                    current_phase = re.search(r'###\s*(?:PHASE-)?(\d+):', line).group(1)
                # Check for task lines
                elif current_phase and line.strip().startswith('- [ ]'):
                    tasks.append({
                        "id": f"task-{len(tasks)}",
                        "description": line.strip()[6:].strip(),
                        "phase": current_phase,
                        "step": None,
                        "status": "pending"
                    })
            return tasks
        
        # Process each phase section
        for i, header_match in enumerate(phase_headers):
            phase_num = header_match.group(1)
            title = header_match.group(2).strip()
            
            # Determine section bounds
            start_pos = header_match.end()
            end_pos = phase_headers[i + 1].start() if i + 1 < len(phase_headers) else len(self.content)
            
            # Extract phase-specific content
            phase_content = self.content[start_pos:end_pos]
            
            # Extract tasks within this phase
            phase_tasks = self._extract_tasks_from_phase_section(phase_content, phase_num)
            tasks.extend(phase_tasks)
        
        # Post-process: Ensure all tasks have valid phase numbers
        for task in tasks:
            if not task.get('phase') or task['phase'] == 'None':
                # Try to extract phase from description if missing
                desc_phase_match = re.search(r'PHASE-(\d+)\.', task['description'])
                if desc_phase_match:
                    task['phase'] = desc_phase_match.group(1)
        
        print(f"[DEBUG] Total tasks extracted: {len(tasks)}")
        return tasks
    
    def generate_checklist(self):
        """Generate execution checklist for the blueprint."""
        checklist_lines = []
        checklist_lines.append("# EXECUTION CHECKLIST")
        checklist_lines.append(f"*Generated from {self.blueprint.name} on {datetime.now().strftime('%Y-%m-%d')}*")
        checklist_lines.append("")
        
        # Executive Summary
        checklist_lines.append("## Executive Summary")
        checklist_lines.append(f"- **Blueprint File:** {self.blueprint.name}")
        checklist_lines.append(f"- **Total Phases:** {len(self.phases)}")
        checklist_lines.append(f"- **Total Tasks:** {len(self.tasks)}")
        checklist_lines.append(f"- **Status:** Planning Phase")
        checklist_lines.append("")
        
        # Phase-by-Phase Breakdown
        checklist_lines.append("## Phase-by-Phase Execution")
        checklist_lines.append("")
        
        for phase in self.phases:
            checklist_lines.append(f"### Phase {phase['number']}: {phase['title']}")
            
            # Filter tasks for this phase
            phase_tasks = [t for t in self.tasks if str(t['phase']) == phase['number']]
            
            if not phase_tasks:
                checklist_lines.append("*No tasks defined for this phase*")
                checklist_lines.append("")
                continue
            
            # Display tasks for this phase
            for task in phase_tasks:
                status = "✓" if task['status'] == 'completed' else "○"
                task_display = f"{task['description']}"
                checklist_lines.append(f"{status} **PHASE-{task['phase']}.{task['step'] if task['step'] else 'V'}** {task_display}")
            
            # Add validation gate indicator
            checklist_lines.append(f"- [ ] **PHASE-{phase['number']}.V** Validation gate: Verification required")
            checklist_lines.append("")
        
        # Task Dependencies
        checklist_lines.append("## Task Dependencies")
        checklist_lines.append("")
        checklist_lines.append("* **Sequential Execution:** Tasks must follow phase order")
        checklist_lines.append("* **Phase Validation:** Each phase requires validation gate completion")
        checklist_lines.append("* **Rollback Points:** All phases include rollback tag anchors")
        checklist_lines.append("")
        
        # Progress Indicators
        completed_tasks = len([t for t in self.tasks if t['status'] == 'completed'])
        total_tasks = len(self.tasks)
        
        checklist_lines.append("## Progress Dashboard")
        checklist_lines.append("")
        checklist_lines.append(f"- **Completed Tasks:** {completed_tasks}/{total_tasks}")
        completion_rate = (completed_tasks/total_tasks*100) if total_tasks > 0 else 0.0
        checklist_lines.append(f"- **Completion Rate:** {completion_rate:.1f}%")
        checklist_lines.append(f"- **Current Phase:** {len([p for p in self.phases if p['status'] == 'active'])}")
        checklist_lines.append(f"- **Next Phase:** {len([p for p in self.phases if p['status'] == 'pending']) + 1}")
        checklist_lines.append("")
        
        return "\n".join(checklist_lines)
    
    def write_checklist(self):
        """Write checklist to output directory."""
        checklist_filename = self.blueprint.stem.replace("blue", "checklist").replace("blueprint", "checklist") + ".md"
        checklist_path = self.output_dir / checklist_filename
        
        checklist_content = self.generate_checklist()
        checklist_path.write_text(checklist_content)
        
        print(f"[SUCCESS] Checklist generated: {checklist_path}")
        print(f"[INFO] Total phases: {len(self.phases)}")
        print(f"[INFO] Total tasks: {len(self.tasks)}")
        
        return checklist_path

    def validate_blueprint_structure(self):
        """Validate blueprint meets enterprise standards."""
        validation_results = {
            "valid": True,
            "errors": [],
            "warnings": [],
            "score": 100
        }
        
        # Check for required elements
        required_patterns = [
            (r"^## Part I", "Vision & Architecture chapter"),
            (r"^## Part II", "Module Registry chapter"),
            (r"^## Part III", "Specifications chapter"),
            (r"^## Part IV", "Data Architecture chapter"),
            (r"^## Part V", "Change Control chapter"),
            (r"^## Part VI", "Phase Checklists chapter"),
            (r"^## Part VII", "Quality Standards chapter"),
        ]
        
        for pattern, description in required_patterns:
            if not re.search(pattern, self.content, re.MULTILINE):
                validation_results["errors"].append(f"Missing {description}")
                validation_results["score"] -= 10
                validation_results["valid"] = False
        
        # Check for phases
        if len(self.phases) < 6:
            validation_results["warnings"].append(f"Only {len(self.phases)} phases found (recommend 6-7)")
            validation_results["score"] -= 5
        
        # Check for tasks
        if len(self.tasks) < 10:
            validation_results["warnings"].append(f"Only {len(self.tasks)} tasks found (recommend 15-20)")
            validation_results["score"] -= 5
        
        return validation_results

    def generate_workflow(self):
        """Generate execution workflow for the blueprint."""
        workflow = {
            "name": f"{self.blueprint.stem} Execution Workflow",
            "phases": [],
            "total_duration": "TBD",
            "resources": []
        }
        
        for phase in self.phases:
            phase_workflow = {
                "phase_id": phase["number"],
                "name": phase["title"],
                "estimated_hours": phase["number"] * 40,
                "status": phase["status"],
                "tasks": len([t for t in self.tasks if t['phase'] == str(phase['number'])]),
                "validation_required": True
            }
            workflow["phases"].append(phase_workflow)
        
        return workflow

def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Standalone Enterprise Blueprint Checker - Generate execution checklists from any blueprint",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  Generate checklist from existing blueprint:
    python3 enterprise_blueprint_checker.py ./my-project/blueprint.md

  Generate checklist in specific directory:
    python3 enterprise_blueprint_checker.py blueprint.md --output ./output

  Validate blueprint structure:
    python3 enterprise_blueprint_checker.py blueprint.md --validate

  Generate execution workflow:
    python3 enterprise_blueprint_checker.py blueprint.md --workflow

This tool is provider-agnostic and requires only Python 3.8+ stdlib.
No external dependencies or enterprise licensing required.
        """
    )
    
    parser.add_argument("blueprint", help="Path to the enterprise blueprint markdown file")
    parser.add_argument("--output", "-o", help="Output directory for checklist (default: blueprint's parent)")
    parser.add_argument("--validate", action="store_true", help="Validate blueprint meets enterprise standards")
    parser.add_argument("--workflow", action="store_true", help="Generate execution workflow plan")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    
    args = parser.parse_args()
    
    # Initialize checker
    checker = EnterpriseBlueprintChecker(args.blueprint, args.output)
    
    results = {
        "blueprint": str(checker.blueprint),
        "status": "success",
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }
    
    # Generate checklist
    checklist_path = checker.write_checklist()
    results["checklist_generated"] = str(checklist_path)
    
    # Validate if requested
    if args.validate:
        validation = checker.validate_blueprint_structure()
        results["validation"] = validation
    
    # Generate workflow if requested
    if args.workflow:
        workflow = checker.generate_workflow()
        results["workflow"] = workflow
    
    # Output results
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print("\n=== EXECUTION SUMMARY ===")
        print(f"✓ Blueprint: {checker.blueprint.name}")
        print(f"✓ Checklist Generated: {checklist_path.name}")
        print(f"✓ Total Phases: {len(checker.phases)}")
        print(f"✓ Total Tasks: {len(checker.tasks)}")
        
        if args.validate:
            validation = checker.validate_blueprint_structure()
            print(f"\n=== VALIDATION RESULTS ===")
            print(f"✓ Score: {validation['score']}/100")
            print(f"✓ Valid: {'Yes' if validation['valid'] else 'No'}")
            if validation['errors']:
                print(f"✗ Errors: {len(validation['errors'])}")
                for error in validation['errors']:
                    print(f"  - {error}")
            if validation['warnings']:
                print(f"⚠ Warnings: {len(validation['warnings'])}")
                for warning in validation['warnings']:
                    print(f"  - {warning}")
        
        if args.workflow:
            workflow = checker.generate_workflow()
            print(f"\n=== WORKFLOW PLAN ===")
            print(f"✓ Phases: {len(workflow['phases'])}")
            print(f"✓ Duration: TBD hours")
            print(f"✓ Resources: TBD")
    
    print("\n=== READY FOR EXECUTION ===")
    print(f"Checklist ready for team: {checklist_path}")
    print("All phases and tasks documented with validation gates.")

if __name__ == "__main__":
    main()
