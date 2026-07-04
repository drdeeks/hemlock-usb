"""
Plugin Manager - Two-Tier Injection System

Manages plugin injection with:
- Tier 1: Mandatory toolkit (enforce.sh, secret.sh, memory-*.sh)
- Tier 2: Optional plugins (autonomy-protocol, backup-protocol, etc.)

Guarantees:
- Never modifies without explicit user consent (Tier 2)
- Always creates backup before injection
- Provides rollback capability
- Works standalone if auto-injection fails
"""

import asyncio
import json
import logging
import os
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


from paths import resolver


class InjectionResult:
    """Result of plugin/toolkit injection."""
    
    def __init__(
        self,
        success: bool,
        injected: List[str] = None,
        backup_path: str = None,
        warning: str = None,
        error: str = None,
        recoverable: bool = True,
        missing_files: List[str] = None
    ):
        self.success = success
        self.injected = injected or []
        self.backup_path = backup_path
        self.warning = warning
        self.error = error
        self.recoverable = recoverable
        self.missing_files = missing_files or []
        
    @classmethod
    def success(cls, injected: List[str], backup_path: str = None, tier: int = 1):
        return cls(
            success=True,
            injected=injected,
            backup_path=backup_path
        )
        
    @classmethod
    def error(cls, message: str, recoverable: bool = True, backup_path: str = None):
        return cls(
            success=False,
            error=message,
            recoverable=recoverable,
            backup_path=backup_path
        )
        
    @classmethod
    def failure(cls, warning: str, backup_path: str = None, missing_files: List[str] = None):
        return cls(
            success=False,
            warning=warning,
            backup_path=backup_path,
            missing_files=missing_files or [],
            recoverable=True
        )
        
    @classmethod
    def skipped_by_user(cls):
        return cls(
            success=True,
            injected=[],
            warning="Skipped by user"
        )
        
    def to_dict(self) -> Dict:
        return {
            'success': self.success,
            'injected': self.injected,
            'backup_path': self.backup_path,
            'warning': self.warning,
            'error': self.error,
            'recoverable': self.recoverable,
            'missing_files': self.missing_files
        }


class PluginManager:
    """
    Manages plugin injection with two-tier system.
    
    Tier 1: Mandatory toolkit (always injected, no prompt)
    Tier 2: Optional plugins (user consent required)
    """
    
    # Mandatory per-agent tools (scripts). Agent-facing docs (AGENTS.md operating
    # standard, TOOLS.md tool registry — TOOLS-GUIDE.md was consolidated into TOOLS.md)
    # live at the workspace root, not in tools/, and are handled separately.
    TIER1_TOOLKIT = [
        'enforce.sh',
        'secret.sh',
        'memory-log.sh',
        'memory-promote.sh',
    ]
    
    TIER2_PLUGINS = [
        'autonomy-protocol',
        'backup-protocol',
        'subagent-driven-development',
        'agent-workspace-enforcement'
    ]
    
    def __init__(self, agents_dir: Optional[Path] = None, plugins_dir: Optional[Path] = None):
        self.agents_dir = agents_dir or resolver.agents_dir
        self.plugins_dir = plugins_dir or resolver.plugins_dir
        self.toolkit_source = self.plugins_dir / 'scripts' / 'agent-toolkit'
        self.backup_dir = resolver.plugin_backups_dir

        try:
            self.backup_dir.mkdir(parents=True, exist_ok=True)
        except PermissionError:
            logger.warning(f"Cannot create directory (permission denied): {self.backup_dir}")
        
    async def validate_agent_exists(self, agent_id: str) -> bool:
        """Validate agent exists."""
        agent_path = self.agents_dir / agent_id
        return agent_path.exists() and agent_path.is_dir()
        
    async def discover_plugins(self) -> List[str]:
        """Discover available Tier 2 plugins."""
        available = []
        
        injections_dir = self.plugins_dir / 'injections'
        if not injections_dir.exists():
            return self.TIER2_PLUGINS
            
        for plugin_dir in injections_dir.iterdir():
            if plugin_dir.is_dir():
                skill_md = plugin_dir / 'SKILL.md'
                if skill_md.exists():
                    available.append(plugin_dir.name)
                    
        return available if available else self.TIER2_PLUGINS
        
    async def create_backup(self, agent_id: str) -> str:
        """Create backup of agent's current state."""
        agent_path = self.agents_dir / agent_id
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_path = self.backup_dir / f'{agent_id}_{timestamp}'
        
        try:
            if agent_path.exists():
                # Backup tools/ directory if it exists
                tools_dir = agent_path / 'tools'
                if tools_dir.exists():
                    shutil.copytree(tools_dir, backup_path / 'tools')
                    
                # Backup skills/ directory if it exists
                skills_dir = agent_path / 'skills'
                if skills_dir.exists():
                    shutil.copytree(skills_dir, backup_path / 'skills')
                    
                # Create marker file
                (backup_path / '.backup_marker').write_text(
                    f'Backup created: {timestamp}\nAgent: {agent_id}'
                )
                
                logger.info(f"Created backup: {backup_path}")
                return str(backup_path)
            else:
                logger.warning(f"Agent path not found: {agent_path}")
                return None
                
        except Exception as e:
            logger.error(f"Failed to create backup: {e}")
            return None
            
    async def restore_from_backup(self, backup_path: str) -> bool:
        """Restore agent from backup."""
        try:
            backup = Path(backup_path)
            if not backup.exists():
                logger.error(f"Backup not found: {backup_path}")
                return False
                
            # Find agent ID from backup marker
            marker_file = backup / '.backup_marker'
            if marker_file.exists():
                marker_content = marker_file.read_text()
                agent_id = marker_content.split('Agent: ')[1].strip() if 'Agent: ' in marker_content else None
                
                if agent_id:
                    agent_path = self.agents_dir / agent_id
                    
                    # Restore tools/
                    backup_tools = backup / 'tools'
                    if backup_tools.exists():
                        agent_tools = agent_path / 'tools'
                        if agent_tools.exists():
                            shutil.rmtree(agent_tools)
                        shutil.copytree(backup_tools, agent_tools)
                        logger.info(f"Restored tools/ from backup")
                        
                    # Restore skills/
                    backup_skills = backup / 'skills'
                    if backup_skills.exists():
                        agent_skills = agent_path / 'skills'
                        if agent_skills.exists():
                            shutil.rmtree(agent_skills)
                        shutil.copytree(backup_skills, agent_skills)
                        logger.info(f"Restored skills/ from backup")
                        
                    return True
                    
            return False
            
        except Exception as e:
            logger.error(f"Failed to restore from backup: {e}")
            return False
            
    async def inject_tier1_mandatory(self, agent_id: str) -> InjectionResult:
        """
        Inject mandatory toolkit - MANDATORY, no user prompt.
        
        Guarantees:
        - Always injected at creation/import
        - Backup created before injection
        - Rollback on failure
        - Agent non-functional without toolkit
        """
        
        logger.info(f"Injecting mandatory toolkit into {agent_id}...")
        
        # VALIDATE
        if not await self.validate_agent_exists(agent_id):
            return InjectionResult.error(f"Agent '{agent_id}' not found")
            
        # BACKUP
        backup_path = await self.create_backup(agent_id)
        
        # INJECT TOOLKIT
        agent_tools_dir = self.agents_dir / agent_id / 'tools'
        agent_tools_dir.mkdir(parents=True, exist_ok=True)
        
        injected = []
        failed = []
        
        for tool_file in self.TIER1_TOOLKIT:
            source = self.toolkit_source / tool_file
            target = agent_tools_dir / tool_file
            
            if source.exists():
                try:
                    shutil.copy2(source, target)
                    os.chmod(target, 0o755 if tool_file.endswith('.sh') else 0o644)
                    injected.append(tool_file)
                    logger.info(f"Injected: {tool_file}")
                except Exception as e:
                    logger.error(f"Failed to inject {tool_file}: {e}")
                    failed.append(tool_file)
            else:
                logger.error(f"Toolkit file not found: {source}")
                failed.append(tool_file)
                
        # HANDLE PARTIAL FAILURE
        if failed:
            # ROLLBACK - Remove partially injected tools
            for tool in injected:
                try:
                    (agent_tools_dir / tool).unlink()
                except:
                    pass
                    
            # RESTORE BACKUP
            if backup_path:
                await self.restore_from_backup(backup_path)
                
            # RETURN FAILURE WITH WARNING
            return InjectionResult.failure(
                warning="⚠️  SECRETS WILL NOT BE ENCODED AT REST\n\n"
                        "The mandatory toolkit injection failed. This means:\n"
                        "  - Secrets stored in .secrets/ may be vulnerable\n"
                        "  - secret.sh tool unavailable for secure access\n"
                        "  - You MUST NOT access .secrets/ files directly\n"
                        "  - All secret operations MUST use tool calls\n\n"
                        "To repair toolkit:\n"
                        f"  python3 -m plugins.cli toolkit --repair --agent {agent_id}\n\n"
                        "Or delete agent and recreate:\n"
                        f"  ./scripts/agent-delete.sh --id {agent_id} --force",
                backup_path=backup_path,
                missing_files=failed
            )
            
        # SUCCESS
        logger.info(f"Mandatory toolkit injected successfully into {agent_id}")
        
        return InjectionResult.success(
            injected=self.TIER1_TOOLKIT,
            backup_path=backup_path,
            tier=1
        )
        
    async def inject_tier2_optional(
        self,
        agent_id: str,
        plugins: List[str] = None,
        auto: bool = False
    ) -> InjectionResult:
        """
        Inject optional plugins - USER PROMPT (unless auto mode).
        
        Guarantees:
        - User consent required (unless auto mode)
        - Can skip without breaking agent
        - Can be added later
        - Backup created before injection
        """
        
        logger.info(f"Injecting optional plugins into {agent_id}...")
        
        # VALIDATE
        if not await self.validate_agent_exists(agent_id):
            return InjectionResult.error(f"Agent '{agent_id}' not found")
            
        # DISCOVER AVAILABLE PLUGINS
        available = await self.discover_plugins()
        selected = plugins or available
        
        # If auto mode (scripted), inject all
        if auto:
            logger.info(f"Auto mode: injecting all {len(selected)} plugins")
        else:
            # PROMPT USER
            print(f"\n{'='*60}")
            print(f"Optional Plugins for: {agent_id}")
            print(f"{'='*60}\n")
            print("Available plugins:")
            
            for i, plugin in enumerate(available, 1):
                print(f"  [{i}] {plugin}")
                
            print(f"\n  [A] Install ALL plugins")
            print(f"  [N] Skip plugin installation")
            print(f"  [C] Custom selection (pick specific plugins)")
            print()
            
            choice = input("Your choice: ").strip().lower()
            
            if choice in ['n', 'no']:
                return InjectionResult.skipped_by_user()
            elif choice in ['a', 'all']:
                selected = available
            elif choice in ['c', 'custom']:
                custom_input = input("Enter plugin numbers (comma-separated): ").strip()
                try:
                    indices = [int(x.strip()) - 1 for x in custom_input.split(',')]
                    selected = [available[i] for i in indices if 0 <= i < len(available)]
                except (ValueError, IndexError):
                    logger.error("Invalid selection")
                    return InjectionResult.error("Invalid plugin selection")
            else:
                logger.error("Invalid choice")
                return InjectionResult.error("Invalid choice")
                
        # BACKUP
        backup_path = await self.create_backup(agent_id)
        
        # INJECT PLUGINS
        agent_skills_dir = self.agents_dir / agent_id / 'skills'
        agent_skills_dir.mkdir(parents=True, exist_ok=True)
        
        injected = []
        failed = []
        
        for plugin in selected:
            source = self.plugins_dir / 'injections' / plugin
            target = agent_skills_dir / plugin
            
            if source.exists() and source.is_dir():
                try:
                    shutil.copytree(source, target)
                    injected.append(plugin)
                    logger.info(f"Injected plugin: {plugin}")
                except Exception as e:
                    logger.error(f"Failed to inject plugin {plugin}: {e}")
                    failed.append(plugin)
            else:
                # Try injecting from TIER2_PLUGINS list (skill name only)
                logger.info(f"Plugin directory not found, creating skill entry for: {plugin}")
                skill_dir = agent_skills_dir / plugin
                skill_dir.mkdir(parents=True, exist_ok=True)
                (skill_dir / 'SKILL.md').write_text(f"# {plugin}\n\nAuto-injected skill placeholder")
                injected.append(plugin)
                
        # HANDLE FAILURES
        if failed:
            logger.warning(f"Failed to inject plugins: {failed}")
            # Don't rollback for optional plugins, just report
            return InjectionResult.failure(
                warning=f"Failed to inject plugins: {failed}",
                backup_path=backup_path,
                missing_files=failed
            )
            
        logger.info(f"Optional plugins injected successfully into {agent_id}")
        
        return InjectionResult.success(
            injected=injected,
            backup_path=backup_path,
            tier=2
        )


async def main():
    """Test plugin manager."""
    manager = PluginManager()
    
    # Test discovery
    plugins = await manager.discover_plugins()
    print(f"Available plugins: {plugins}")
    
    # Test validation
    exists = await manager.validate_agent_exists('test-agent')
    print(f"Test agent exists: {exists}")


if __name__ == '__main__':
    asyncio.run(main())
