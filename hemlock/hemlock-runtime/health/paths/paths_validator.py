#!/usr/bin/env python3
"""
Path resolution validator for Hemlock health checks.

Verifies that PathResolver resolves all paths correctly, directories
are writable, and environment overrides work as expected.
"""

import os
import sys
import json
import tempfile
from pathlib import Path
from dataclasses import dataclass, field, asdict
from typing import List


@dataclass
class CheckResult:
    name: str
    status: str  # "ok", "warn", "fail"
    detail: str = ""
    path: str = ""


def run_path_checks(fix: bool = False) -> List[CheckResult]:
    results: List[CheckResult] = []

    try:
        from paths import resolver, PathResolver
    except ImportError as e:
        results.append(CheckResult("paths_import", "fail", f"Cannot import PathResolver: {e}"))
        return results

    results.append(CheckResult("paths_import", "ok", "PathResolver imported successfully"))

    p = resolver

    core_paths = {
        "root": p.root,
        "hermes_home": p.hermes_home,
        "agents_dir": p.agents_dir,
        "crews_dir": p.crews_dir,
        "projects_dir": p.projects_dir,
        "skills_root": p.skills_root,
        "logs_dir": p.logs_dir,
        "memory_dir": p.memory_dir,
        "plugins_dir": p.plugins_dir,
        "backups_dir": p.backups_dir,
        "config_dir": p.config_dir,
        "scripts_dir": p.scripts_dir,
        "models_dir": p.models_dir,
    }

    for name, path in core_paths.items():
        resolved = str(path)
        results.append(CheckResult(
            f"path_{name}", "ok",
            f"Resolved: {resolved}",
            resolved
        ))
        if not path.exists():
            if fix:
                try:
                    path.mkdir(parents=True, exist_ok=True)
                    results.append(CheckResult(
                        f"path_{name}_dir", "ok",
                        f"Created: {resolved}",
                        resolved
                    ))
                except PermissionError:
                    results.append(CheckResult(
                        f"path_{name}_dir", "fail",
                        f"Permission denied creating: {resolved}",
                        resolved
                    ))
            else:
                results.append(CheckResult(
                    f"path_{name}_dir", "warn",
                    f"Does not exist: {resolved}",
                    resolved
                ))

    write_test_dirs = ["hermes_home", "agents_dir", "crews_dir", "logs_dir", "config_dir"]
    for name in write_test_dirs:
        path = core_paths.get(name)
        if not path or not path.exists():
            continue
        try:
            test_file = path / ".health_write_test"
            test_file.write_text("ok")
            test_file.unlink()
            results.append(CheckResult(f"write_{name}", "ok", f"Writable: {path}"))
        except PermissionError:
            results.append(CheckResult(f"write_{name}", "fail", f"Not writable: {path}"))
        except OSError as e:
            results.append(CheckResult(f"write_{name}", "warn", f"Write test error: {e}"))

    docker_env = os.getenv("HEMLOCK_DOCKER", "").lower()
    if docker_env in ("1", "true", "yes"):
        if p.is_docker:
            results.append(CheckResult("docker_detection", "ok", "Docker environment detected correctly"))
        else:
            results.append(CheckResult("docker_detection", "fail",
                         f"HEMLOCK_DOCKER={docker_env} but is_docker=False"))
    elif docker_env in ("0", "false", "no"):
        if not p.is_docker:
            results.append(CheckResult("docker_detection", "ok", "Non-Docker environment detected correctly"))
        else:
            results.append(CheckResult("docker_detection", "warn",
                         f"HEMLOCK_DOCKER={docker_env} but is_docker=True"))
    else:
        results.append(CheckResult("docker_detection", "ok",
                     f"Auto-detected docker={p.is_docker}"))

    test_root = tempfile.mkdtemp(prefix="hemlock_path_test_")
    try:
        custom = PathResolver(root=test_root)
        if str(custom.root) != test_root:
            results.append(CheckResult("path_override", "fail",
                         f"Root override failed: expected {test_root}, got {custom.root}"))
        else:
            results.append(CheckResult("path_override", "ok", f"Root override works: {test_root}"))
    except Exception as e:
        results.append(CheckResult("path_override", "fail", f"PathResolver override failed: {e}"))
    finally:
        PathResolver.reset_instance()
        try:
            import shutil
            shutil.rmtree(test_root, ignore_errors=True)
        except Exception:
            pass

    path_dict = p.to_dict()
    if not isinstance(path_dict, dict) or "root" not in path_dict:
        results.append(CheckResult("path_dict", "fail", "to_dict() returned invalid structure"))
    else:
        results.append(CheckResult("path_dict", "ok", f"to_dict() returned {len(path_dict)} paths"))

    return results


def main():
    fix = "--fix" in sys.argv
    results = run_path_checks(fix=fix)

    if "--json" in sys.argv:
        print(json.dumps([asdict(r) for r in results], indent=2))
    else:
        for r in results:
            icon = {"ok": "\u2713", "warn": "\u26a0", "fail": "\u2717"}[r.status]
            line = f"  {icon} {r.name}: {r.detail}"
            if r.path and r.path != r.detail:
                line += f"  [{r.path}]"
            print(line)

    failed = sum(1 for r in results if r.status == "fail")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()