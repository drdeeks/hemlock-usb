#!/usr/bin/env python3
"""
Orchestration validator for Hermes/OpenClaw framework.
Checks that orchestration components are available.
"""
import sys
import os
from dataclasses import dataclass
from typing import List


@dataclass
class CheckResult:
    name: str
    status: str
    detail: str = ""
    path: str = ""


def test_orchestration(fix=False) -> List[CheckResult]:
    """Test that we can access orchestration components."""
    results = []
    
    try:
        # Check for process registry
        from tools.process_registry import process_registry
        results.append(CheckResult("orchestration_process_registry", "ok", "Process registry accessible"))
        
        # Check for skill manager (if exists)
        hermes_root = os.getenv('HERMES_HOME', '/opt/hermes')
        skill_manager_path = f'{hermes_root}/tools/skill_manager_tool.py'
        if os.path.exists(skill_manager_path):
            results.append(CheckResult("orchestration_skill_manager", "ok", "Skill manager tool found", skill_manager_path))
        else:
            results.append(CheckResult("orchestration_skill_manager", "warn", "Skill manager tool not found", skill_manager_path))
            
        # Check for MCP files
        mcp_file = f'{hermes_root}/agent_brain_mcp.py'
        if os.path.exists(mcp_file):
            results.append(CheckResult("orchestration_mcp_brain", "ok", "MCP brain file found", mcp_file))
        else:
            results.append(CheckResult("orchestration_mcp_brain", "warn", "MCP brain file not found", mcp_file))
            
    except ImportError as e:
        results.append(CheckResult("orchestration_import_error", "fail", f"Import error: {e}"))
    except Exception as e:
        results.append(CheckResult("orchestration_error", "fail", f"Unexpected error: {type(e).__name__}: {e}"))
    
    return results


if __name__ == "__main__":
    results = test_orchestration()
    all_ok = all(r.status != "fail" for r in results)
    sys.exit(0 if all_ok else 1)
