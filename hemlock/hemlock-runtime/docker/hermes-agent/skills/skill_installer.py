"""
Skill Installer - Cherry-Pick and Batch Installation

Provides:
- Install single skills (cherry-pick)
- Install multiple skills at once (batch)
- Check skill dependencies
- Log all installations
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

from skills.skill_registry import SkillRegistry, SkillMetadata

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SkillInstaller:
    """
    Skill installation with dependency checking and batch support.
    """
    
    def __init__(self, registry: SkillRegistry = None):
        self.registry = registry or SkillRegistry()
        self.install_log = []
        
    async def install(self, skill_name: str, agent_id: str,
                      check_dependencies: bool = True,
                      force: bool = False) -> bool:
        """
        Install a single skill (cherry-pick).
        
        Args:
            skill_name: Name of skill to install
            agent_id: Target agent ID
            check_dependencies: Check and install dependencies (default: True)
            force: Overwrite existing skill
            
        Returns:
            True if successful, False otherwise
        """
        logger.info(f"Installing skill {skill_name} to agent {agent_id}...")
        
        # Check dependencies first
        if check_dependencies:
            dependencies = await self._get_dependencies(skill_name)
            if dependencies:
                logger.info(f"Checking dependencies: {dependencies}")
                for dep in dependencies:
                    if not await self._is_installed(dep, agent_id):
                        logger.info(f"Installing dependency: {dep}")
                        dep_success = await self.install(dep, agent_id, 
                                                         check_dependencies=True,
                                                         force=force)
                        if not dep_success:
                            logger.error(f"Failed to install dependency: {dep}")
                            return False
        
        # Install the skill
        success = await self.registry.install_to_agent(skill_name, agent_id, force)
        
        # Log the installation
        self._log_installation(skill_name, agent_id, success)
        
        return success
        
    async def install_batch(self, skill_names: List[str], agent_id: str,
                            check_dependencies: bool = True,
                            force: bool = False) -> Dict[str, bool]:
        """
        Install multiple skills at once (batch install).
        
        Args:
            skill_names: List of skill names to install
            agent_id: Target agent ID
            check_dependencies: Check and install dependencies
            force: Overwrite existing skills
            
        Returns:
            Dictionary mapping skill names to success status
        """
        logger.info(f"Batch installing {len(skill_names)} skills to agent {agent_id}...")
        
        results = {}
        
        # Sort skills to install dependencies first
        ordered = await self._order_by_dependencies(skill_names)
        
        for skill_name in ordered:
            if skill_name in results:
                continue  # Already installed as dependency
                
            success = await self.install(skill_name, agent_id, 
                                         check_dependencies=check_dependencies,
                                         force=force)
            results[skill_name] = success
            
        # Log batch installation
        self._log_batch_installation(skill_names, agent_id, results)
        
        return results
        
    async def _get_dependencies(self, skill_name: str) -> List[str]:
        """
        Get list of dependencies for a skill.
        
        Args:
            skill_name: Name of skill
            
        Returns:
            List of dependency skill names
        """
        skill_path = self.registry.skills_root / skill_name
        skill_md = skill_path / 'SKILL.md'
        
        if not skill_md.exists():
            return []
            
        try:
            import yaml
            content = skill_md.read_text()
            
            if content.startswith('---'):
                parts = content.split('---', 2)
                if len(parts) >= 2:
                    data = yaml.safe_load(parts[1])
                    if data:
                        deps = data.get('dependencies', [])
                        return deps or []
        except Exception as e:
            logger.warning(f"Failed to parse dependencies for {skill_name}: {e}")
            
        return []
        
    async def _is_installed(self, skill_name: str, agent_id: str) -> bool:
        """
        Check if a skill is already installed for an agent.
        
        Args:
            skill_name: Name of skill
            agent_id: Agent ID
            
        Returns:
            True if installed, False otherwise
        """
        agent_skills = self.registry.agents_dir / agent_id / 'skills'
        skill_path = agent_skills / skill_name
        return skill_path.exists()
        
    async def _order_by_dependencies(self, skill_names: List[str]) -> List[str]:
        """
        Order skills by dependencies (dependencies first).
        
        Args:
            skill_names: List of skill names
            
        Returns:
            Ordered list of skill names
        """
        # Simple topological sort
        ordered = []
        visited = set()
        
        def visit(skill_name: str):
            if skill_name in visited:
                return
                
            visited.add(skill_name)
            
            # Visit dependencies first
            deps = self._get_dependencies_sync(skill_name)
            for dep in deps:
                if dep in skill_names:
                    visit(dep)
                    
            ordered.append(skill_name)
            
        for skill_name in skill_names:
            visit(skill_name)
            
        return ordered
        
    def _get_dependencies_sync(self, skill_name: str) -> List[str]:
        """
        Get dependencies synchronously (for use within async context).
        
        Args:
            skill_name: Name of skill
            
        Returns:
            List of dependency skill names
        """
        skill_path = self.registry.skills_root / skill_name
        skill_md = skill_path / 'SKILL.md'
        
        if not skill_md.exists():
            return []
            
        try:
            import yaml
            content = skill_md.read_text()
            
            if content.startswith('---'):
                parts = content.split('---', 2)
                if len(parts) >= 2:
                    data = yaml.safe_load(parts[1])
                    if data:
                        deps = data.get('dependencies', [])
                        return deps or []
        except Exception as e:
            logger.debug(f"Failed to parse dependencies for {skill_name}: {e}")
            
        return []
        
    def _log_installation(self, skill_name: str, agent_id: str, success: bool):
        """Log a single installation."""
        entry = {
            'timestamp': datetime.now().isoformat(),
            'action': 'install',
            'skill': skill_name,
            'agent': agent_id,
            'success': success
        }
        self.install_log.append(entry)
        logger.info(f"Installation log: {entry}")
        
    def _log_batch_installation(self, skill_names: List[str], agent_id: str,
                                 results: Dict[str, bool]):
        """Log a batch installation."""
        entry = {
            'timestamp': datetime.now().isoformat(),
            'action': 'batch_install',
            'skills': skill_names,
            'agent': agent_id,
            'results': results,
            'success_count': sum(1 for v in results.values() if v),
            'failure_count': sum(1 for v in results.values() if not v)
        }
        self.install_log.append(entry)
        logger.info(f"Batch installation log: {entry}")
        
    def get_install_log(self) -> List[Dict]:
        """Get installation log."""
        return self.install_log
        
    def save_install_log(self, log_path: str = None):
        """
        Save installation log to file.
        
        Args:
            log_path: Path to save log (default: skills/install_log.json)
        """
        if not log_path:
            log_path = Path(__file__).parent / 'install_log.json'
            
        with open(log_path, 'w') as f:
            json.dump(self.install_log, f, indent=2)
            
        logger.info(f"Installation log saved to {log_path}")


async def main():
    """CLI entry point."""
    import sys
    
    installer = SkillInstaller()
    
    if len(sys.argv) < 2:
        print("Usage: python -m skills.skill_installer [install|batch|log]")
        print("  install <skill> <agent>           - Install single skill")
        print("  batch <skill1,skill2,...> <agent> - Install multiple skills")
        print("  log                               - Show installation log")
        sys.exit(1)
        
    command = sys.argv[1]
    
    if command == 'install':
        if len(sys.argv) < 4:
            print("Usage: install <skill_name> <agent_id>")
            sys.exit(1)
            
        skill_name = sys.argv[2]
        agent_id = sys.argv[3]
        
        success = await installer.install(skill_name, agent_id)
        if success:
            print(f"✓ Skill {skill_name} installed to agent {agent_id}")
        else:
            print(f"✗ Failed to install {skill_name}")
            sys.exit(1)
            
    elif command == 'batch':
        if len(sys.argv) < 4:
            print("Usage: batch <skill1,skill2,...> <agent_id>")
            sys.exit(1)
            
        skill_names = [s.strip() for s in sys.argv[2].split(',')]
        agent_id = sys.argv[3]
        
        results = await installer.install_batch(skill_names, agent_id)
        
        print(f"\n{'='*60}")
        print(f"Batch Installation Results")
        print(f"{'='*60}\n")
        
        for skill, success in results.items():
            status = "✓" if success else "✗"
            print(f"  {status} {skill}")
            
        success_count = sum(1 for v in results.values() if v)
        print(f"\nTotal: {success_count}/{len(results)} installed")
        
    elif command == 'log':
        log = installer.get_install_log()
        if not log:
            print("No installations logged")
        else:
            print(f"\n{'='*60}")
            print(f"Installation Log ({len(log)} entries)")
            print(f"{'='*60}\n")
            for entry in log:
                print(f"  [{entry['timestamp']}] {entry['action']}: {entry.get('skill') or entry.get('skills')} -> {entry['agent']}")
                print(f"    Status: {'Success' if entry['success'] else 'Failed'}")
                print()
                
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    asyncio.run(main())
