"""
Plugin Manager CLI - Command Line Interface

Commands:
- toolkit: Inject mandatory toolkit (Tier 1)
- inject: Inject optional plugins (Tier 2)
- repair: Repair toolkit on existing agent
- list: List available plugins
"""

import asyncio
import click
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from plugins.plugin_manager import PluginManager, InjectionResult


@click.group()
def cli():
    """Plugin and Toolkit Management"""
    pass


@cli.command()
@click.option('--agent', required=True, help='Agent ID')
@click.option('--backup/--no-backup', default=True, help='Create backup before injection')
def toolkit(agent, backup):
    """Inject mandatory toolkit (enforce.sh, secret.sh, etc.)"""
    
    async def run():
        manager = PluginManager()
        
        click.echo(f"Injecting mandatory toolkit into {agent}...")
        
        result = await manager.inject_tier1_mandatory(agent)
        
        if result.success:
            click.echo(click.style("✓ Toolkit injected successfully", fg='green'))
            click.echo(f"  Injected: {', '.join(result.injected)}")
            if result.backup_path:
                click.echo(f"  Backup: {result.backup_path}")
        else:
            click.echo(click.style("⚠️  Toolkit injection failed", fg='yellow'))
            if result.warning:
                click.echo(result.warning)
            if result.backup_path:
                click.echo(f"  Backup available: {result.backup_path}")
            sys.exit(1)
            
    asyncio.run(run())


@cli.command()
@click.option('--agent', required=True, help='Agent ID')
@click.option('--force', is_flag=True, help='Force repair even if toolkit partially exists')
def repair(agent, force):
    """Repair toolkit on existing agent"""
    
    async def run():
        manager = PluginManager()
        
        click.echo(f"Repairing toolkit for {agent}...")
        
        result = await manager.inject_tier1_mandatory(agent)
        
        if result.success:
            click.echo(click.style("✓ Toolkit repaired successfully", fg='green'))
            click.echo(f"  Injected: {', '.join(result.injected)}")
        else:
            click.echo(click.style("⚠️  Toolkit repair failed", fg='yellow'))
            if result.warning:
                click.echo(result.warning)
            if result.missing_files:
                click.echo(f"  Missing: {', '.join(result.missing_files)}")
            sys.exit(1)
            
    asyncio.run(run())


@cli.command()
@click.option('--agent', required=True, help='Agent ID')
@click.option('--all', 'inject_all', is_flag=True, help='Inject all available plugins')
@click.option('--plugins', help='Specific plugins to inject (comma-separated)')
@click.option('--auto', is_flag=True, help='Auto mode (no prompt)')
def inject(agent, inject_all, plugins, auto):
    """Inject optional plugins"""
    
    async def run():
        manager = PluginManager()
        
        if inject_all:
            click.echo(f"Injecting all plugins into {agent}...")
            result = await manager.inject_tier2_optional(agent, auto=True)
        elif plugins:
            plugin_list = [p.strip() for p in plugins.split(',')]
            click.echo(f"Injecting plugins {plugin_list} into {agent}...")
            result = await manager.inject_tier2_optional(agent, plugins=plugin_list, auto=True)
        else:
            click.echo(f"Injecting plugins into {agent}...")
            result = await manager.inject_tier2_optional(agent, auto=auto)
            
        if result.success:
            if result.injected:
                click.echo(click.style("✓ Plugins injected successfully", fg='green'))
                click.echo(f"  Injected: {', '.join(result.injected)}")
            else:
                click.echo(click.style("○ Plugins skipped by user", fg='yellow'))
        else:
            click.echo(click.style("⚠️  Plugin injection failed", fg='yellow'))
            if result.warning:
                click.echo(result.warning)
                
    asyncio.run(run())


@cli.command()
@click.option('--available', is_flag=True, help='List available plugins')
@click.option('--installed', is_flag=True, help='List installed plugins for agent')
@click.option('--agent', help='Agent ID (for --installed)')
def list(available, installed, agent):
    """List available and installed plugins"""
    
    async def run():
        manager = PluginManager()
        
        show_available = available
        show_installed = installed
        
        # If no flags provided, show both available and installed (if agent given)
        if not show_available and not show_installed:
            show_available = True
            if agent:
                show_installed = True
        
        if show_available:
            click.echo("Available plugins:")
            plugins = await manager.discover_plugins()
            for plugin in plugins:
                click.echo(f"  • {plugin}")
            click.echo()
                
        if show_installed and agent:
            click.echo(f"Installed plugins for {agent}:")
            agent_skills = manager.agents_dir / agent / 'skills'
            if agent_skills.exists():
                installed_count = 0
                for skill_dir in agent_skills.iterdir():
                    if skill_dir.is_dir():
                        click.echo(f"  • {skill_dir.name}")
                        installed_count += 1
                if installed_count == 0:
                    click.echo("  (no plugins installed)")
            else:
                click.echo("  (no skills directory)")
        elif show_installed and not agent:
            click.echo("Error: --installed requires --agent <agent_id>")
            sys.exit(1)
            
    asyncio.run(run())


if __name__ == '__main__':
    cli()
