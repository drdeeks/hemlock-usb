"""
Autonomy Protocol - Decision Framework for Agent Autonomy Layers

Implements a 6-layer decision hierarchy that determines how tasks
should be handled based on their characteristics. Connects to the
Hermes reflection engine and logs decisions to memory for learning.

Layer 0: Project Manager - Strategic decisions, project oversight
Layer 1: Script - Deterministic, repeatable, code-based actions
Layer 2: Tool - Packaged capabilities with known interfaces
Layer 3: Skill - Methodologies and protocols for structured execution
Layer 4: Subagent - Fresh context for self-contained LLM tasks
Layer 5: Main Agent - Coordination, judgment, and final decisions
"""

import json
import logging
import os
from datetime import datetime
from enum import IntEnum
from pathlib import Path
from typing import Dict, List, Optional, Any

from paths import resolver

logger = logging.getLogger(__name__)


class AutonomyLayer(IntEnum):
    """Autonomy protocol decision layers, from most deterministic to most autonomous."""
    PM = 0
    SCRIPT = 1
    TOOL = 2
    SKILL = 3
    SUBAGENT = 4
    MAIN_AGENT = 5


LAYER_DESCRIPTIONS: Dict[int, str] = {
    AutonomyLayer.PM: "Project Manager - Strategic decisions, project oversight",
    AutonomyLayer.SCRIPT: "Script - Deterministic, repeatable, code-based actions",
    AutonomyLayer.TOOL: "Tool - Packaged capabilities with known interfaces",
    AutonomyLayer.SKILL: "Skill - Methodologies and protocols for structured execution",
    AutonomyLayer.SUBAGENT: "Subagent - Fresh context for self-contained LLM tasks",
    AutonomyLayer.MAIN_AGENT: "Main Agent - Coordination, judgment, and final decisions",
}

LAYER_AXIOMS: Dict[int, List[str]] = {
    AutonomyLayer.PM: [
        "PM coordinates the mission, not the execution",
        "Strategic decisions belong here",
        "Defer to lower layers when possible",
    ],
    AutonomyLayer.SCRIPT: [
        "That which can be deterministic OUGHT to be",
        "State belongs in files, not in your head",
        "Use a tool if one exists. Write a script if it doesn't",
    ],
    AutonomyLayer.TOOL: [
        "That which can be deterministic OUGHT to be",
        "State belongs in files, not in your head",
        "Use a tool if one exists. Write a script if it doesn't",
    ],
    AutonomyLayer.SKILL: [
        "Skills constrain emergence",
        "Skills are bridges, not crutches",
    ],
    AutonomyLayer.SUBAGENT: [
        "Fresh context beats exhausted context",
        "Subagents get full SOUL",
    ],
    AutonomyLayer.MAIN_AGENT: [
        "Main agent coordinates and decides",
    ],
}


class DecisionResult:
    """Result of an autonomy protocol decision."""

    def __init__(self, task: str, layer: AutonomyLayer, reason: str,
                 axioms: List[str], action: str, metadata: Optional[Dict] = None):
        self.task = task
        self.layer = layer
        self.layer_name = layer.name
        self.layer_value = int(layer)
        self.reason = reason
        self.axioms = axioms
        self.action = action
        self.metadata = metadata or {}
        self.timestamp = datetime.now().isoformat()

    def to_dict(self) -> Dict[str, Any]:
        return {
            'task': self.task,
            'layer': self.layer_value,
            'layer_name': self.layer_name,
            'reason': self.reason,
            'axioms': self.axioms,
            'action': self.action,
            'metadata': self.metadata,
            'timestamp': self.timestamp,
        }

    def __repr__(self) -> str:
        return f"DecisionResult(layer={self.layer_name}, task='{self.task}', action='{self.action}')"


class AutonomyProtocol:
    """
    Autonomy protocol decision framework.

    Evaluates tasks through a 6-layer hierarchy to determine the
    most appropriate level of autonomy for execution. Connects to
    the Hermes reflection engine and logs decisions to memory.
    """

    def __init__(self, memory_dir: Optional[str] = None,
                 reflection_engine: Optional[Any] = None):
        """
        Initialize the autonomy protocol.

        Args:
            memory_dir: Directory for persisting decision logs
            reflection_engine: Optional Hermes reflection engine instance
        """
        self.memory_dir = Path(memory_dir) if memory_dir else resolver.autonomy_memory_dir
        self.memory_dir.mkdir(parents=True, exist_ok=True)
        self.reflection_engine = reflection_engine
        self.decisions: List[DecisionResult] = []
        self.outcomes: Dict[str, str] = {}

        logger.info("Autonomy protocol initialized")

    def decide(self, task: str,
               is_deterministic: Optional[bool] = None,
               tool_exists: Optional[bool] = None,
               methodology_exists: Optional[bool] = None,
               needs_llm_judgment: Optional[bool] = None,
               is_self_contained: Optional[bool] = None,
               is_strategic: Optional[bool] = None,
               metadata: Optional[Dict] = None) -> DecisionResult:
        """
        Determine the appropriate autonomy layer for a task.

        Evaluates the task through each layer and returns the first
        matching decision. If no lower layer matches, falls back to
        Main Agent (Layer 5).

        Args:
            task: Task description
            is_deterministic: Whether the task is repeatable and deterministic
            tool_exists: Whether a packaged tool exists for this task
            methodology_exists: Whether a methodology/protocol exists
            needs_llm_judgment: Whether LLM judgment is required
            is_self_contained: Whether the task has a self-contained description
            is_strategic: Whether this is a strategic/project-level decision
            metadata: Additional context for the decision

        Returns:
            DecisionResult with the chosen layer, reason, axioms, and action
        """
        logger.info(f"Evaluating task: {task}")

        # Layer 0: Project Manager
        if is_strategic:
            result = DecisionResult(
                task=task,
                layer=AutonomyLayer.PM,
                reason="Strategic/project-level decision requires PM coordination",
                axioms=LAYER_AXIOMS[AutonomyLayer.PM],
                action="PM coordinates strategic decision",
                metadata=metadata,
            )
            self._record_decision(result)
            return result

        # Layer 1: Script
        if is_deterministic is True or is_deterministic is None:
            if is_deterministic is True:
                result = DecisionResult(
                    task=task,
                    layer=AutonomyLayer.SCRIPT,
                    reason="Task is deterministic and repeatable",
                    axioms=LAYER_AXIOMS[AutonomyLayer.SCRIPT],
                    action="Write or use a script",
                    metadata=metadata,
                )
                self._record_decision(result)
                return result

        # Layer 2: Tool
        if tool_exists is True:
            result = DecisionResult(
                task=task,
                layer=AutonomyLayer.TOOL,
                reason="A packaged tool exists for this task",
                axioms=LAYER_AXIOMS[AutonomyLayer.TOOL],
                action="Use the existing tool",
                metadata=metadata,
            )
            self._record_decision(result)
            return result

        # Layer 3: Skill
        if methodology_exists is True:
            result = DecisionResult(
                task=task,
                layer=AutonomyLayer.SKILL,
                reason="A methodology/protocol exists for this task",
                axioms=LAYER_AXIOMS[AutonomyLayer.SKILL],
                action="Apply the relevant skill/methodology",
                metadata=metadata,
            )
            self._record_decision(result)
            return result

        # Layer 4: Subagent
        if needs_llm_judgment is True:
            if is_self_contained is True or is_self_contained is None:
                result = DecisionResult(
                    task=task,
                    layer=AutonomyLayer.SUBAGENT,
                    reason="Requires LLM judgment with fresh context",
                    axioms=LAYER_AXIOMS[AutonomyLayer.SUBAGENT],
                    action="Spawn a subagent with full SOUL",
                    metadata=metadata,
                )
                self._record_decision(result)
                return result

        # Layer 5: Main Agent (fallback)
        result = DecisionResult(
            task=task,
            layer=AutonomyLayer.MAIN_AGENT,
            reason="No lower layer matched - main agent coordinates and decides",
            axioms=LAYER_AXIOMS[AutonomyLayer.MAIN_AGENT],
            action="Main agent handles directly",
            metadata=metadata,
        )
        self._record_decision(result)
        return result

    def decide_interactive(self, task: str) -> DecisionResult:
        """
        Interactive decision flow (mimics the bash autonomy.sh interface).

        Prompts the user with questions at each layer to determine
        the appropriate autonomy level.

        Args:
            task: Task description

        Returns:
            DecisionResult with the chosen layer
        """
        print(f"\n=== Autonomy Protocol Decision ===")
        print(f"Task: {task}")
        print()

        # Layer 1: Script
        done_before = input("1. Script - Has this been done before? [y/N] ").strip().lower()
        if done_before in ('y', 'yes'):
            print("  → Use existing script/tool")
            result = DecisionResult(
                task=task, layer=AutonomyLayer.SCRIPT,
                reason="Previously done - use existing script",
                axioms=LAYER_AXIOMS[AutonomyLayer.SCRIPT],
                action="Use existing script or tool",
            )
            self._record_decision(result)
            return result

        deterministic = input("  Is it deterministic? [y/N] ").strip().lower()
        if deterministic in ('y', 'yes'):
            print("  → Write a script (Layer 1)")
            result = DecisionResult(
                task=task, layer=AutonomyLayer.SCRIPT,
                reason="Task is deterministic",
                axioms=LAYER_AXIOMS[AutonomyLayer.SCRIPT],
                action="Write a script",
            )
            self._record_decision(result)
            return result

        # Layer 2: Tool
        print("2. Tool - Packaged capability")
        tool_exists = input("  Does a packaged tool exist? [y/N] ").strip().lower()
        if tool_exists in ('y', 'yes'):
            print("  → Use the tool (Layer 2)")
            result = DecisionResult(
                task=task, layer=AutonomyLayer.TOOL,
                reason="A packaged tool exists",
                axioms=LAYER_AXIOMS[AutonomyLayer.TOOL],
                action="Use existing tool",
            )
            self._record_decision(result)
            return result

        # Layer 3: Skill
        print("3. Skill - Methodology/protocol")
        methodology = input("  Is there a methodology? [y/N] ").strip().lower()
        if methodology in ('y', 'yes'):
            print("  → Use a skill (Layer 3)")
            result = DecisionResult(
                task=task, layer=AutonomyLayer.SKILL,
                reason="A methodology exists",
                axioms=LAYER_AXIOMS[AutonomyLayer.SKILL],
                action="Apply the skill/methodology",
            )
            self._record_decision(result)
            return result

        # Layer 4: Subagent
        print("4. Subagent - Fresh context")
        llm_judgment = input("  Needs LLM judgment? [y/N] ").strip().lower()
        if llm_judgment in ('y', 'yes'):
            self_contained = input("  Self-contained description possible? [y/N] ").strip().lower()
            if self_contained in ('y', 'yes'):
                print("  → Spawn subagent (Layer 4)")
                result = DecisionResult(
                    task=task, layer=AutonomyLayer.SUBAGENT,
                    reason="Requires LLM judgment with fresh context",
                    axioms=LAYER_AXIOMS[AutonomyLayer.SUBAGENT],
                    action="Spawn a subagent",
                )
                self._record_decision(result)
                return result

        # Layer 5: Main Agent
        print("5. Main Agent - Coordinate and decide")
        print("  → Main agent handles (Layer 5)")
        result = DecisionResult(
            task=task, layer=AutonomyLayer.MAIN_AGENT,
            reason="No lower layer matched",
            axioms=LAYER_AXIOMS[AutonomyLayer.MAIN_AGENT],
            action="Main agent handles directly",
        )
        self._record_decision(result)
        return result

    def record_outcome(self, task: str, outcome: str, notes: str = "") -> None:
        """
        Record the outcome of a decision for learning.

        Args:
            task: The original task description
            outcome: The outcome ('success', 'partial', 'failure', 'escalated')
            notes: Additional notes about what happened
        """
        self.outcomes[task] = outcome
        outcome_data = {
            'task': task,
            'outcome': outcome,
            'notes': notes,
            'timestamp': datetime.now().isoformat(),
        }

        outcome_file = self.memory_dir / f'outcome_{datetime.now().strftime("%Y%m%d_%H%M%S_%f")}.json'
        with open(outcome_file, 'w') as f:
            json.dump(outcome_data, f, indent=2)

        logger.info(f"Recorded outcome for '{task}': {outcome}")

        # Connect to reflection engine if available
        if self.reflection_engine is not None:
            try:
                self.reflection_engine.record_decision_outcome(task, outcome)
                logger.info("Outcome forwarded to reflection engine")
            except Exception as e:
                logger.warning(f"Failed to forward outcome to reflection engine: {e}")

    def get_decision_history(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Get recent decision history."""
        decisions = sorted(
            self.memory_dir.glob('decision_*.json'),
            key=lambda f: f.stat().st_mtime,
            reverse=True,
        )
        results = []
        for decision_file in decisions[:limit]:
            try:
                with open(decision_file) as f:
                    results.append(json.load(f))
            except (json.JSONDecodeError, IOError) as e:
                logger.warning(f"Failed to load decision {decision_file}: {e}")
        return results

    def get_layer_stats(self) -> Dict[str, int]:
        """Get statistics on decisions per layer."""
        stats = {layer.name: 0 for layer in AutonomyLayer}
        for decision_file in self.memory_dir.glob('decision_*.json'):
            try:
                with open(decision_file) as f:
                    data = json.load(f)
                layer_name = data.get('layer_name', 'UNKNOWN')
                if layer_name in stats:
                    stats[layer_name] += 1
            except (json.JSONDecodeError, IOError):
                continue
        return stats

    def connect_reflection_engine(self, engine: Any) -> None:
        """Connect to the Hermes reflection engine.

        Args:
            engine: Reflection engine instance with record_decision_outcome method
        """
        self.reflection_engine = engine
        logger.info("Connected to reflection engine")

    def _record_decision(self, result: DecisionResult) -> None:
        """Record a decision to memory for learning and audit."""
        self.decisions.append(result)

        decision_file = self.memory_dir / f'decision_{datetime.now().strftime("%Y%m%d_%H%M%S_%f")}.json'
        try:
            with open(decision_file, 'w') as f:
                json.dump(result.to_dict(), f, indent=2)
            logger.info(f"Decision recorded: Layer {result.layer_name} for '{result.task}'")
        except Exception as e:
            logger.error(f"Failed to record decision: {e}")


def main():
    """CLI entry point for autonomy protocol."""
    import sys

    if len(sys.argv) < 2:
        print("Usage: python -m autonomy.protocol <task> [--interactive]")
        print("")
        print("Modes:")
        print("  <task>              Evaluate task and determine autonomy layer")
        print("  --interactive <task>  Interactive decision flow")
        print("  --history            Show recent decision history")
        print("  --stats             Show decision statistics per layer")
        print("")
        print("Evaluation flags (for non-interactive mode):")
        print("  --deterministic      Task is deterministic/repeatable")
        print("  --tool-exists       A packaged tool exists")
        print("  --methodology       A methodology/protocol exists")
        print("  --llm-judgment      Requires LLM judgment")
        print("  --self-contained     Task is self-contained")
        print("  --strategic          Strategic/project-level decision")
        sys.exit(1)

    protocol = AutonomyProtocol()
    command = sys.argv[1]

    if command == '--history':
        history = protocol.get_decision_history()
        if not history:
            print("No decisions recorded yet.")
        else:
            print(f"\n{'='*60}")
            print(f"Decision History ({len(history)} recent)")
            print(f"{'='*60}\n")
            for d in history:
                print(f"  [{d['layer_name']}] {d['task']}")
                print(f"    Action: {d['action']}")
                print(f"    Time: {d['timestamp']}")
                print()

    elif command == '--stats':
        stats = protocol.get_layer_stats()
        print(f"\n{'='*60}")
        print("Decision Statistics by Layer")
        print(f"{'='*60}\n")
        total = sum(stats.values())
        for layer, count in stats.items():
            pct = (count / total * 100) if total > 0 else 0
            bar = '#' * int(pct / 5)
            print(f"  {layer:12s}: {count:4d} ({pct:5.1f}%) {bar}")
        print(f"\n  Total: {total}")

    elif command == '--interactive':
        if len(sys.argv) < 3:
            print("Error: Task description required for interactive mode")
            sys.exit(1)
        task = ' '.join(sys.argv[2:])
        result = protocol.decide_interactive(task)
        print(f"\nDecision: Layer {result.layer_value} ({result.layer_name})")
        print(f"Action: {result.action}")
        print(f"\nAxioms:")
        for axiom in result.axioms:
            print(f"  - {axiom}")

    else:
        task = ' '.join(sys.argv[1:])
        flags = {
            'is_deterministic': '--deterministic' in sys.argv,
            'tool_exists': '--tool-exists' in sys.argv,
            'methodology_exists': '--methodology' in sys.argv,
            'needs_llm_judgment': '--llm-judgment' in sys.argv,
            'is_self_contained': '--self-contained' in sys.argv,
            'is_strategic': '--strategic' in sys.argv,
        }

        # Only pass flags that were explicitly set
        decide_kwargs = {k: v for k, v in flags.items() if v}
        # If no flags set, let decide() use its default heuristic
        if not decide_kwargs:
            decide_kwargs = {
                'is_deterministic': None,
                'tool_exists': None,
                'methodology_exists': None,
                'needs_llm_judgment': None,
            }

        result = protocol.decide(task, **decide_kwargs)

        print(f"\n{'='*60}")
        print(f"Autonomy Protocol Decision")
        print(f"{'='*60}")
        print(f"Task:   {result.task}")
        print(f"Layer:  {result.layer_value} ({result.layer_name})")
        print(f"Reason: {result.reason}")
        print(f"Action: {result.action}")
        print(f"\nAxioms:")
        for axiom in result.axioms:
            print(f"  - {axiom}")


if __name__ == '__main__':
    main()