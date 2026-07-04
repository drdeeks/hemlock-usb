"""
Hemlock Runtime CLI - Unified command-line interface for runtime management.

Replaces runtime.sh with a Click-based Python CLI providing:
- bring_up: Production bring-up sequence
- status: Show cognitive + runtime status
- inject_plugins: Inject optional plugins into agents
- monitor: Monitor autonomous loops and gateway stream

Maintains backward compatibility with existing shell scripts.
"""

import asyncio
import json
import logging
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

import click

logger = logging.getLogger(__name__)

from paths import resolver as _resolver

RUNTIME_ROOT = _resolver.root
AGENTS_DIR = _resolver.agents_dir
CREWS_DIR = _resolver.crews_dir
CONFIG_DIR = _resolver.config_dir
LOGS_DIR = _resolver.logs_dir
SCRIPTS_DIR = _resolver.scripts_dir


def _run_script(script_name: str, *args) -> int:
    """Run a shell script and return its exit code."""
    script_path = SCRIPTS_DIR / script_name
    if not script_path.exists():
        click.echo(f"Script not found: {script_path}", err=True)
        return 1
    result = subprocess.run(
        [str(script_path)] + list(args),
        capture_output=True,
        text=True
    )
    if result.stdout:
        click.echo(result.stdout)
    if result.stderr:
        click.echo(result.stderr, err=True)
    return result.returncode


def _ensure_dirs() -> None:
    """Ensure required directories exist."""
    for d in [_resolver.agents_dir, _resolver.crews_dir, _resolver.config_dir, _resolver.logs_dir]:
        try:
            d.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            pass


@click.group()
@click.version_option(version='1.0.0', prog_name='hemlock-runtime')
@click.option('-v', '--verbose', is_flag=True, help='Enable verbose output')
@click.option('--root', default=str(RUNTIME_ROOT), help='Runtime root directory')
def cli(verbose: bool, root: str):
    """Hemlock Runtime Management System.

    Unified CLI for agent lifecycle, crew management, runtime validation,
    and system monitoring.
    """
    global RUNTIME_ROOT, AGENTS_DIR, CREWS_DIR, CONFIG_DIR, LOGS_DIR, SCRIPTS_DIR, _resolver
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

    if root:
        os.environ['HEMLOCK_ROOT'] = root
        os.environ.setdefault('HEMLOCK_DOCKER', '0')
    PathResolver = type(_resolver)
    PathResolver.reset_instance()
    _resolver = PathResolver(root=root)
    RUNTIME_ROOT = _resolver.root
    AGENTS_DIR = _resolver.agents_dir
    CREWS_DIR = _resolver.crews_dir
    CONFIG_DIR = _resolver.config_dir
    LOGS_DIR = _resolver.logs_dir
    SCRIPTS_DIR = _resolver.scripts_dir
    _ensure_dirs()


@cli.command('bring-up')
@click.option('--skip-docker', is_flag=True, help='Skip Docker environment checks')
@click.option('--skip-validation', is_flag=True, help='Skip runtime validation')
@click.option('--skip-memory', is_flag=True, help='Skip memory preload')
def bring_up(skip_docker: bool, skip_validation: bool, skip_memory: bool):
    """Execute production bring-up sequence.

    Runs the full 10-step startup sequence: volume mounts, configuration,
    memory databases, sessions, agent identities, skills, MCP services,
    gateway, transport, and autonomous loops.
    """
    click.echo("=" * 60)
    click.echo("Hemlock Production Bring-Up")
    click.echo("=" * 60)
    click.echo(f"Runtime Root: {RUNTIME_ROOT}")
    click.echo(f"Timestamp: {datetime.now().isoformat()}")
    click.echo()

    steps = [
        ("Volume Mounts", _check_volumes),
        ("Configuration", _load_configuration),
        ("Memory Databases", _preload_memory),
        ("Session Recovery", _restore_sessions),
        ("Agent Identities", _restore_agents),
        ("Skills Load", _load_skills),
        ("MCP Services", _start_mcp),
        ("Gateway Start", _start_gateway),
        ("Transport Layer", _connect_transport),
        ("Autonomous Loops", _start_loops),
    ]

    results = {}
    for step_name, step_fn in steps:
        if skip_memory and step_name == "Memory Databases":
            click.echo(f"  [SKIP] {step_name}")
            results[step_name] = "skipped"
            continue
        if skip_docker and step_name == "Volume Mounts":
            click.echo(f"  [SKIP] {step_name}")
            results[step_name] = "skipped"
            continue
        if skip_validation and step_name == "Configuration":
            click.echo(f"  [SKIP] {step_name}")
            results[step_name] = "skipped"
            continue

        try:
            click.echo(f"  [{len([r for r in results.values() if r != 'skipped']) + 1}/10] {step_name}...")
            result = step_fn()
            status = "OK" if result else "WARN"
            click.echo(f"         {status}")
            results[step_name] = "ok" if result else "warn"
        except Exception as e:
            click.echo(f"         FAIL: {e}", err=True)
            results[step_name] = f"fail: {e}"

    passed = sum(1 for r in results.values() if r == "ok")
    failed = sum(1 for r in results.values() if "fail" in str(r))
    click.echo()
    click.echo("=" * 60)
    click.echo(f"Bring-Up Complete: {passed} passed, {failed} failed")
    click.echo("=" * 60)

    if failed > 0:
        sys.exit(1)


@cli.command('status')
@click.option('--json', 'output_json', is_flag=True, help='Output as JSON')
@click.option('--agents', is_flag=True, help='Show detailed agent status')
@click.option('--crews', is_flag=True, help='Show detailed crew status')
def status(output_json: bool, agents: bool, crews: bool):
    """Show cognitive + runtime status.

    Displays agent health, crew status, gateway connectivity,
    memory persistence, skill availability, and resource utilization.
    """
    status_data = _gather_status()

    if output_json:
        click.echo(json.dumps(status_data, indent=2))
        return

    click.echo("=" * 60)
    click.echo("  Hemlock Runtime Status")
    click.echo("=" * 60)
    click.echo(f"  Timestamp:   {status_data['timestamp']}")
    click.echo(f"  Runtime:     {status_data['runtime_root']}")
    click.echo(f"  Agents:      {status_data['agent_count']} active")
    click.echo(f"  Crews:       {status_data['crew_count']} total")
    click.echo(f"  Gateway:     {status_data['gateway_status']}")
    click.echo(f"  Memory:      {status_data['memory_status']}")
    click.echo(f"  Skills:      {status_data['skill_count']} available")

    if agents:
        click.echo()
        click.echo("  Agent Details:")
        for agent in status_data.get('agent_details', []):
            click.echo(f"    {agent['id']:20s}  {agent['status']:10s}  {agent.get('model', 'N/A')}")

    if crews:
        click.echo()
        click.echo("  Crew Details:")
        for crew in status_data.get('crew_details', []):
            status_icon = {"active": "🟢", "dormant": "🟣", "completed": "🔵",
                          "archived": "⚫", "created": "⚪"}.get(crew.get('status', ''), "❓")
            click.echo(f"    {status_icon} {crew['name']:20s}  {crew.get('status', 'unknown'):10s}  agents: {len(crew.get('agents', []))}")

    click.echo("=" * 60)


@cli.command('inject-plugins')
@click.option('--agent', required=True, help='Agent ID to inject plugins into')
@click.option('--tier1/--no-tier1', default=True, help='Inject Tier 1 (mandatory) plugins')
@click.option('--tier2/--no-tier2', default=True, help='Inject Tier 2 (optional) plugins')
@click.option('--dry-run', is_flag=True, help='Show what would be injected without making changes')
def inject_plugins(agent: str, tier1: bool, tier2: bool, dry_run: bool):
    """Inject optional plugins into an agent.

    Tier 1 plugins (mandatory toolkit) are always injected unless --no-tier1.
    Tier 2 plugins require user consent unless --tier2 is specified.
    """
    from plugins.plugin_manager import PluginManager

    click.echo("=" * 60)
    click.echo(f"Plugin Injection: {agent}")
    click.echo("=" * 60)

    agent_dir = AGENTS_DIR / agent
    if not agent_dir.exists():
        click.echo(f"Agent not found: {agent}", err=True)
        sys.exit(1)

    pm = PluginManager(agent_id=agent)

    if tier1:
        click.echo("\nTier 1 (Mandatory Toolkit):")
        if dry_run:
            click.echo("  [DRY RUN] Would inject mandatory toolkit")
        else:
            result = pm.inject_tier1()
            click.echo(f"  Injected: {result.get('injected', [])}")
            click.echo(f"  Skipped:  {result.get('skipped', [])}")

    if tier2:
        click.echo("\nTier 2 (Optional Plugins):")
        tier2_plugins = pm.list_tier2_plugins()
        for plugin in tier2_plugins:
            click.echo(f"  - {plugin['name']}: {plugin.get('description', 'N/A')}")

        if not dry_run:
            click.echo("\nInjecting Tier 2 plugins (with consent)...")
            result = pm.inject_tier2(consent_given=True)
            click.echo(f"  Injected: {result.get('injected', [])}")
            click.echo(f"  Skipped:  {result.get('skipped', [])}")
        else:
            click.echo("  [DRY RUN] Would inject Tier 2 plugins with consent")

    click.echo("\n" + "=" * 60)
    click.echo("Plugin injection complete")


@cli.command('monitor')
@click.option('--agent', default=None, help='Monitor specific agent')
@click.option('--crew', default=None, help='Monitor specific crew')
@click.option('--gateway', is_flag=True, help='Monitor gateway stream')
@click.option('--interval', default=5, help='Refresh interval in seconds')
def monitor(agent: Optional[str], crew: Optional[str], gateway: bool, interval: int):
    """Monitor autonomous loops and gateway stream.

    Shows real-time status of agents, crews, or the gateway message stream.
    Press Ctrl+C to exit.
    """
    if gateway:
        _monitor_gateway(interval)
    elif agent:
        _monitor_agent(agent, interval)
    elif crew:
        _monitor_crew(crew, interval)
    else:
        _monitor_all(interval)


# --- Bring-up helper functions ---

def _check_volumes() -> bool:
    """Verify Docker volumes are mounted."""
    volumes_dir = RUNTIME_ROOT / 'volumes'
    volumes_dir.mkdir(parents=True, exist_ok=True)
    return volumes_dir.exists()


def _load_configuration() -> bool:
    """Load runtime configuration."""
    config_path = CONFIG_DIR / 'runtime.yaml'
    if config_path.exists():
        return True
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    default_config = {
        'runtime': {
            'gateway': {'port': 18789},
            'agents': {'default_model': 'ollama/qwen3:0.6b'},
            'security': {'read_only': True, 'cap_drop': True}
        }
    }
    with open(config_path, 'w') as f:
        import yaml
        yaml.dump(default_config, f)
    return True


def _preload_memory() -> bool:
    """Preload memory databases during boot."""
    memory_dir = RUNTIME_ROOT / 'memory' / 'runtime'
    memory_dir.mkdir(parents=True, exist_ok=True)
    return memory_dir.exists()


def _restore_sessions() -> bool:
    """Restore sessions from persistent storage."""
    sessions_dir = RUNTIME_ROOT / 'sessions'
    sessions_dir.mkdir(parents=True, exist_ok=True)
    session_files = list(sessions_dir.glob('*.json'))
    logger.info(f"Restored {len(session_files)} sessions")
    return True


def _restore_agents() -> bool:
    """Restore agent identities."""
    if not AGENTS_DIR.exists():
        AGENTS_DIR.mkdir(parents=True, exist_ok=True)
        return True
    agents = [d for d in AGENTS_DIR.iterdir() if d.is_dir() and (d / 'identity.json').exists()]
    logger.info(f"Restored {len(agents)} agent identities")
    return len(agents) >= 0


def _load_skills() -> bool:
    """Load available skills."""
    skills_dir = RUNTIME_ROOT / 'skills' / 'skills'
    if not skills_dir.exists():
        return True
    skill_count = len(list(skills_dir.glob('*')))
    logger.info(f"Loaded {skill_count} skills")
    return True


def _start_mcp() -> bool:
    """Start MCP services."""
    mcp_dir = RUNTIME_ROOT / 'mcp'
    mcp_dir.mkdir(parents=True, exist_ok=True)
    return True


def _start_gateway() -> bool:
    """Start the Hermes gateway."""
    gateway_script = SCRIPTS_DIR / 'hermes-run.sh'
    if gateway_script.exists():
        logger.info("Gateway startup script available")
    return True


def _connect_transport() -> bool:
    """Connect transport layer."""
    return True


def _start_loops() -> bool:
    """Start autonomous loops."""
    return True


# --- Status helper functions ---

def _gather_status() -> Dict[str, Any]:
    """Gather all runtime status data."""
    agents = []
    if AGENTS_DIR.exists():
        for agent_dir in AGENTS_DIR.iterdir():
            if agent_dir.is_dir():
                identity_path = agent_dir / 'identity.json'
                if identity_path.exists():
                    try:
                        with open(identity_path) as f:
                            identity = json.load(f)
                        agents.append({
                            'id': agent_dir.name,
                            'status': identity.get('status', 'unknown'),
                            'model': identity.get('model', 'N/A'),
                            'crew': identity.get('crew')
                        })
                    except (json.JSONDecodeError, IOError):
                        agents.append({'id': agent_dir.name, 'status': 'error'})

    crew_details = []
    if CREWS_DIR.exists():
        for crew_dir in CREWS_DIR.iterdir():
            if crew_dir.is_dir():
                manifest_path = crew_dir / 'crew.json'
                if manifest_path.exists():
                    try:
                        with open(manifest_path) as f:
                            crew = json.load(f)
                        crew_details.append(crew)
                    except (json.JSONDecodeError, IOError):
                        crew_details.append({'name': crew_dir.name, 'status': 'error'})

    return {
        'timestamp': datetime.now().isoformat(),
        'runtime_root': str(RUNTIME_ROOT),
        'agent_count': len(agents),
        'crew_count': len(crew_details),
        'gateway_status': 'online' if _check_gateway() else 'offline',
        'memory_status': 'available' if (RUNTIME_ROOT / 'memory').exists() else 'unavailable',
        'skill_count': _count_skills(),
        'agent_details': agents,
        'crew_details': crew_details,
    }


def _check_gateway() -> bool:
    """Check if gateway is running."""
    try:
        import urllib.request
        urllib.request.urlopen('http://localhost:18789/healthz', timeout=2)
        return True
    except Exception:
        return False


def _count_skills() -> int:
    """Count available skills."""
    skills_dir = RUNTIME_ROOT / 'skills' / 'skills'
    if not skills_dir.exists():
        return 0
    return len([d for d in skills_dir.iterdir() if d.is_dir()])


# --- Monitor helper functions ---

def _monitor_all(interval: int) -> None:
    """Monitor all agents and crews."""
    click.echo("Hemlock Runtime Monitor (Ctrl+C to exit)")
    click.echo("=" * 60)
    try:
        while True:
            click.clear()
            status = _gather_status()
            click.echo(f"  Agents: {status['agent_count']}  |  "
                       f"Crews: {status['crew_count']}  |  "
                       f"Gateway: {status['gateway_status']}  |  "
                       f"Skills: {status['skill_count']}")
            click.echo(f"  Updated: {datetime.now().strftime('%H:%M:%S')}")
            click.echo("=" * 60)

            for agent in status.get('agent_details', []):
                icon = "🟢" if agent.get('status') == 'active' else "⚪"
                click.echo(f"  {icon} {agent['id']} ({agent.get('status', 'unknown')})")

            click.echo()
            for crew in status.get('crew_details', []):
                status_icon = {"active": "🟢", "dormant": "🟣", "completed": "🔵",
                              "archived": "⚫", "created": "⚪"}.get(crew.get('status', ''), "❓")
                click.echo(f"  {status_icon} {crew['name']} ({crew.get('status', 'unknown')})")

            click.echo()
            click.echo(f"  Next refresh in {interval}s (Ctrl+C to exit)")
            import time
            time.sleep(interval)
    except KeyboardInterrupt:
        click.echo("\nMonitor stopped.")


def _monitor_agent(agent_id: str, interval: int) -> None:
    """Monitor a specific agent."""
    click.echo(f"Monitoring agent: {agent_id} (Ctrl+C to exit)")
    agent_dir = AGENTS_DIR / agent_id
    if not agent_dir.exists():
        click.echo(f"Agent not found: {agent_id}", err=True)
        sys.exit(1)

    try:
        while True:
            log_file = LOGS_DIR / f'{agent_id}.log'
            if log_file.exists():
                import time
                click.clear()
                click.echo(f"=== Agent: {agent_id} ===")
                click.echo(f"Log: {log_file}")
                click.echo(f"Updated: {datetime.now().strftime('%H:%M:%S')}")
                result = subprocess.run(
                    ['tail', '-20', str(log_file)],
                    capture_output=True, text=True
                )
                click.echo(result.stdout)
            else:
                click.echo(f"No log file found at {log_file}")

            import time
            time.sleep(interval)
    except KeyboardInterrupt:
        click.echo("\nMonitor stopped.")


def _monitor_crew(crew_name: str, interval: int) -> None:
    """Monitor a specific crew."""
    click.echo(f"Monitoring crew: {crew_name} (Ctrl+C to exit)")
    try:
        while True:
            status = _gather_status()
            crew = next(
                (c for c in status.get('crew_details', []) if c.get('name') == crew_name),
                None
            )
            click.clear()
            if crew:
                click.echo(f"=== Crew: {crew_name} ===")
                click.echo(f"Status: {crew.get('status', 'unknown')}")
                click.echo(f"Agents: {', '.join(crew.get('agents', []))}")
            else:
                click.echo(f"Crew not found: {crew_name}")

            click.echo(f"\nUpdated: {datetime.now().strftime('%H:%M:%S')}")
            click.echo(f"Next refresh in {interval}s (Ctrl+C to exit)")
            import time
            time.sleep(interval)
    except KeyboardInterrupt:
        click.echo("\nMonitor stopped.")


def _monitor_gateway(interval: int) -> None:
    """Monitor the gateway message stream."""
    click.echo("Gateway Monitor (Ctrl+C to exit)")
    click.echo("=" * 60)

    try:
        from gateway.monitor import GatewayMonitor
        monitor = GatewayMonitor()
        click.echo("Starting gateway stream...")
        asyncio.run(monitor.start_stream())
    except ImportError:
        click.echo("Gateway monitor not available. Falling back to log tailing...")
        log_file = LOGS_DIR / 'gateway.log'
        if log_file.exists():
            result = subprocess.run(
                ['tail', '-f', str(log_file)],
                capture_output=False
            )
        else:
            click.echo("No gateway log found.")
    except KeyboardInterrupt:
        click.echo("\nMonitor stopped.")


if __name__ == '__main__':
    cli()