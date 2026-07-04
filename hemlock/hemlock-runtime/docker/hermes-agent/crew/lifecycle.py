"""
Crew Lifecycle Manager - Crew Creation, Dormancy, Deletion, and State Management

Provides:
- Crew creation with crew agents
- Crew dormancy with user acknowledgment
- Crew reactivation with state restoration
- Crew deletion with cleanup
- State export/restore
- State transition validation
"""

import asyncio
import json
import logging
import os
import shutil
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Any

from gateway.protocol import GatewayMessage, MessageType
from gateway.killswitch import KillswitchHandler

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class CrewState(str, Enum):
    """Valid crew states for lifecycle management."""
    CREATED = "created"
    ACTIVE = "active"
    COMPLETED = "completed"
    DORMANT = "dormant"
    REACTIVATED = "reactivated"
    ARCHIVED = "archived"
    DELETED = "deleted"


# Valid state transitions: from -> set of allowed targets
VALID_TRANSITIONS: Dict[str, set] = {
    CrewState.CREATED: {CrewState.ACTIVE, CrewState.ARCHIVED},
    CrewState.ACTIVE: {CrewState.COMPLETED, CrewState.DORMANT, CrewState.ARCHIVED},
    CrewState.COMPLETED: {CrewState.DORMANT, CrewState.ARCHIVED},
    CrewState.DORMANT: {CrewState.ACTIVE, CrewState.ARCHIVED},
    CrewState.REACTIVATED: {CrewState.ACTIVE, CrewState.COMPLETED, CrewState.DORMANT, CrewState.ARCHIVED},
    CrewState.ARCHIVED: set(),
    CrewState.DELETED: set(),
}


class CrewLifecycleError(Exception):
    """Base exception for crew lifecycle errors."""
    pass


class CrewNotFoundError(CrewLifecycleError):
    """Raised when a crew is not found."""
    pass


class InvalidStateTransitionError(CrewLifecycleError):
    """Raised when a state transition is not allowed."""
    pass


class CrewLifecycleManager:
    """
    Manages crew lifecycle including creation, dormancy, reactivation, and deletion.
    Enforces valid state transitions and preserves crew state across lifecycle changes.
    """

    def __init__(self, crews_dir: str = None, agents_dir: str = None):
        from paths import resolver
        self.crews_dir = Path(crews_dir) if crews_dir else resolver.crews_dir
        self.agents_dir = Path(agents_dir) if agents_dir else resolver.agents_dir
        self.projects_dir = resolver.projects_dir

        for d in [self.crews_dir, self.projects_dir]:
            try:
                d.mkdir(parents=True, exist_ok=True)
            except PermissionError:
                logger.warning(f"Cannot create directory (permission denied): {d}")

        self.killswitch = KillswitchHandler()
        logger.info("Crew lifecycle manager initialized")

    def _validate_transition(self, current_state: str, new_state: str) -> None:
        """
        Validate that a state transition is allowed.

        Args:
            current_state: Current crew state
            new_state: Target crew state

        Raises:
            InvalidStateTransitionError: If transition is not allowed
        """
        current = CrewState(current_state) if current_state else CrewState.CREATED
        target = CrewState(new_state)

        allowed = VALID_TRANSITIONS.get(current, set())
        if target not in allowed and target != CrewState.DELETED:
            raise InvalidStateTransitionError(
                f"Invalid transition: {current.value} -> {target.value}. "
                f"Allowed: {[s.value for s in allowed]}"
            )

    def _load_crew(self, crew_name: str) -> Dict:
        """Load crew manifest. Returns empty dict if not found."""
        crew_dir = self.crews_dir / crew_name
        manifest_path = crew_dir / "crew.json"

        if manifest_path.exists():
            with open(manifest_path, 'r') as f:
                return json.load(f)
        return {}

    def _save_crew(self, crew_name: str, crew_data: Dict) -> None:
        """Save crew manifest."""
        crew_dir = self.crews_dir / crew_name
        manifest_path = crew_dir / "crew.json"
        with open(manifest_path, 'w') as f:
            json.dump(crew_data, f, indent=2)

    async def create_crew(self, crew_name: str, agents: List[str],
                          resources: Dict = None) -> Dict:
        """
        Create a new crew with specified agents.

        Args:
            crew_name: Name of the crew
            agents: List of agent IDs
            resources: Crew resources

        Returns:
            Crew information dictionary

        Raises:
            CrewLifecycleError: If crew already exists
        """
        logger.info(f"Creating crew: {crew_name}")

        crew_dir = self.crews_dir / crew_name
        if crew_dir.exists():
            existing = self._load_crew(crew_name)
            if existing:
                raise CrewLifecycleError(
                    f"Crew already exists: {crew_name} (status: {existing.get('status', 'unknown')})"
                )

        crew_dir.mkdir(parents=True, exist_ok=True)

        # Create directory structure
        (crew_dir / "state").mkdir(exist_ok=True)
        (crew_dir / "logs").mkdir(exist_ok=True)
        (crew_dir / "backups").mkdir(exist_ok=True)

        crew = {
            "name": crew_name,
            "created_at": datetime.now().isoformat(),
            "status": CrewState.CREATED.value,
            "agents": agents,
            "resources": resources or {},
            "state": {},
            "version": "1.0"
        }

        self._save_crew(crew_name, crew)

        # Create each crew agent
        for agent_id in agents:
            await self._create_crew_agent(crew_name, agent_id)

        logger.info(f"Crew created: {crew_name} with {len(agents)} agents")
        return crew

    async def _create_crew_agent(self, crew_name: str, agent_id: str) -> None:
        """
        Create an agent as part of a crew.

        Args:
            crew_name: Crew name
            agent_id: Agent ID
        """
        agent_dir = self.agents_dir / agent_id
        agent_dir.mkdir(parents=True, exist_ok=True)

        # Create agent identity for crew
        identity = {
            "agent_id": agent_id,
            "crew": crew_name,
            "role": "crew_member",
            "created_at": datetime.now().isoformat(),
            "status": "active"
        }

        identity_path = agent_dir / "identity.json"
        with open(identity_path, 'w') as f:
            json.dump(identity, f, indent=2)

    async def activate_crew(self, crew_name: str) -> Dict:
        """
        Activate a crew (transition from created to active).

        Args:
            crew_name: Crew name

        Returns:
            Activation confirmation
        """
        logger.info(f"Activating crew: {crew_name}")
        crew = self._load_crew(crew_name)
        if not crew:
            raise CrewNotFoundError(f"Crew not found: {crew_name}")

        self._validate_transition(crew.get("status"), CrewState.ACTIVE.value)

        crew["status"] = CrewState.ACTIVE.value
        crew["activated_at"] = datetime.now().isoformat()
        self._save_crew(crew_name, crew)

        logger.info(f"Crew activated: {crew_name}")
        return {
            "status": CrewState.ACTIVE.value,
            "crew": crew_name,
            "timestamp": crew["activated_at"]
        }

    async def mark_dormant(self, crew_name: str, reason: str = None) -> Dict:
        """
        Mark a crew as dormant (requires user acknowledgment).

        Args:
            crew_name: Crew name
            reason: Reason for dormancy

        Returns:
            Dormancy confirmation
        """
        logger.info(f"Marking crew {crew_name} as dormant")

        crew = self._load_crew(crew_name)
        if not crew:
            raise CrewNotFoundError(f"Crew not found: {crew_name}")

        self._validate_transition(crew.get("status"), CrewState.DORMANT.value)

        crew["status"] = CrewState.DORMANT.value
        crew["dormant_at"] = datetime.now().isoformat()
        crew["dormant_reason"] = reason

        # Export state before dormancy
        await self._export_crew_state(crew_name)

        # Save updated manifest
        self._save_crew(crew_name, crew)

        logger.info(f"Crew marked as dormant: {crew_name}")
        return {
            "status": CrewState.DORMANT.value,
            "crew": crew_name,
            "reason": reason,
            "timestamp": crew["dormant_at"]
        }

    async def complete_crew(self, crew_name: str) -> Dict:
        """
        Mark a crew as completed (mission accomplished).

        Args:
            crew_name: Crew name

        Returns:
            Completion confirmation
        """
        logger.info(f"Completing crew: {crew_name}")

        crew = self._load_crew(crew_name)
        if not crew:
            raise CrewNotFoundError(f"Crew not found: {crew_name}")

        self._validate_transition(crew.get("status"), CrewState.COMPLETED.value)

        crew["status"] = CrewState.COMPLETED.value
        crew["completed_at"] = datetime.now().isoformat()

        # Export final state
        await self._export_crew_state(crew_name)

        self._save_crew(crew_name, crew)

        logger.info(f"Crew completed: {crew_name}")
        return {
            "status": CrewState.COMPLETED.value,
            "crew": crew_name,
            "timestamp": crew["completed_at"]
        }

    async def reactivate(self, crew_name: str) -> Dict:
        """
        Reactivate a dormant crew with full state restoration.

        Args:
            crew_name: Crew name

        Returns:
            Reactivation confirmation
        """
        logger.info(f"Reactivating crew: {crew_name}")

        crew_dir = self.crews_dir / crew_name
        manifest_path = crew_dir / "crew.json"

        if not manifest_path.exists():
            raise CrewNotFoundError(
                f"Crew manifest not found: {crew_name}. Cannot reactivate non-existent crew."
            )

        crew = self._load_crew(crew_name)
        previous_status = crew.get("status", "unknown")

        # Reactivation is only valid from dormant state
        if previous_status != CrewState.DORMANT.value:
            raise InvalidStateTransitionError(
                f"Can only reactivate dormant crews. Current status: {previous_status}"
            )

        self._validate_transition(previous_status, CrewState.ACTIVE.value)

        # Restore state from backup
        restored = await self._restore_crew_state(crew_name)

        crew["status"] = CrewState.ACTIVE.value
        crew["reactivated_at"] = datetime.now().isoformat()
        crew["previous_status"] = previous_status

        # Merge restored state if any
        if restored:
            crew["state"] = {**(crew.get("state", {})), **restored}

        self._save_crew(crew_name, crew)

        logger.info(f"Crew reactivated: {crew_name} (from {previous_status})")
        return {
            "status": CrewState.ACTIVE.value,
            "crew": crew_name,
            "previous_status": previous_status,
            "reactivated_at": crew["reactivated_at"],
            "state_restored": bool(restored),
            "timestamp": crew["reactivated_at"]
        }

    async def archive_crew(self, crew_name: str) -> Dict:
        """
        Archive a crew (terminal state, preserves data).

        Args:
            crew_name: Crew name

        Returns:
            Archive confirmation
        """
        logger.info(f"Archiving crew: {crew_name}")

        crew = self._load_crew(crew_name)
        if not crew:
            raise CrewNotFoundError(f"Crew not found: {crew_name}")

        self._validate_transition(crew.get("status"), CrewState.ARCHIVED.value)

        crew["status"] = CrewState.ARCHIVED.value
        crew["archived_at"] = datetime.now().isoformat()

        self._save_crew(crew_name, crew)

        logger.info(f"Crew archived: {crew_name}")
        return {
            "status": CrewState.ARCHIVED.value,
            "crew": crew_name,
            "timestamp": crew["archived_at"]
        }

    async def delete(self, crew_name: str) -> Dict:
        """
        Delete a crew and all associated data.

        Args:
            crew_name: Crew name

        Returns:
            Deletion confirmation
        """
        logger.info(f"Deleting crew: {crew_name}")

        crew_dir = self.crews_dir / crew_name

        # Load crew data BEFORE deleting directory
        crew = self._load_crew(crew_name) if crew_dir.exists() else {}
        agent_ids = crew.get("agents", [])

        # Remove crew directory
        if crew_dir.exists():
            shutil.rmtree(crew_dir)

        # Clean up crew agent identities
        for agent_id in agent_ids:
            agent_dir = self.agents_dir / agent_id
            identity_path = agent_dir / "identity.json"
            if identity_path.exists():
                identity_path.unlink()
                logger.info(f"Removed identity for agent {agent_id}")

        logger.info(f"Crew deleted: {crew_name}")
        return {
            "status": "deleted",
            "crew": crew_name,
            "agents_cleaned": len(agent_ids),
            "timestamp": datetime.now().isoformat()
        }

    async def _export_crew_state(self, crew_name: str) -> Path:
        """
        Export crew state before lifecycle transition.

        Returns:
            Path to the state backup file
        """
        crew_dir = self.crews_dir / crew_name
        state_dir = crew_dir / "state"
        backup_dir = crew_dir / "backups"
        backup_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        state_file = backup_dir / f"state_{timestamp}.json"

        crew = self._load_crew(crew_name)

        # Capture full state: manifest, agent details, resources
        state = {
            "timestamp": datetime.now().isoformat(),
            "crew": crew_name,
            "manifest": crew,
            "agents": [],
            "resources": crew.get("resources", {}),
            "state": crew.get("state", {})
        }

        for agent_id in crew.get("agents", []):
            agent_dir = self.agents_dir / agent_id
            agent_state = {
                "id": agent_id,
                "exists": agent_dir.exists()
            }
            identity_path = agent_dir / "identity.json"
            if identity_path.exists():
                with open(identity_path, 'r') as f:
                    agent_state["identity"] = json.load(f)
            state["agents"].append(agent_state)

        with open(state_file, 'w') as f:
            json.dump(state, f, indent=2)

        logger.info(f"Crew state exported: {state_file}")
        return state_file

    async def _restore_crew_state(self, crew_name: str) -> Dict:
        """
        Restore crew state from the latest backup.

        Returns:
            Restored state dictionary, or empty dict if no backup found
        """
        crew_dir = self.crews_dir / crew_name
        backup_dir = crew_dir / "backups"

        if not backup_dir.exists():
            logger.info(f"No backup directory found for crew {crew_name}")
            return {}

        backups = list(backup_dir.glob("state_*.json"))
        if not backups:
            logger.info(f"No state backups found for crew {crew_name}")
            return {}

        latest = max(backups, key=lambda x: x.stat().st_mtime)
        logger.info(f"Restoring crew state from: {latest}")

        with open(latest, 'r') as f:
            backup_data = json.load(f)

        # Restore agent identities from backup
        for agent_state in backup_data.get("agents", []):
            if agent_state.get("exists") and "identity" in agent_state:
                agent_id = agent_state["id"]
                agent_dir = self.agents_dir / agent_id
                agent_dir.mkdir(parents=True, exist_ok=True)
                identity_path = agent_dir / "identity.json"
                with open(identity_path, 'w') as f:
                    json.dump(agent_state["identity"], f, indent=2)

        restored_state = {
            "manifest": backup_data.get("manifest", {}),
            "state": backup_data.get("state", {}),
            "resources": backup_data.get("resources", {}),
            "restored_at": datetime.now().isoformat(),
            "source_backup": latest.name
        }
        logger.info(f"Crew state restored with {len(backup_data.get('agents', []))} agents")
        return restored_state

    async def list_crews(self, status_filter: str = None) -> List[Dict]:
        """
        List all crews, optionally filtered by status.

        Args:
            status_filter: Optional status to filter by

        Returns:
            List of crew dictionaries
        """
        crews = []
        if not self.crews_dir.exists():
            return crews

        for crew_dir in self.crews_dir.iterdir():
            if crew_dir.is_dir():
                manifest_path = crew_dir / "crew.json"
                if manifest_path.exists():
                    with open(manifest_path, 'r') as f:
                        crew = json.load(f)
                        if status_filter is None or crew.get("status") == status_filter:
                            crews.append(crew)
        return crews

    async def get_crew_status(self, crew_name: str) -> Dict:
        """
        Get detailed crew status.

        Args:
            crew_name: Crew name

        Returns:
            Crew status dictionary

        Raises:
            CrewNotFoundError: If crew not found
        """
        crew = self._load_crew(crew_name)
        if not crew:
            raise CrewNotFoundError(f"Crew not found: {crew_name}")

        # Get backup count
        backup_dir = self.crews_dir / crew_name / "backups"
        backup_count = 0
        latest_backup = None
        if backup_dir.exists():
            backups = list(backup_dir.glob("state_*.json"))
            backup_count = len(backups)
            if backups:
                latest = max(backups, key=lambda x: x.stat().st_mtime)
                latest_backup = latest.name

        return {
            "name": crew.get("name", crew_name),
            "status": crew.get("status", "unknown"),
            "agents": crew.get("agents", []),
            "agent_count": len(crew.get("agents", [])),
            "created_at": crew.get("created_at"),
            "activated_at": crew.get("activated_at"),
            "dormant_at": crew.get("dormant_at"),
            "dormant_reason": crew.get("dormant_reason"),
            "completed_at": crew.get("completed_at"),
            "reactivated_at": crew.get("reactivated_at"),
            "archived_at": crew.get("archived_at"),
            "resources": crew.get("resources", {}),
            "state": crew.get("state", {}),
            "backups": backup_count,
            "latest_backup": latest_backup,
            "previous_status": crew.get("previous_status"),
            "version": crew.get("version", "1.0")
        }

    def get_valid_transitions(self, current_status: str) -> List[str]:
        """
        Get list of valid next states for a given status.

        Args:
            current_status: Current crew status

        Returns:
            List of valid target states
        """
        current = CrewState(current_status) if current_status else CrewState.CREATED
        allowed = VALID_TRANSITIONS.get(current, set())
        return sorted([s.value for s in allowed])

    async def update_crew_state(self, crew_name: str, state_data: Dict) -> Dict:
        """
        Update crew runtime state.

        Args:
            crew_name: Crew name
            state_data: State data to merge

        Returns:
            Updated state
        """
        crew = self._load_crew(crew_name)
        if not crew:
            raise CrewNotFoundError(f"Crew not found: {crew_name}")

        crew["state"] = {**(crew.get("state", {})), **state_data}
        crew["state_updated_at"] = datetime.now().isoformat()
        self._save_crew(crew_name, crew)

        return crew["state"]


async def main():
    """CLI entry point."""
    import sys

    manager = CrewLifecycleManager()

    if len(sys.argv) < 2:
        print("Usage: python -m crew.lifecycle [command] [args]")
        print("")
        print("Commands:")
        print("  create <name> <agent1,agent2,...>  - Create a new crew")
        print("  activate <name>                    - Activate a created crew")
        print("  complete <name>                    - Mark crew as completed")
        print("  dormant <name> [reason]            - Mark crew as dormant")
        print("  reactivate <name>                  - Reactivate a dormant crew")
        print("  archive <name>                     - Archive a crew (terminal)")
        print("  delete <name>                      - Delete crew and all data")
        print("  list [status]                      - List all crews (optionally filter by status)")
        print("  status <name>                      - Get detailed crew status")
        print("  transitions <status>               - Show valid transitions from a status")
        print("")
        sys.exit(1)

    command = sys.argv[1]

    if command == 'create':
        if len(sys.argv) < 4:
            print("Usage: create <name> <agent1,agent2,...>")
            sys.exit(1)
        name = sys.argv[2]
        agents = sys.argv[3].split(',')
        try:
            crew = await manager.create_crew(name, agents)
            print(f"✓ Crew created: {name}")
            print(f"  Agents: {', '.join(agents)}")
            print(f"  Status: {crew['status']}")
        except CrewLifecycleError as e:
            print(f"✗ Error: {e}")
            sys.exit(1)

    elif command == 'activate':
        if len(sys.argv) < 3:
            print("Usage: activate <name>")
            sys.exit(1)
        name = sys.argv[2]
        try:
            result = await manager.activate_crew(name)
            print(f"✓ Crew activated: {name}")
            print(f"  Timestamp: {result['timestamp']}")
        except (CrewNotFoundError, InvalidStateTransitionError) as e:
            print(f"✗ Error: {e}")
            sys.exit(1)

    elif command == 'complete':
        if len(sys.argv) < 3:
            print("Usage: complete <name>")
            sys.exit(1)
        name = sys.argv[2]
        try:
            result = await manager.complete_crew(name)
            print(f"✓ Crew completed: {name}")
            print(f"  Timestamp: {result['timestamp']}")
        except (CrewNotFoundError, InvalidStateTransitionError) as e:
            print(f"✗ Error: {e}")
            sys.exit(1)

    elif command == 'dormant':
        if len(sys.argv) < 3:
            print("Usage: dormant <name> [reason]")
            sys.exit(1)
        name = sys.argv[2]
        reason = sys.argv[3] if len(sys.argv) > 3 else "User requested"
        try:
            result = await manager.mark_dormant(name, reason)
            print(f"✓ Crew marked dormant: {name}")
            print(f"  Reason: {reason}")
            print(f"  Timestamp: {result['timestamp']}")
        except (CrewNotFoundError, InvalidStateTransitionError) as e:
            print(f"✗ Error: {e}")
            sys.exit(1)

    elif command == 'reactivate':
        if len(sys.argv) < 3:
            print("Usage: reactivate <name>")
            sys.exit(1)
        name = sys.argv[2]
        try:
            result = await manager.reactivate(name)
            print(f"✓ Crew reactivated: {name}")
            print(f"  From: {result['previous_status']}")
            print(f"  State restored: {result['state_restored']}")
            print(f"  Timestamp: {result['timestamp']}")
        except (CrewNotFoundError, InvalidStateTransitionError) as e:
            print(f"✗ Error: {e}")
            sys.exit(1)

    elif command == 'archive':
        if len(sys.argv) < 3:
            print("Usage: archive <name>")
            sys.exit(1)
        name = sys.argv[2]
        try:
            result = await manager.archive_crew(name)
            print(f"✓ Crew archived: {name}")
            print(f"  Timestamp: {result['timestamp']}")
        except (CrewNotFoundError, InvalidStateTransitionError) as e:
            print(f"✗ Error: {e}")
            sys.exit(1)

    elif command == 'delete':
        if len(sys.argv) < 3:
            print("Usage: delete <name>")
            sys.exit(1)
        name = sys.argv[2]
        try:
            result = await manager.delete(name)
            print(f"✓ Crew deleted: {name}")
            print(f"  Agents cleaned: {result['agents_cleaned']}")
        except Exception as e:
            print(f"✗ Error: {e}")
            sys.exit(1)

    elif command == 'list':
        status_filter = sys.argv[2] if len(sys.argv) > 2 else None
        crews = await manager.list_crews(status_filter)
        print(f"\n{'='*60}")
        print(f"Crews ({len(crews)} total)")
        print(f"{'='*60}\n")
        for crew in crews:
            status = crew.get("status", "unknown")
            symbol = {"active": "🟢", "dormant": "🟣", "completed": "🔵",
                      "archived": "⚫", "created": "⚪"}.get(status, "❓")
            print(f"  {symbol} {crew['name']} ({status})")
            print(f"     Agents: {', '.join(crew.get('agents', []))}")

    elif command == 'status':
        if len(sys.argv) < 3:
            print("Usage: status <name>")
            sys.exit(1)
        name = sys.argv[2]
        try:
            status = await manager.get_crew_status(name)
            print(f"\n{'='*60}")
            print(f"Crew Status: {status['name']}")
            print(f"{'='*60}")
            print(f"Status:       {status['status']}")
            print(f"Created:      {status['created_at']}")
            if status.get('activated_at'):
                print(f"Activated:    {status['activated_at']}")
            if status.get('completed_at'):
                print(f"Completed:    {status['completed_at']}")
            if status.get('dormant_at'):
                print(f"Dormant:      {status['dormant_at']}")
            if status.get('dormant_reason'):
                print(f"Reason:       {status['dormant_reason']}")
            if status.get('reactivated_at'):
                print(f"Reactivated:  {status['reactivated_at']}")
            if status.get('archived_at'):
                print(f"Archived:     {status['archived_at']}")
            if status.get('previous_status'):
                print(f"Previous:     {status['previous_status']}")
            print(f"Agents:       {', '.join(status['agents'])} ({status['agent_count']})")
            print(f"Backups:      {status['backups']}")
            if status['latest_backup']:
                print(f"Latest:       {status['latest_backup']}")
            print(f"State:        {json.dumps(status['state'], indent=2) if status['state'] else '{}'}")
        except CrewNotFoundError as e:
            print(f"✗ Error: {e}")
            sys.exit(1)

    elif command == 'transitions':
        status = sys.argv[2] if len(sys.argv) > 2 else ""
        transitions = manager.get_valid_transitions(status)
        print(f"Valid transitions from '{status or 'created'}':")
        for t in transitions:
            print(f"  → {t}")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    asyncio.run(main())