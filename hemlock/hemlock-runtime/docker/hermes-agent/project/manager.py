"""
Project Manager - Autonomous Project Management

Provides:
- Autonomous project management loop
- Mission definition
- Blueprint creation
- Crew creation
- Progress monitoring
- Quality validation
- Dormant marking
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

from gateway.protocol import GatewayMessage, MessageType
from gateway.killswitch import KillswitchHandler
from paths import resolver

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ProjectManager:
    """
    Autonomous project management system.
    """

    def __init__(self, agent_id: str = "project-manager", message_queue: asyncio.Queue = None, projects_dir: str = None):
        self.agent_id = agent_id
        self.message_queue = message_queue or asyncio.Queue()
        self.killswitch = KillswitchHandler(message_queue)
        self.projects_dir = Path(projects_dir) if projects_dir else resolver.projects_dir
        self.projects_dir.mkdir(parents=True, exist_ok=True)

        # Project state
        self.current_project = None
        self.project_blueprint = None
        self.crew = None
        self.lead_agent = None
        self.progress = 0.0
        self.status = "pending"

        logger.info(f"Project manager initialized: {self.agent_id}")

    async def autonomous_loop(self) -> None:
        """
        Autonomous project management loop.

        Process:
        1. Define mission
        2. Create blueprint
        3. Get user approval
        4. Create crew
        5. Assign lead agent
        6. Monitor progress
        7. Validate quality
        8. Request final approval
        9. Mark dormant
        10. Retrospective
        """
        print("\n" * 2)
        print("=== AUTONOMOUS PROJECT MANAGEMENT LOOP ===")
        print("Press K to trigger killswitch at any time\n")

        try:
            # Step 1: Define mission
            mission = await self.define_mission()

            # Step 2: Create blueprint
            blueprint = await self.create_blueprint(mission)

            # Step 3: Get user approval
            if not await self.get_user_approval(blueprint):
                print("\nProject cancelled by user")
                return

            # Step 4: Create crew
            crew = await self.create_crew(blueprint)

            # Step 5: Assign lead agent
            lead_agent = await self.assign_lead_agent(crew)

            # Step 6: Monitor progress
            await self.monitor_progress(blueprint, crew, lead_agent)

            # Step 7: Validate quality
            if not await self.validate_quality(blueprint):
                print("\nQuality validation failed. Project needs revision.")
                return

            # Step 8: Request final approval
            if not await self.request_final_approval(blueprint):
                print("\nFinal approval not received. Project needs revision.")
                return

            # Step 9: Mark dormant
            await self.mark_dormant(blueprint)

            # Step 10: Retrospective
            await self.retrospective(blueprint)

        except KeyboardInterrupt:
            print("\nProject management loop interrupted")

    async def define_mission(self) -> Dict:
        """Define project mission."""
        print("\n=== DEFINE PROJECT MISSION ===")

        mission = {
            "name": input("  Project name: "),
            "description": input("  Project description: "),
            "objectives": [],
            "constraints": [],
            "deliverables": []
        }

        print("\n  Objectives (enter blank to finish):")
        while True:
            objective = input("    - ")
            if not objective:
                break
            mission["objectives"].append(objective)

        print("\n  Constraints (enter blank to finish):")
        while True:
            constraint = input("    - ")
            if not constraint:
                break
            mission["constraints"].append(constraint)

        print("\n  Deliverables (enter blank to finish):")
        while True:
            deliverable = input("    - ")
            if not deliverable:
                break
            mission["deliverables"].append(deliverable)

        print("\nMission defined successfully")
        return mission

    async def create_blueprint(self, mission: Dict) -> Dict:
        """Create project blueprint."""
        print("\n=== CREATE PROJECT BLUEPRINT ===")

        blueprint = {
            "mission": mission,
            "phases": [],
            "resources": [],
            "timeline": [],
            "quality_criteria": []
        }

        print("\n  Phases (enter blank to finish):")
        while True:
            phase = input("    - ")
            if not phase:
                break
            blueprint["phases"].append(phase)

        print("\n  Resources (enter blank to finish):")
        while True:
            resource = input("    - ")
            if not resource:
                break
            blueprint["resources"].append(resource)

        print("\n  Timeline (enter blank to finish):")
        while True:
            milestone = input("    - ")
            if not milestone:
                break
            blueprint["timeline"].append(milestone)

        print("\n  Quality Criteria (enter blank to finish):")
        while True:
            criterion = input("    - ")
            if not criterion:
                break
            blueprint["quality_criteria"].append(criterion)

        print("\nBlueprint created successfully")
        return blueprint

    async def get_user_approval(self, blueprint: Dict) -> bool:
        """Get user approval for blueprint."""
        print("\n=== USER APPROVAL ===")
        print("Please review the project blueprint:")
        print(json.dumps(blueprint, indent=2))

        while True:
            approval = input("\nApprove this blueprint? [y/n] ").lower()
            if approval in ['y', 'yes']:
                return True
            elif approval in ['n', 'no']:
                return False
            else:
                print("Please enter 'y' or 'n'")

    async def create_crew(self, blueprint: Dict) -> Dict:
        """Create project crew."""
        print("\n=== CREATE PROJECT CREW ===")

        crew = {
            "name": f"crew-{blueprint['mission']['name'].lower().replace(' ', '-')}",
            "agents": [],
            "resources": blueprint["resources"],
            "timeline": blueprint["timeline"]
        }

        print("\n  Agents (enter blank to finish):")
        while True:
            agent = input("    - ")
            if not agent:
                break
            crew["agents"].append(agent)

        print("\nCrew created successfully")
        return crew

    async def assign_lead_agent(self, crew: Dict) -> str:
        """Assign lead agent to crew."""
        print("\n=== ASSIGN LEAD AGENT ===")

        if not crew["agents"]:
            print("No agents in crew. Please add agents first.")
            return ""

        print("Available agents:")
        for i, agent in enumerate(crew["agents"]):
            print(f"  {i+1}. {agent}")

        while True:
            try:
                choice = int(input("Select lead agent (number): "))
                if 1 <= choice <= len(crew["agents"]):
                    lead_agent = crew["agents"][choice-1]
                    print(f"\nLead agent assigned: {lead_agent}")
                    return lead_agent
                else:
                    print(f"Please enter a number between 1 and {len(crew['agents'])}.")
            except ValueError:
                print("Please enter a valid number.")

    async def monitor_progress(self, blueprint: Dict, crew: Dict, lead_agent: str) -> None:
        """Monitor project progress."""
        print("\n=== MONITOR PROJECT PROGRESS ===")
        print("Monitoring progress... Press K to trigger killswitch")

        # Simulate progress monitoring
        for phase in blueprint["phases"]:
            print(f"\nStarting phase: {phase}")

            # Simulate work
            for i in range(1, 11):
                progress = i * 10
                print(f"  Progress: {progress}% - {phase}")

                # Check for killswitch
                if self.killswitch.is_triggered():
                    print("\nKILLSWITCH TRIGGERED - Project stopped")
                    return

                # Simulate delay
                await asyncio.sleep(1)

        print("\nProject progress monitoring complete")

    async def validate_quality(self, blueprint: Dict) -> bool:
        """Validate project quality."""
        print("\n=== QUALITY VALIDATION ===")

        print("Validating project quality against criteria:")
        for criterion in blueprint["quality_criteria"]:
            print(f"  - {criterion}")

        # Simulate quality validation
        print("\nQuality validation complete")

        while True:
            validation = input("Is the quality acceptable? [y/n] ").lower()
            if validation in ['y', 'yes']:
                return True
            elif validation in ['n', 'no']:
                return False
            else:
                print("Please enter 'y' or 'n'")

    async def request_final_approval(self, blueprint: Dict) -> bool:
        """Request final approval for project."""
        print("\n=== FINAL APPROVAL REQUEST ===")

        print("Please review the completed project:")
        print(json.dumps(blueprint, indent=2))

        while True:
            approval = input("\nApprove this project? [y/n] ").lower()
            if approval in ['y', 'yes']:
                return True
            elif approval in ['n', 'no']:
                return False
            else:
                print("Please enter 'y' or 'n'")

    async def mark_dormant(self, blueprint: Dict) -> None:
        """Mark project as dormant."""
        print("\n=== MARK PROJECT DORMANT ===")

        print("Project completed successfully. Marking as dormant.")

        # Save project to dormant directory
        dormant_dir = self.projects_dir / "dormant"
        dormant_dir.mkdir(parents=True, exist_ok=True)

        project_file = dormant_dir / f"{blueprint['mission']['name'].lower().replace(' ', '-')}.json"

        with open(project_file, 'w') as f:
            json.dump(blueprint, f, indent=2)

        print(f"\nProject saved to dormant state: {project_file}")

        # Request user acknowledgment
        while True:
            acknowledgment = input("\nAcknowledge dormant state? [y/n] ").lower()
            if acknowledgment in ['y', 'yes']:
                print("\nProject marked as dormant")
                return
            elif acknowledgment in ['n', 'no']:
                print("Please acknowledge the dormant state")
            else:
                print("Please enter 'y' or 'n'")

    async def retrospective(self, blueprint: Dict) -> None:
        """Conduct project retrospective."""
        print("\n=== PROJECT RETROSPECTIVE ===")

        print("Conducting retrospective analysis...")

        # Simulate retrospective
        print("\nRetrospective complete. Key learnings:")
        print("  - Project completed successfully")
        print("  - Team collaboration was effective")
        print("  - Quality standards were met")

        # Save retrospective
        retrospective_dir = self.projects_dir / "retrospectives"
        retrospective_dir.mkdir(parents=True, exist_ok=True)

        retrospective_file = retrospective_dir / f"{blueprint['mission']['name'].lower().replace(' ', '-')}.txt"

        with open(retrospective_file, 'w') as f:
            f.write("# PROJECT RETROSPECTIVE\n")
            f.write(f"Project: {blueprint['mission']['name']}\n")
            f.write(f"Date: {datetime.now().strftime('%Y-%m-%d')}\n")
            f.write("\nKey Learnings:\n")
            f.write("  - Project completed successfully\n")
            f.write("  - Team collaboration was effective\n")
            f.write("  - Quality standards were met\n")

        print(f"\nRetrospective saved: {retrospective_file}")

    async def trigger_killswitch(self, reason: str) -> None:
        """Trigger killswitch."""
        await self.killswitch.trigger(reason)

    def is_killswitch_triggered(self) -> bool:
        """Check if killswitch has been triggered."""
        return self.killswitch.is_triggered()

    def get_killswitch_reason(self) -> Optional[str]:
        """Get killswitch reason."""
        return self.killswitch.get_reason()


async def main():
    """CLI entry point."""
    import sys

    manager = ProjectManager()

    if len(sys.argv) > 1 and sys.argv[1] == 'test':
        # Test mode - run autonomous loop
        print("Starting test mode... Press K to trigger killswitch")
        await manager.autonomous_loop()
    else:
        print("Usage: python -m project.manager [test]")
        print("  test  - Start test mode with autonomous loop")


if __name__ == '__main__':
    asyncio.run(main())