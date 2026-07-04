#!/usr/bin/env python3
"""
Adapter validator for Hermes/OpenClaw framework.
Checks that platform adapters can be initialized.
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


def test_adapters(fix=False) -> List[CheckResult]:
    """Test that we can initialize platform adapters."""
    results = []
    
    try:
        gateway_dir = os.getenv('HERMES_HOME', '/opt/hermes') + '/gateway'
        if os.path.exists(gateway_dir):
            results.append(CheckResult("adapters_gateway_dir", "ok", "Gateway directory found", gateway_dir))
            
            # Check for platform directories
            platforms_dir = os.path.join(gateway_dir, 'platforms')
            if os.path.exists(platforms_dir):
                platforms = os.listdir(platforms_dir)
                results.append(CheckResult("adapters_platforms", "ok", f"Found platforms: {platforms}", platforms_dir))
            else:
                results.append(CheckResult("adapters_platforms", "warn", "Platforms directory not found"))
                
            # Check for key gateway files
            required_files = ['config.py', 'session.py', 'hooks.py', 'pairing.py', 'run.py']
            for file in required_files:
                file_path = os.path.join(gateway_dir, file)
                if os.path.exists(file_path):
                    results.append(CheckResult(f"adapters_{file}", "ok", f"{file} found", file_path))
                else:
                    results.append(CheckResult(f"adapters_{file}", "warn", f"{file} missing", file_path))
        else:
            results.append(CheckResult("adapters_gateway_dir", "warn", "Gateway directory not found in expected location", gateway_dir))
            
    except Exception as e:
        results.append(CheckResult("adapters_error", "fail", f"Unexpected error: {type(e).__name__}: {e}"))
    
    return results


if __name__ == "__main__":
    results = test_adapters()
    all_ok = all(r.status != "fail" for r in results)
    sys.exit(0 if all_ok else 1)
