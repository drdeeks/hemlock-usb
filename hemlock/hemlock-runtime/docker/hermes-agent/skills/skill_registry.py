"""
Skill Registry - Central Registry for All 289 Skills

Provides:
- List all available skills from root /skills/ mount
- Install skills to agent workspace (copy from /skills/ to agent/skills/)
- Parse skill metadata from SKILL.md files
- Track skill versions and installation status
"""

import asyncio
import json
import logging
import os
import shutil
import yaml
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


from paths import resolver


class SkillMetadata:
    """Parsed skill metadata from SKILL.md frontmatter."""
    
    def __init__(self, name: str = "", description: str = "", version: str = "1.0.0",
                 author: str = "", license: str = "MIT", tags: List[str] = None,
                 category: str = "", complexity: str = "basic"):
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.license = license
        self.tags = tags or []
        self.category = category
        self.complexity = complexity
        
    @classmethod
    def from_file(cls, skill_md_path: Path) -> 'SkillMetadata':
        """Parse SKILL.md frontmatter to extract metadata."""
        metadata = cls()
        
        if not skill_md_path.exists():
            logger.debug(f"SKILL.md not found: {skill_md_path}")
            return metadata
            
        try:
            content = skill_md_path.read_text()
            
            # Extract YAML frontmatter (between --- markers)
            if content.startswith('---'):
                parts = content.split('---', 2)
                if len(parts) >= 2:
                    yaml_content = parts[1].strip()
                    try:
                        data = yaml.safe_load(yaml_content)
                        if data:
                            metadata.name = data.get('name', skill_md_path.parent.name)
                            metadata.description = data.get('description', '')
                            metadata.version = data.get('version', '1.0.0')
                            metadata.author = data.get('author', 'unknown')
                            metadata.license = data.get('license', 'MIT')
                            
                            # Parse metadata section
                            meta = data.get('metadata', {})
                            if isinstance(meta, dict):
                                hermes = meta.get('hermes', {})
                                if isinstance(hermes, dict):
                                    metadata.tags = hermes.get('tags', [])
                                    metadata.category = hermes.get('category', '')
                                    metadata.complexity = hermes.get('complexity', 'basic')
                    except yaml.YAMLError as e:
                        logger.debug(f"YAML parse error for {skill_md_path.parent.name}: {e}")
                        # Fall back to extracting name from directory
                        metadata.name = skill_md_path.parent.name
        except Exception as e:
            logger.debug(f"Failed to read SKILL.md: {e}")
            # Fall back to directory name
            metadata.name = skill_md_path.parent.name
            
        # Ensure name is set
        if not metadata.name:
            metadata.name = skill_md_path.parent.name
            
        return metadata
        
    def to_dict(self) -> Dict:
        return {
            'name': self.name,
            'description': self.description,
            'version': self.version,
            'author': self.author,
            'license': self.license,
            'tags': self.tags,
            'category': self.category,
            'complexity': self.complexity
        }


class SkillRegistry:
    """
    Central registry for all skills.
    
    Skills are stored in read-only root mount at /skills/
    Agents can install skills by copying to their workspace.
    """
    
    def __init__(self, skills_root: str = None, agents_dir: str = None):
        if skills_root:
            self.skills_root = Path(skills_root)
        else:
            self.skills_root = resolver.skills_root
            if not self.skills_root.exists():
                self.skills_root = Path('/skills')
                
        if agents_dir:
            self.agents_dir = Path(agents_dir)
        else:
            self.agents_dir = resolver.agents_dir
            
        logger.info(f"Skill registry initialized: {self.skills_root}")
        
    async def list_available(self, category: str = None, tags: List[str] = None) -> List[Dict]:
        """
        List all available skills from root mount.
        
        Args:
            category: Filter by category (optional)
            tags: Filter by tags (optional)
            
        Returns:
            List of skill metadata dictionaries
        """
        skills = []
        
        if not self.skills_root.exists():
            logger.error(f"Skills root not found: {self.skills_root}")
            return skills
            
        for skill_dir in self.skills_root.iterdir():
            if not skill_dir.is_dir():
                continue
                
            # Parse SKILL.md
            skill_md = skill_dir / 'SKILL.md'
            metadata = SkillMetadata.from_file(skill_md)
            
            # Use directory name if name not in metadata
            if not metadata.name:
                metadata.name = skill_dir.name
                
            # Apply filters
            if category and metadata.category != category:
                continue
                
            if tags:
                if not any(tag in metadata.tags for tag in tags):
                    continue
                    
            skills.append(metadata.to_dict())
            
        # Sort by name
        skills.sort(key=lambda x: x['name'])
        
        logger.info(f"Found {len(skills)} available skills")
        return skills
        
    async def install_to_agent(self, skill_name: str, agent_id: str, 
                                force: bool = False) -> bool:
        """
        Install a skill to an agent's workspace.
        
        Args:
            skill_name: Name of skill to install
            agent_id: Target agent ID
            force: Overwrite existing skill (default: False)
            
        Returns:
            True if successful, False otherwise
        """
        # Find skill in root
        skill_source = self.skills_root / skill_name
        if not skill_source.exists():
            logger.error(f"Skill not found: {skill_name}")
            return False
            
        # Validate agent exists
        agent_dir = self.agents_dir / agent_id
        if not agent_dir.exists():
            logger.error(f"Agent not found: {agent_id}")
            return False
            
        # Create agent skills directory if needed
        agent_skills = agent_dir / 'skills'
        agent_skills.mkdir(parents=True, exist_ok=True)
        
        # Check if already installed
        skill_target = agent_skills / skill_name
        if skill_target.exists() and not force:
            logger.warning(f"Skill already installed: {skill_name} for {agent_id}")
            return False
            
        # Copy skill to agent workspace
        try:
            if skill_target.exists():
                shutil.rmtree(skill_target)
                
            shutil.copytree(skill_source, skill_target)
            logger.info(f"Installed skill {skill_name} to agent {agent_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to install skill: {e}")
            return False
            
    async def install_multiple(self, skill_names: List[str], agent_id: str,
                                force: bool = False) -> Dict[str, bool]:
        """
        Install multiple skills to an agent.
        
        Args:
            skill_names: List of skill names to install
            agent_id: Target agent ID
            force: Overwrite existing skills
            
        Returns:
            Dictionary mapping skill names to success status
        """
        results = {}
        
        for skill_name in skill_names:
            success = await self.install_to_agent(skill_name, agent_id, force)
            results[skill_name] = success
            
        return results
        
    async def get_installed(self, agent_id: str) -> List[Dict]:
        """
        Get list of skills installed for an agent.
        
        Args:
            agent_id: Agent ID
            
        Returns:
            List of installed skill metadata
        """
        installed = []
        agent_skills = self.agents_dir / agent_id / 'skills'
        
        if not agent_skills.exists():
            return installed
            
        for skill_dir in agent_skills.iterdir():
            if not skill_dir.is_dir():
                continue
                
            skill_md = skill_dir / 'SKILL.md'
            metadata = SkillMetadata.from_file(skill_md)
            
            if not metadata.name:
                metadata.name = skill_dir.name
                
            installed.append(metadata.to_dict())
            
        installed.sort(key=lambda x: x['name'])
        return installed
        
    async def uninstall(self, skill_name: str, agent_id: str) -> bool:
        """
        Uninstall a skill from an agent.
        
        Args:
            skill_name: Name of skill to uninstall
            agent_id: Agent ID
            
        Returns:
            True if successful, False otherwise
        """
        agent_skills = self.agents_dir / agent_id / 'skills'
        skill_path = agent_skills / skill_name
        
        if not skill_path.exists():
            logger.warning(f"Skill not installed: {skill_name} for {agent_id}")
            return False
            
        try:
            shutil.rmtree(skill_path)
            logger.info(f"Uninstalled skill {skill_name} from agent {agent_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to uninstall skill: {e}")
            return False


async def main():
    """CLI entry point."""
    import sys
    
    registry = SkillRegistry()
    
    if len(sys.argv) < 2:
        print("Usage: python -m skills.skill_registry [list|install|uninstall|installed]")
        print("  list                     - List all available skills")
        print("  install <skill> <agent>  - Install skill to agent")
        print("  uninstall <skill> <agent> - Uninstall skill from agent")
        print("  installed <agent>        - List installed skills for agent")
        sys.exit(1)
        
    command = sys.argv[1]
    
    if command == 'list':
        skills = await registry.list_available()
        print(f"\n{'='*60}")
        print(f"Available Skills ({len(skills)} total)")
        print(f"{'='*60}\n")
        
        for skill in skills:
            print(f"  • {skill['name']}")
            if skill.get('description'):
                print(f"    {skill['description']}")
            if skill.get('tags'):
                print(f"    Tags: {', '.join(skill['tags'])}")
            print()
            
    elif command == 'install':
        if len(sys.argv) < 4:
            print("Usage: install <skill_name> <agent_id>")
            sys.exit(1)
            
        skill_name = sys.argv[2]
        agent_id = sys.argv[3]
        
        success = await registry.install_to_agent(skill_name, agent_id)
        if success:
            print(f"✓ Skill {skill_name} installed to agent {agent_id}")
        else:
            print(f"✗ Failed to install {skill_name}")
            sys.exit(1)
            
    elif command == 'uninstall':
        if len(sys.argv) < 4:
            print("Usage: uninstall <skill_name> <agent_id>")
            sys.exit(1)
            
        skill_name = sys.argv[2]
        agent_id = sys.argv[3]
        
        success = await registry.uninstall(skill_name, agent_id)
        if success:
            print(f"✓ Skill {skill_name} uninstalled from agent {agent_id}")
        else:
            print(f"✗ Failed to uninstall {skill_name}")
            sys.exit(1)
            
    elif command == 'installed':
        if len(sys.argv) < 3:
            print("Usage: installed <agent_id>")
            sys.exit(1)
            
        agent_id = sys.argv[2]
        skills = await registry.get_installed(agent_id)
        
        print(f"\n{'='*60}")
        print(f"Installed Skills for {agent_id} ({len(skills)} total)")
        print(f"{'='*60}\n")
        
        for skill in skills:
            print(f"  • {skill['name']}")
            if skill.get('description'):
                print(f"    {skill['description']}")
            print()
            
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    asyncio.run(main())
