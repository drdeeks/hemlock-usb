"""
Completion Approval - User Acknowledgment System

Provides:
- Request completion acknowledgment from user
- User options: Approve, Reject, Extend, Quit
- 24-hour timeout enforcement
- Rework request handling
- Export before dormancy
- Decision persistence
"""

import asyncio
import json
import logging
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Optional, List

from paths import resolver

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ApprovalTimeoutError(Exception):
    """Raised when approval request times out."""
    pass


class ApprovalCancelledError(Exception):
    """Raised when approval request is cancelled."""
    pass


class CompletionApproval:
    """
    Handles user approval workflow for project completion.
    Supports approve, reject, extend, and quit actions with
    persistent decision storage and timeout enforcement.
    """

    VALID_CHOICES = {'A', 'R', 'E', 'Q'}

    def __init__(self, agent_id: str, timeout_hours: int = 24, projects_dir: str = None):
        self.agent_id = agent_id
        self.projects_dir = Path(projects_dir) if projects_dir else resolver.projects_dir
        self.decisions_dir = self.projects_dir / "decisions"
        try:
            self.decisions_dir.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            logger.warning(f"Cannot create directory (permission denied): {self.decisions_dir}")

        # Approval state
        self.approved = False
        self.rejected = False
        self.extended = False
        self.rework_requested = False
        self.cancelled = False
        self.timeout_hours = timeout_hours
        self.created_at = datetime.now()
        self.decision: Optional[Dict] = None

        logger.info(f"Completion approval initialized for {self.agent_id}")

    @property
    def is_expired(self) -> bool:
        """Check if the approval request has expired."""
        return datetime.now() > self.created_at + timedelta(hours=self.timeout_hours)

    @property
    def time_remaining(self) -> timedelta:
        """Time remaining before timeout."""
        return max(
            timedelta(0),
            (self.created_at + timedelta(hours=self.timeout_hours)) - datetime.now()
        )

    def _check_timeout(self) -> None:
        """Raise ApprovalTimeoutError if request has expired."""
        if self.is_expired:
            raise ApprovalTimeoutError(
                f"Approval request expired after {self.timeout_hours} hours. "
                f"Deadline: {self.created_at + timedelta(hours=self.timeout_hours)}"
            )

    def _load_existing_decision(self, project_name: str) -> Optional[Dict]:
        """Load a previously saved decision for this project."""
        decision_file = self.decisions_dir / f"{project_name}.json"
        if decision_file.exists():
            with open(decision_file, 'r') as f:
                return json.load(f)
        return None

    def request_completion_acknowledgment(
        self,
        project_name: str,
        project_summary: str
    ) -> Dict:
        """
        Request completion acknowledgment from user.

        Args:
            project_name: Name of the project
            project_summary: Summary of completed work

        Returns:
            Dictionary with approval status and user response

        Raises:
            ApprovalTimeoutError: If request times out
            ApprovalCancelledError: If user quits
        """
        # Check for existing decision (resume scenario)
        existing = self._load_existing_decision(project_name)
        if existing and existing.get("decision") in ("approved", "rejected", "extended"):
            logger.info(f"Existing decision found for {project_name}: {existing['decision']}")
            self.decision = existing
            self._apply_decision(existing["decision"])
            return existing

        self._check_timeout()

        print("\n" + "=" * 60)
        print("PROJECT COMPLETION APPROVAL REQUEST")
        print("=" * 60)
        print(f"\nProject:  {project_name}")
        print(f"Agent:    {self.agent_id}")
        print(f"Deadline: {self.created_at + timedelta(hours=self.timeout_hours)}")
        print(f"Status:   Awaiting user decision")
        print(f"\nSummary:\n{project_summary}\n")

        while True:
            self._check_timeout()

            remaining = self.time_remaining
            hours, remainder = divmod(int(remaining.total_seconds()), 3600)
            minutes = remainder // 60
            print(f"\nTime remaining: {hours}h {minutes}m")
            print("\nOptions:")
            print("  [A] Approve - Project is complete, mark as dormant")
            print("  [R] Reject  - Project needs revision")
            print("  [E] Extend  - Extend deadline for more work")
            print("  [Q] Quit    - Exit without decision")

            try:
                choice = input("\nYour choice [A/R/E/Q]: ").strip().upper()
            except (EOFError, KeyboardInterrupt):
                print("\n\nInput interrupted. Cancelling.")
                return self._handle_quit(project_name)

            if choice not in self.VALID_CHOICES:
                print("Invalid choice. Please enter A, R, E, or Q.")
                continue

            if choice == 'A':
                return self._handle_approve(project_name)
            elif choice == 'R':
                return self._handle_reject(project_name)
            elif choice == 'E':
                return self._handle_extend(project_name)
            elif choice == 'Q':
                return self._handle_quit(project_name)

    def _handle_approve(self, project_name: str) -> Dict:
        self.approved = True
        self.decision = {
            "status": "approved",
            "project": project_name,
            "timestamp": datetime.now().isoformat(),
            "agent": self.agent_id,
            "time_remaining": str(self.time_remaining)
        }
        self._save_decision(project_name, "approved")
        print(f"\n✓ Project '{project_name}' approved for dormancy")
        return self.decision

    def _handle_reject(self, project_name: str) -> Dict:
        self.rejected = True
        self.rework_requested = True
        self._save_decision(project_name, "rejected")
        print(f"\n✗ Project '{project_name}' rejected - revision needed")

        try:
            rework_notes = input("Enter rework notes (or press Enter to skip): ").strip()
        except (EOFError, KeyboardInterrupt):
            rework_notes = ""

        self.decision = {
            "status": "rejected",
            "project": project_name,
            "rework_requested": True,
            "notes": rework_notes,
            "timestamp": datetime.now().isoformat(),
            "agent": self.agent_id
        }
        # Save again with notes
        self._save_decision(project_name, "rejected", notes=rework_notes)
        return self.decision

    def _handle_extend(self, project_name: str) -> Dict:
        self.extended = True
        self._save_decision(project_name, "extended")
        print(f"\n⏳ Project '{project_name}' deadline extended")

        try:
            extension_hours = input("Extension hours (default 24): ").strip()
            try:
                extension = int(extension_hours) if extension_hours else 24
            except ValueError:
                extension = 24
        except (EOFError, KeyboardInterrupt):
            extension = 24

        self.decision = {
            "status": "extended",
            "project": project_name,
            "extension_hours": extension,
            "new_deadline": (datetime.now() + timedelta(hours=extension)).isoformat(),
            "timestamp": datetime.now().isoformat(),
            "agent": self.agent_id
        }
        # Save with extension details
        self._save_decision(project_name, "extended", extension_hours=extension)
        print(f"  Extended by {extension} hours. New deadline: {self.decision['new_deadline']}")
        return self.decision

    def _handle_quit(self, project_name: str) -> Dict:
        self.cancelled = True
        self.decision = {
            "status": "cancelled",
            "project": project_name,
            "timestamp": datetime.now().isoformat(),
            "agent": self.agent_id
        }
        self._save_decision(project_name, "cancelled")
        print("\nDecision cancelled.")
        return self.decision

    def _apply_decision(self, decision: str) -> None:
        """Apply a loaded decision to internal state."""
        if decision == "approved":
            self.approved = True
        elif decision == "rejected":
            self.rejected = True
            self.rework_requested = True
        elif decision == "extended":
            self.extended = True
        elif decision == "cancelled":
            self.cancelled = True

    def _save_decision(self, project_name: str, decision: str,
                       notes: str = "", extension_hours: int = 0) -> None:
        """Save approval decision to file."""
        decision_file = self.decisions_dir / f"{project_name}.json"

        data = {
            "project": project_name,
            "decision": decision,
            "timestamp": datetime.now().isoformat(),
            "agent": self.agent_id,
            "timeout_hours": self.timeout_hours
        }

        if notes:
            data["notes"] = notes
        if extension_hours:
            data["extension_hours"] = extension_hours

        with open(decision_file, 'w') as f:
            json.dump(data, f, indent=2)

        logger.info(f"Decision saved: {decision_file} (decision={decision})")

    def get_decision(self, project_name: str) -> Optional[Dict]:
        """Retrieve a previously saved decision."""
        return self._load_existing_decision(project_name)

    def get_pending_projects(self) -> List[str]:
        """List all projects with no final decision."""
        pending = []
        if not self.decisions_dir.exists():
            return pending
        for f in self.decisions_dir.glob("*.json"):
            with open(f, 'r') as fh:
                data = json.load(fh)
                if data.get("decision") in (None, "cancelled"):
                    pending.append(data.get("project", f.stem))
        return pending


async def main():
    """CLI entry point."""
    import sys

    if len(sys.argv) < 3:
        print("Usage: python -m project.approval <agent_id> <project_name>")
        print("       python -m project.approval <agent_id> <project_name> --timeout <hours>")
        print("       python -m project.approval <agent_id> --pending")
        sys.exit(1)

    agent_id = sys.argv[1]

    # Check for pending projects listing
    if sys.argv[2] == "--pending":
        approver = CompletionApproval(agent_id)
        pending = approver.get_pending_projects()
        if pending:
            print(f"\nPending projects for {agent_id}:")
            for p in pending:
                print(f"  - {p}")
        else:
            print(f"\nNo pending projects for {agent_id}")
        sys.exit(0)

    project_name = sys.argv[2]

    # Parse optional timeout
    timeout_hours = 24
    if "--timeout" in sys.argv:
        try:
            idx = sys.argv.index("--timeout")
            timeout_hours = int(sys.argv[idx + 1])
        except (ValueError, IndexError):
            print("Invalid timeout value. Using default 24 hours.")

    approver = CompletionApproval(agent_id, timeout_hours=timeout_hours)

    # Check for existing decision
    existing = approver.get_decision(project_name)
    if existing and existing.get("decision") in ("approved", "rejected", "extended"):
        print(f"\nExisting decision for '{project_name}': {existing['decision']}")
        print(json.dumps(existing, indent=2))
        sys.exit(0)

    # Demo project summary
    project_summary = f"""
Completed Tasks:
  - Mission definition: ✓
  - Blueprint creation: ✓
  - Crew formation: ✓
  - Phase execution: ✓
  - Quality validation: ✓

All objectives met. Ready for dormant state.
"""

    try:
        result = approver.request_completion_acknowledgment(project_name, project_summary)
        print(json.dumps(result, indent=2))
    except ApprovalTimeoutError as e:
        print(f"\n✗ Approval request timed out: {e}")
        sys.exit(2)
    except ApprovalCancelledError:
        print("\nDecision cancelled by user.")
        sys.exit(0)


if __name__ == '__main__':
    asyncio.run(main())