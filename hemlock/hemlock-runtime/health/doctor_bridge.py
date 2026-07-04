#!/usr/bin/env python3
"""
Doctor Bridge - Programmatic health check orchestration for Hemlock.

Integrates all health validators (paths, env, identity, gateway, imports,
adapters, orchestration, persistence) into a single check pipeline.

Provides both human-readable and JSON output suitable for:
  - OpenClaw pre-flight checks (hermes doctor bridge --json)
  - Docker HEALTHCHECK (hermes doctor bridge --quick)
  - Full diagnostic (hermes doctor bridge)
  - Auto-fix mode (hermes doctor bridge --fix)

Used by OpenClaw to verify the agent runtime before starting.
"""

import json
import os
import sys
import time
from pathlib import Path
from dataclasses import dataclass, asdict, field
from typing import List, Optional


@dataclass
class CheckResult:
    name: str
    status: str  # "ok", "warn", "fail"
    detail: str = ""
    path: str = ""
    category: str = ""


@dataclass
class DoctorReport:
    healthy: bool
    total_checks: int
    ok_count: int
    warn_count: int
    fail_count: int
    duration_ms: float
    results: List[CheckResult] = field(default_factory=list)


def _run_category(category: str, module_path: str, function_name: str,
                  fix: bool = False) -> List[CheckResult]:
    """Run a single validator module and collect results."""
    try:
        sys.path.insert(0, str(Path(__file__).parent.parent))
        parts = module_path.rsplit(".", 1)
        if len(parts) == 2:
            mod = __import__(parts[0], fromlist=[parts[1]])
            validator = getattr(mod, parts[1])
        else:
            mod = __import__(module_path)
            validator = mod

        check_fn = getattr(validator, function_name)
        raw_results = check_fn(fix=fix)

        results = []
        for r in raw_results:
            if isinstance(r, dict):
                results.append(CheckResult(
                    name=r.get("name", "unknown"),
                    status=r.get("status", "warn"),
                    detail=r.get("detail", ""),
                    path=r.get("path", ""),
                    category=category,
                ))
            elif hasattr(r, 'name'):
                r.category = category
                results.append(r)
            else:
                results.append(CheckResult(
                    name=str(r),
                    status="warn",
                    detail=str(r),
                    category=category,
                ))
        return results

    except ImportError as e:
        return [CheckResult(
            name=f"{category}_import",
            status="fail",
            detail=f"Cannot import {module_path}: {e}",
            category=category,
        )]
    except AttributeError as e:
        return [CheckResult(
            name=f"{category}_function",
            status="fail",
            detail=f"Cannot find {function_name} in {module_path}: {e}",
            category=category,
        )]
    except Exception as e:
        return [CheckResult(
            name=f"{category}_error",
            status="fail",
            detail=f"Unexpected error: {type(e).__name__}: {e}",
            category=category,
        )]


# Registry of all health validators
VALIDATORS = {
    "paths": ("health.paths.paths_validator", "run_path_checks"),
    "env": ("health.env.env_validator", "run_env_checks"),
    "identity": ("health.identity.identity_validator", "run_agent_identity_checks"),
    "gateway": ("health.gateway.gateway_validator", "run_gateway_checks"),
    "imports": ("health.imports.imports_validator", "test_imports"),
    "adapters": ("health.adapters.adapters_validator", "test_adapters"),
    "orchestration": ("health.orchestration.orchestration_validator", "test_orchestration"),
    "persistence": ("health.persistence.persistence_validator", "test_persistence"),
}

QUICK_CATEGORIES = ["paths", "env", "imports"]


def run_all_checks(
    categories: Optional[List[str]] = None,
    fix: bool = False,
    quick: bool = False,
) -> DoctorReport:
    """Run health checks and return a comprehensive report."""
    start = time.monotonic()

    if categories is None:
        categories = QUICK_CATEGORIES if quick else list(VALIDATORS.keys())

    all_results: List[CheckResult] = []
    for cat in categories:
        if cat not in VALIDATORS:
            all_results.append(CheckResult(
                name=f"unknown_category_{cat}",
                status="warn",
                detail=f"Unknown check category: {cat}",
                category=cat,
            ))
            continue

        module_path, function_name = VALIDATORS[cat]
        results = _run_category(cat, module_path, function_name, fix=fix)
        all_results.extend(results)

    duration_ms = (time.monotonic() - start) * 1000

    ok_count = sum(1 for r in all_results if r.status == "ok")
    warn_count = sum(1 for r in all_results if r.status == "warn")
    fail_count = sum(1 for r in all_results if r.status == "fail")

    return DoctorReport(
        healthy=fail_count == 0,
        total_checks=len(all_results),
        ok_count=ok_count,
        warn_count=warn_count,
        fail_count=fail_count,
        duration_ms=round(duration_ms, 1),
        results=all_results,
    )


def format_report(report: DoctorReport) -> str:
    """Format a DoctorReport as human-readable output."""
    lines = []
    status_icon = "\u2713" if report.healthy else "\u2717"
    lines.append(f"{'=' * 60}")
    lines.append(f"  Hemlock Health Check  {status_icon}")
    lines.append(f"  {report.ok_count} ok  {report.warn_count} warn  {report.fail_count} fail  ({report.duration_ms}ms)")
    lines.append(f"{'=' * 60}")

    current_category = ""
    for r in report.results:
        if r.category != current_category:
            current_category = r.category
            lines.append(f"\n  [{current_category.upper()}]")
        icon = {"ok": "\u2713", "warn": "\u26a0", "fail": "\u2717"}[r.status]
        lines.append(f"    {icon} {r.name}: {r.detail}")

    lines.append(f"\n{'=' * 60}")
    if report.healthy:
        lines.append("  HEALTHY - All critical checks passed")
    else:
        lines.append(f"  UNHEALTHY - {report.fail_count} critical issue(s)")
    lines.append(f"{'=' * 60}")
    return "\n".join(lines)


def main():
    """CLI entry point for doctor bridge."""
    import argparse

    parser = argparse.ArgumentParser(description="Hemlock Health Check Bridge")
    parser.add_argument("--json", action="store_true", help="Output JSON for automation")
    parser.add_argument("--fix", action="store_true", help="Auto-fix issues where possible")
    parser.add_argument("--quick", action="store_true", help="Run only essential checks (paths, env, imports)")
    parser.add_argument("--categories", nargs="+", help="Specific categories to check")
    parser.add_argument("--agent-id", help="Agent ID for identity checks")
    args = parser.parse_args()

    categories = args.categories
    report = run_all_checks(categories=categories, fix=args.fix, quick=args.quick)

    if args.json:
        print(json.dumps(asdict(report), indent=2, default=str))
    else:
        print(format_report(report))

    sys.exit(0 if report.healthy else 1)


if __name__ == "__main__":
    main()