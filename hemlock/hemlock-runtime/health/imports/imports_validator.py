#!/usr/bin/env python3
"""
Import validator for Hermes/OpenClaw framework.
Checks that critical modules can be imported.
"""
import sys
import traceback
from dataclasses import dataclass
from typing import List


@dataclass
class CheckResult:
    name: str
    status: str
    detail: str = ""
    path: str = ""


def test_imports(fix=False) -> List[CheckResult]:
    """Test that we can import the core modules."""
    results = []
    
    try:
        # Try to import from the Hermes agent
        from gateway.config import load_gateway_config
        from gateway.session import SessionStore
        from gateway.hooks import HookRegistry
        from gateway.pairing import PairingStore
        from gateway.run import start_gateway
        from tools.process_registry import process_registry
        from gateway.config import Platform
        from gateway.session import SessionSource
        
        results.append(CheckResult("imports_gateway", "ok", "All Hermes gateway imports successful"))
        
        # Try to import OpenClaw runtime (if available)
        try:
            import openclaw_runtime
            results.append(CheckResult("imports_openclaw", "ok", "OpenClaw runtime import successful"))
        except ImportError:
            results.append(CheckResult("imports_openclaw", "warn", "OpenClaw runtime not available (expected in base image)"))
            
    except Exception as e:
        results.append(CheckResult("imports_error", "fail", f"Unexpected error: {type(e).__name__}: {e}"))
        traceback.print_exc()
    
    return results


if __name__ == "__main__":
    results = test_imports()
    all_ok = all(r.status != "fail" for r in results)
    sys.exit(0 if all_ok else 1)
