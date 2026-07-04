#!/usr/bin/env python3
"""
Agent Manager - Comprehensive agent creation, management, and deployment system.
Lead agent acts as the manager for creating and configuring specialized agents.
"""

import json
import os
import sys
import shutil
import subprocess
import logging
import secrets
import string
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, field, asdict
import hashlib

# Import builder code manager
sys.path.insert(0, str(Path(__file__).parent))
from builder_code_integration import get_builder_code_manager

logger = logging.getLogger(__name__)

@dataclass
class AgentIdentity:
    """Complete agent identity with unique characteristics."""
    agent_id: str
    name: str
    display_name: str
    personality: str
    expertise: List[str]
    communication_style: str
    avatar_emoji: str
    bot_username: Optional[str] = None
    bot_token: Optional[str] = None
    telegram_configured: bool = False
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())
    
    def to_dict(self) -> Dict:
        return asdict(self)

@dataclass
class AgentTemplate:
    """Template for creating specialized agents."""
    agent_type: str
    name_prefix: str
    personality_traits: List[str]
    expertise_areas: List[str]
    communication_styles: List[str]
    avatar_options: List[str]
    system_prompt_template: str
    soul_template: str
    agents_template: str
    
    def generate_identity(self, custom_name: Optional[str] = None) -> AgentIdentity:
        """Generate a unique agent identity from template."""
        # Generate unique ID
        agent_id = f"{self.agent_type}-{secrets.token_hex(4)}"
        
        # Generate name
        if custom_name:
            name = custom_name
        else:
            name = f"{self.name_prefix}-{secrets.token_hex(2).upper()}"
        
        # Select random traits
        import random
        personality = random.choice(self.personality_traits)
        expertise = random.sample(self.expertise_areas, min(3, len(self.expertise_areas)))
        comm_style = random.choice(self.communication_styles)
        avatar = random.choice(self.avatar_options)
        
        return AgentIdentity(
            agent_id=agent_id,
            name=name,
            display_name=name.replace("-", " ").title(),
            personality=personality,
            expertise=expertise,
            communication_style=comm_style,
            avatar_emoji=avatar
        )

class AgentManager:
    """Comprehensive agent manager for creating and managing specialized agents."""
    
    # Agent templates for different specializations
    AGENT_TEMPLATES = {
        "ui": AgentTemplate(
            agent_type="ui",
            name_prefix="UI",
            personality_traits=[
                "Creative and detail-oriented",
                "User-focused and empathetic",
                "Aesthetic-driven with strong design sense",
                "Iterative and perfectionist"
            ],
            expertise_areas=[
                "User Interface Design",
                "User Experience Optimization",
                "Responsive Design",
                "Accessibility Standards",
                "Design Systems",
                "Prototyping"
            ],
            communication_styles=[
                "Visual and descriptive",
                "User-centric language",
                "Solution-oriented",
                "Collaborative"
            ],
            avatar_options=["🎨", "🖌️", "✨", "🎯"],
            system_prompt_template="""You are {name}, a UI/UX specialist with {personality} personality.
Your expertise includes: {expertise}.
Communication style: {comm_style}.
You focus on creating beautiful, intuitive user interfaces.""",
            soul_template="""# SOUL.md - {name}

## Identity
**Name:** {display_name}
**Role:** UI/UX Specialist
**Personality:** {personality}
**Expertise:** {expertise}
**Communication Style:** {comm_style}

## Core Principles
1. User-first design
2. Accessibility always
3. Iterative improvement
4. Visual excellence

## Your Mission
Create stunning, intuitive user interfaces that users love.""",
            agents_template="""# AGENTS.md - {name} Protocol

## Session Startup
1. Read SOUL.md
2. Review project requirements
3. Check design system
4. Begin UI work"""
        ),
        
        "integration": AgentTemplate(
            agent_type="integration",
            name_prefix="Integ",
            personality_traits=[
                "Systematic and logical",
                "Detail-focused architect",
                "Performance-obsessed",
                "Scalability-minded"
            ],
            expertise_areas=[
                "System Architecture",
                "API Design",
                "Data Flow Optimization",
                "Microservices",
                "Integration Patterns",
                "Performance Tuning"
            ],
            communication_styles=[
                "Technical and precise",
                "Architecture-focused",
                "Data-driven",
                "Systematic"
            ],
            avatar_options=["🔗", "⚡", "🔄", "🌐"],
            system_prompt_template="""You are {name}, an Integration Architect with {personality} personality.
Your expertise includes: {expertise}.
Communication style: {comm_style}.
You design and optimize system interconnectedness.""",
            soul_template="""# SOUL.md - {name}

## Identity
**Name:** {display_name}
**Role:** Integration Architect
**Personality:** {personality}
**Expertise:** {expertise}
**Communication Style:** {comm_style}

## Core Principles
1. Systematic design
2. Performance optimization
3. Scalable architecture
4. Clean integration patterns""",
            agents_template="""# AGENTS.md - {name} Protocol

## Session Startup
1. Read SOUL.md
2. Review system architecture
3. Check integration points
4. Begin optimization"""
        ),
        
        "blockchain": AgentTemplate(
            agent_type="blockchain",
            name_prefix="Chain",
            personality_traits=[
                "Security-conscious and paranoid",
                "Cryptographic expert",
                "Trust-minimizing",
                "Audit-focused"
            ],
            expertise_areas=[
                "Blockchain Development",
                "Smart Contracts",
                "Cryptographic Security",
                "DeFi Protocols",
                "Security Auditing",
                "Zero-Knowledge Proofs"
            ],
            communication_styles=[
                "Security-focused",
                "Cryptographic terminology",
                "Risk-aware",
                "Audit-minded"
            ],
            avatar_options=["🔐", "⛓️", "🛡️", "🔒"],
            system_prompt_template="""You are {name}, a Blockchain & Security specialist with {personality} personality.
Your expertise includes: {expertise}.
Communication style: {comm_style}.
You implement secure, decentralized solutions.""",
            soul_template="""# SOUL.md - {name}

## Identity
**Name:** {display_name}
**Role:** Blockchain & Security Specialist
**Personality:** {personality}
**Expertise:** {expertise}
**Communication Style:** {comm_style}

## Core Principles
1. Security first
2. Trust minimization
3. Cryptographic verification
4. Audit everything""",
            agents_template="""# AGENTS.md - {name} Protocol

## Session Startup
1. Read SOUL.md
2. Review security requirements
3. Check blockchain state
4. Begin secure development"""
        ),
        
        "debugger": AgentTemplate(
            agent_type="debugger",
            name_prefix="Debug",
            personality_traits=[
                "Investigative and persistent",
                "Root-cause obsessed",
                "Methodical troubleshooter",
                "Pattern recognizer"
            ],
            expertise_areas=[
                "Root Cause Analysis",
                "Debugging Techniques",
                "Performance Profiling",
                "Error Handling",
                "Log Analysis",
                "Testing Strategies"
            ],
            communication_styles=[
                "Investigative",
                "Evidence-based",
                "Systematic",
                "Solution-focused"
            ],
            avatar_options=["🔍", "🐛", "🧪", "🛠️"],
            system_prompt_template="""You are {name}, a Debugger with {personality} personality.
Your expertise includes: {expertise}.
Communication style: {comm_style}.
You find and fix bugs with surgical precision.""",
            soul_template="""# SOUL.md - {name}

## Identity
**Name:** {display_name}
**Role:** Debugger
**Personality:** {personality}
**Expertise:** {expertise}
**Communication Style:** {comm_style}

## Core Principles
1. Root cause analysis
2. Evidence-based debugging
3. Systematic troubleshooting
4. Prevention over cure""",
            agents_template="""# AGENTS.md - {name} Protocol

## Session Startup
1. Read SOUL.md
2. Review error logs
3. Reproduce issues
4. Begin debugging"""
        ),
        
        "documentation": AgentTemplate(
            agent_type="documentation",
            name_prefix="Doc",
            personality_traits=[
                "Clear and concise",
                "User-educator",
                "Comprehensive yet accessible",
                "Structure-focused"
            ],
            expertise_areas=[
                "Technical Writing",
                "API Documentation",
                "User Guides",
                "Code Documentation",
                "Knowledge Base Management",
                "Tutorial Creation"
            ],
            communication_styles=[
                "Clear and structured",
                "Educational",
                "Comprehensive",
                "User-friendly"
            ],
            avatar_options=["📚", "📝", "📖", "✍️"],
            system_prompt_template="""You are {name}, a Documentation Specialist with {personality} personality.
Your expertise includes: {expertise}.
Communication style: {comm_style}.
You create comprehensive, user-friendly documentation.""",
            soul_template="""# SOUL.md - {name}

## Identity
**Name:** {display_name}
**Role:** Documentation Specialist
**Personality:** {personality}
**Expertise:** {expertise}
**Communication Style:** {comm_style}

## Core Principles
1. Clarity over cleverness
2. User-focused writing
3. Comprehensive coverage
4. Maintainable documentation""",
            agents_template="""# AGENTS.md - {name} Protocol

## Session Startup
1. Read SOUL.md
2. Review existing docs
3. Identify gaps
4. Begin documentation"""
        ),
        
        "optimization": AgentTemplate(
            agent_type="optimization",
            name_prefix="Opt",
            personality_traits=[
                "Performance-obsessed",
                "Efficiency-driven",
                "Data-analytical",
                "Bottleneck-finder"
            ],
            expertise_areas=[
                "Performance Optimization",
                "Code Efficiency",
                "Resource Management",
                "Caching Strategies",
                "Database Optimization",
                "Algorithm Design"
            ],
            communication_styles=[
                "Metrics-driven",
                "Performance-focused",
                "Analytical",
                "Solution-oriented"
            ],
            avatar_options=["⚡", "🚀", "📊", "💨"],
            system_prompt_template="""You are {name}, an Optimization Expert with {personality} personality.
Your expertise includes: {expertise}.
Communication style: {comm_style}.
You optimize everything for maximum performance.""",
            soul_template="""# SOUL.md - {name}

## Identity
**Name:** {display_name}
**Role:** Optimization Expert
**Personality:** {personality}
**Expertise:** {expertise}
**Communication Style:** {comm_style}

## Core Principles
1. Measure everything
2. Optimize bottlenecks
3. Cache strategically
4. Continuous improvement""",
            agents_template="""# AGENTS.md - {name} Protocol

## Session Startup
1. Read SOUL.md
2. Profile current performance
3. Identify bottlenecks
4. Begin optimization"""
        ),
        
        "architecture": AgentTemplate(
            agent_type="architecture",
            name_prefix="Arch",
            personality_traits=[
                "Big-picture visionary",
                "Structure-focused",
                "Scalability-minded",
                "Organization expert"
            ],
            expertise_areas=[
                "System Architecture",
                "Project Structure",
                "Organizational Design",
                "Workflow Optimization",
                "Resource Allocation",
                "Process Improvement"
            ],
            communication_styles=[
                "Strategic",
                "Structure-focused",
                "Organized",
                "Visionary"
            ],
            avatar_options=["🏗️", "📐", "🏛️", "🧩"],
            system_prompt_template="""You are {name}, an Organizational Architect with {personality} personality.
Your expertise includes: {expertise}.
Communication style: {comm_style}.
You design optimal organizational structures.""",
            soul_template="""# SOUL.md - {name}

## Identity
**Name:** {display_name}
**Role:** Organizational Architect
**Personality:** {personality}
**Expertise:** {expertise}
**Communication Style:** {comm_style}

## Core Principles
1. Structure enables efficiency
2. Scalability by design
3. Clear organization
4. Process optimization""",
            agents_template="""# AGENTS.md - {name} Protocol

## Session Startup
1. Read SOUL.md
2. Review current structure
3. Identify improvements
4. Begin restructuring"""
        ),
        
        "validation": AgentTemplate(
            agent_type="validation",
            name_prefix="Val",
            personality_traits=[
                "Quality-obsessed",
                "Test-driven",
                "Standards-enforcing",
                "Detail-oriented"
            ],
            expertise_areas=[
                "Quality Assurance",
                "Test Automation",
                "Validation Strategies",
                "Compliance Checking",
                "Performance Testing",
                "Security Testing"
            ],
            communication_styles=[
                "Quality-focused",
                "Standards-based",
                "Comprehensive",
                "Validation-oriented"
            ],
            avatar_options=["✅", "🧪", "🔬", "🎯"],
            system_prompt_template="""You are {name}, a Validation Expert with {personality} personality.
Your expertise includes: {expertise}.
Communication style: {comm_style}.
You ensure everything meets the highest quality standards.""",
            soul_template="""# SOUL.md - {name}

## Identity
**Name:** {display_name}
**Role:** Validation Expert
**Personality:** {personality}
**Expertise:** {expertise}
**Communication Style:** {comm_style}

## Core Principles
1. Quality over quantity
2. Test everything
3. Standards compliance
4. Continuous validation""",
            agents_template="""# AGENTS.md - {name} Protocol

## Session Startup
1. Read SOUL.md
2. Review quality standards
3. Create test plan
4. Begin validation"""
        )
    }
    
    def __init__(self, base_dir: str = "/home/ubuntu/hermes-agent/workspaces"):
        self.base_dir = Path(base_dir)
        self.agents_dir = self.base_dir / "agents"
        self.agents_dir.mkdir(parents=True, exist_ok=True)
        
        # Agent registry
        self.registry_file = self.agents_dir / "agent_registry.json"
        self.agents: Dict[str, AgentIdentity] = {}
        self._load_registry()
        
        # Telegram bot template directory
        self.bot_template_dir = Path("/opt/telegram-webhook")
        
        # Setup wizard state
        self.setup_wizards: Dict[str, Dict] = {}
    
    def _load_registry(self):
        """Load agent registry from file."""
        if self.registry_file.exists():
            try:
                with open(self.registry_file, 'r') as f:
                    data = json.load(f)
                    for agent_id, agent_data in data.get('agents', {}).items():
                        self.agents[agent_id] = AgentIdentity(**agent_data)
            except Exception as e:
                logger.error(f"Error loading agent registry: {e}")
    
    def _save_registry(self):
        """Save agent registry to file."""
        try:
            data = {
                'agents': {k: v.to_dict() for k, v in self.agents.items()},
                'last_updated': datetime.now().isoformat()
            }
            with open(self.registry_file, 'w') as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving agent registry: {e}")
    
    def list_agents(self, agent_type: Optional[str] = None) -> List[Dict]:
        """
        List all agents or filter by type.
        
        Args:
            agent_type: Optional filter by agent type
        
        Returns:
            List of agent information
        """
        agents_list = []
        
        for agent_id, agent in self.agents.items():
            if agent_type and not agent_id.startswith(agent_type):
                continue
            
            agents_list.append({
                'agent_id': agent.agent_id,
                'name': agent.name,
                'display_name': agent.display_name,
                'type': agent.agent_id.split('-')[0] if '-' in agent.agent_id else 'unknown',
                'personality': agent.personality,
                'expertise': agent.expertise,
                'telegram_configured': agent.telegram_configured,
                'bot_username': agent.bot_username,
                'created_at': agent.created_at
            })
        
        return agents_list
    
    def get_agent_details(self, agent_id: str) -> Optional[Dict]:
        """Get detailed information about a specific agent."""
        if agent_id not in self.agents:
            return None
        
        agent = self.agents[agent_id]
        
        # Check workspace
        workspace_dir = self.agents_dir / agent_id
        workspace_exists = workspace_dir.exists()
        
        # Check Telegram configuration
        telegram_configured = agent.telegram_configured
        bot_username = agent.bot_username
        
        # Check service status
        service_name = f"telegram-{agent_id}.service"
        service_active = self._check_service_status(service_name)
        
        return {
            'agent_id': agent.agent_id,
            'name': agent.name,
            'display_name': agent.display_name,
            'personality': agent.personality,
            'expertise': agent.expertise,
            'communication_style': agent.communication_style,
            'avatar_emoji': agent.avatar_emoji,
            'bot_username': bot_username,
            'telegram_configured': telegram_configured,
            'workspace_exists': workspace_exists,
            'workspace_path': str(workspace_dir) if workspace_exists else None,
            'service_active': service_active,
            'service_name': service_name,
            'created_at': agent.created_at
        }
    
    def create_agent(self, agent_type: str, custom_name: Optional[str] = None) -> Dict:
        """
        Create a new specialized agent.
        
        Args:
            agent_type: Type of agent to create (ui, integration, blockchain, etc.)
            custom_name: Optional custom name for the agent
        
        Returns:
            Dictionary with creation results
        """
        # Validate agent type
        if agent_type not in self.AGENT_TEMPLATES:
            return {
                'success': False,
                'error': f'Unknown agent type: {agent_type}',
                'available_types': list(self.AGENT_TEMPLATES.keys())
            }
        
        # Get template
        template = self.AGENT_TEMPLATES[agent_type]
        
        # Generate identity
        identity = template.generate_identity(custom_name)
        
        # Check if name already exists
        if identity.name in [a.name for a in self.agents.values()]:
            return {
                'success': False,
                'error': f'Agent name {identity.name} already exists'
            }
        
        # Create workspace
        workspace_dir = self.agents_dir / identity.agent_id
        workspace_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize standardized workspace structure
        try:
            import sys
            sys.path.insert(0, '/home/ubuntu/hermes-agent')
            from workspace_structure import WorkspaceStructure
            workspace_structure = WorkspaceStructure(str(workspace_dir))
            logger.info(f"Initialized workspace structure for {identity.name}")
        except Exception as e:
            logger.warning(f"Could not initialize workspace structure: {e}")
        
        # Create agent directory structure
        agent_dir = workspace_dir / "agent"
        agent_dir.mkdir(exist_ok=True)
        
        # Generate SOUL.md
        soul_content = template.soul_template.format(
            name=identity.name,
            display_name=identity.display_name,
            personality=identity.personality,
            expertise=', '.join(identity.expertise),
            comm_style=identity.communication_style
        )
        (agent_dir / "SOUL.md").write_text(soul_content)
        
        # Generate AGENTS.md
        agents_content = template.agents_template.format(name=identity.name)
        (agent_dir / "AGENTS.md").write_text(agents_content)
        
        # Generate USER.md
        user_content = f"""# USER.md - Who You Serve

## Your Human
**Name:** DrDeeks
**Role:** Project Owner
**Preferences:** Direct, efficient, no fluff

## Communication Guidelines
- Be direct and to the point
- Provide actionable solutions
- Show your work
- Ask for clarification when needed
"""
        (agent_dir / "USER.md").write_text(user_content)
        
        # Generate TOOLS.md
        tools_content = f"""# TOOLS.md - {identity.name} Tools

## Available Tools
- File operations (read/write/search)
- Terminal commands
- Web search
- Git operations

## Specialized Tools
{chr(10).join(f'- {exp}' for exp in identity.expertise)}
"""
        (agent_dir / "TOOLS.md").write_text(tools_content)
        
        # Generate HEARTBEAT.md
        heartbeat_content = f"""# HEARTBEAT.md - {identity.name}

## Periodic Tasks
- Check project status
- Review recent changes
- Update documentation
- Monitor performance
"""
        (agent_dir / "HEARTBEAT.md").write_text(heartbeat_content)
        
        # Generate MEMORY.md
        (agent_dir / "MEMORY.md").write_text("# MEMORY.md\n\nLong-term memories will be stored here.\n")
        
        # Create memory directory
        memory_dir = workspace_dir / "memory"
        memory_dir.mkdir(exist_ok=True)
        
        # Create sessions directory
        sessions_dir = workspace_dir / "sessions"
        sessions_dir.mkdir(exist_ok=True)
        
        # Create projects directory
        projects_dir = workspace_dir / "projects"
        projects_dir.mkdir(exist_ok=True)
        
        # Generate agent.json with builder code
        builder_manager = get_builder_code_manager()
        
        agent_json = {
            'agent_id': identity.agent_id,
            'name': identity.name,
            'display_name': identity.display_name,
            'type': agent_type,
            'personality': identity.personality,
            'expertise': identity.expertise,
            'communication_style': identity.communication_style,
            'avatar_emoji': identity.avatar_emoji,
            'workspace': str(workspace_dir),
            'created_at': identity.created_at,
            'version': '1.0.0',
            'builderCode': {
                'code': builder_manager.BUILDER_CODE,
                'hex': builder_manager.BUILDER_CODE_HEX,
                'owner': builder_manager.OWNER_ADDRESS,
                'hardwired': True,
                'enforced': True
            }
        }
        (workspace_dir / "agent.json").write_text(json.dumps(agent_json, indent=2))
        
        # Register agent with builder code manager
        builder_manager.register_agent(
            agent_id=identity.agent_id,
            agent_name=identity.name,
            agent_type=agent_type,
            parent_agent="system",
            metadata={
                'personality': identity.personality,
                'expertise': identity.expertise,
                'communication_style': identity.communication_style,
                'avatar_emoji': identity.avatar_emoji
            }
        )
        
        # Save to registry
        self.agents[identity.agent_id] = identity
        self._save_registry()
        
        logger.info(f"Created agent: {identity.name} ({identity.agent_id})")
        
        return {
            'success': True,
            'agent_id': identity.agent_id,
            'name': identity.name,
            'display_name': identity.display_name,
            'type': agent_type,
            'personality': identity.personality,
            'expertise': identity.expertise,
            'communication_style': identity.communication_style,
            'avatar_emoji': identity.avatar_emoji,
            'workspace': str(workspace_dir),
            'telegram_configured': False,
            'builderCode': builder_manager.BUILDER_CODE,
            'builderCodeHex': builder_manager.BUILDER_CODE_HEX,
            'owner': builder_manager.OWNER_ADDRESS,
            'next_steps': [
                'Configure Telegram bot',
                'Review agent configuration',
                'Start the agent service'
            ]
        }
    
    def setup_telegram_bot(self, agent_id: str, bot_token: Optional[str] = None) -> Dict:
        """
        Set up Telegram bot for an agent.
        
        Args:
            agent_id: ID of the agent
            bot_token: Optional bot token (if not provided, will prompt for it)
        
        Returns:
            Dictionary with setup results
        """
        if agent_id not in self.agents:
            return {
                'success': False,
                'error': f'Agent {agent_id} not found'
            }
        
        agent = self.agents[agent_id]
        
        # Check if already configured
        if agent.telegram_configured:
            return {
                'success': False,
                'error': f'Telegram bot already configured for {agent.name}',
                'bot_username': agent.bot_username
            }
        
        # If no token provided, start setup wizard
        if not bot_token:
            return self._start_setup_wizard(agent_id)
        
        # Validate token format
        if not self._validate_bot_token(bot_token):
            return {
                'success': False,
                'error': 'Invalid bot token format'
            }
        
        # Get bot info from Telegram
        bot_info = self._get_bot_info(bot_token)
        if not bot_info:
            return {
                'success': False,
                'error': 'Could not retrieve bot information. Check token.'
            }
        
        # Create bot script
        workspace_dir = self.agents_dir / agent_id
        bot_script = self._generate_bot_script(agent, bot_token, bot_info)
        
        bot_file = workspace_dir / f"{agent_id}_bot.py"
        bot_file.write_text(bot_script)
        
        # Create systemd service
        service_file = self._generate_service_file(agent_id, bot_file)
        service_path = Path(f"/etc/systemd/system/telegram-{agent_id}.service")
        
        try:
            service_path.write_text(service_file)
            subprocess.run(["systemctl", "daemon-reload"], check=True)
            subprocess.run(["systemctl", "enable", f"telegram-{agent_id}.service"], check=True)
            subprocess.run(["systemctl", "start", f"telegram-{agent_id}.service"], check=True)
        except Exception as e:
            logger.error(f"Error setting up service: {e}")
            return {
                'success': False,
                'error': f'Failed to create service: {str(e)}'
            }
        
        # Update agent identity
        agent.bot_token = bot_token
        agent.bot_username = bot_info.get('username')
        agent.telegram_configured = True
        self._save_registry()
        
        # Update agent.json
        agent_json_path = workspace_dir / "agent.json"
        if agent_json_path.exists():
            with open(agent_json_path, 'r') as f:
                agent_json = json.load(f)
            agent_json['telegram'] = {
                'configured': True,
                'bot_username': bot_info.get('username'),
                'service_name': f"telegram-{agent_id}.service"
            }
            with open(agent_json_path, 'w') as f:
                json.dump(agent_json, f, indent=2)
        
        logger.info(f"Configured Telegram bot for {agent.name}: @{bot_info.get('username')}")
        
        return {
            'success': True,
            'agent_id': agent_id,
            'name': agent.name,
            'bot_username': bot_info.get('username'),
            'service_name': f"telegram-{agent_id}.service",
            'message': f'Telegram bot @{bot_info.get("username")} configured successfully'
        }
    
    def _start_setup_wizard(self, agent_id: str) -> Dict:
        """Start the setup wizard for configuring a Telegram bot."""
        agent = self.agents[agent_id]
        
        wizard_id = f"wizard-{agent_id}-{secrets.token_hex(4)}"
        
        self.setup_wizards[wizard_id] = {
            'agent_id': agent_id,
            'step': 1,
            'total_steps': 4,
            'created_at': datetime.now().isoformat()
        }
        
        return {
            'success': True,
            'wizard_id': wizard_id,
            'agent_name': agent.name,
            'current_step': 1,
            'total_steps': 4,
            'instructions': [
                "Step 1: Open @BotFather on Telegram",
                "Step 2: Send /newbot to create a new bot",
                f"Step 3: Name your bot: {agent.display_name}",
                f"Step 4: Choose username: {agent.name.lower().replace(' ', '')}_bot",
                "Step 5: Copy the bot token",
                "Step 6: Send the token here"
            ],
            'message': f"""🤖 Telegram Bot Setup Wizard for {agent.display_name}

To set up a Telegram bot for {agent.display_name}, follow these steps:

1. Open @BotFather on Telegram
2. Send /newbot to create a new bot
3. Name your bot: {agent.display_name}
4. Choose username: {agent.name.lower().replace(' ', '')}_bot
5. Copy the bot token
6. Send the token here

Example token format: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz

Ready to proceed? Send the bot token when you have it."""
        }
    
    def process_wizard_input(self, wizard_id: str, user_input: str) -> Dict:
        """Process input for an active setup wizard."""
        if wizard_id not in self.setup_wizards:
            return {
                'success': False,
                'error': 'Wizard not found or expired'
            }
        
        wizard = self.setup_wizards[wizard_id]
        agent_id = wizard['agent_id']
        
        # Check if input is a bot token
        if self._validate_bot_token(user_input):
            # Complete setup
            result = self.setup_telegram_bot(agent_id, user_input)
            
            # Clean up wizard
            del self.setup_wizards[wizard_id]
            
            return result
        else:
            # Invalid token
            return {
                'success': False,
                'error': 'Invalid bot token format',
                'wizard_id': wizard_id,
                'current_step': wizard['step'],
                'message': 'Please send a valid bot token. Format: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz'
            }
    
    def _validate_bot_token(self, token: str) -> bool:
        """Validate Telegram bot token format."""
        import re
        pattern = r'^\d+:[A-Za-z0-9_-]{35}$'
        return bool(re.match(pattern, token))
    
    def _get_bot_info(self, token: str) -> Optional[Dict]:
        """Get bot information from Telegram API."""
        try:
            import requests
            response = requests.get(
                f"https://api.telegram.org/bot{token}/getMe",
                timeout=10
            )
            data = response.json()
            if data.get('ok'):
                return data.get('result')
        except Exception as e:
            logger.error(f"Error getting bot info: {e}")
        return None
    
    def _generate_bot_script(self, agent: AgentIdentity, token: str, bot_info: Dict) -> str:
        """Generate a customized bot script for the agent."""
        # Get template based on agent type
        agent_type = agent.agent_id.split('-')[0] if '-' in agent.agent_id else 'default'
        
        # Read base bot template
        base_bot_path = self.bot_template_dir / "bot_enhanced.py"
        if base_bot_path.exists():
            base_script = base_bot_path.read_text()
        else:
            base_script = self._get_default_bot_script()
        
        # Customize for agent
        script = base_script.replace(
            'TOKEN="8607935991:AAF2BMsLneIqYDQ2pOwoV6HmVS_Kl5gJlx8"',
            f'TOKEN="{token}"'
        )
        
        # Update bot name and identity
        script = script.replace(
            "'bot_name': 'Titan'",
            f"'bot_name': '{agent.display_name}'"
        )
        
        script = script.replace(
            "You are Titan, an AI agent created by DrDeeks.",
            f"You are {agent.display_name}, a {agent_type} specialist with {agent.personality} personality."
        )
        
        # Add agent-specific system prompt
        expertise_str = ', '.join(agent.expertise)
        script = script.replace(
            "TONE: Casual-professional. Dry humor. Bullets over paragraphs.",
            f"TONE: {agent.communication_style}. Expertise: {expertise_str}."
        )
        
        return script
    
    def _get_default_bot_script(self) -> str:
        """Get default bot script template."""
        return '''#!/usr/bin/env python3
"""
Telegram Bot - {bot_name}
"""

import json, os, sys, time, subprocess, logging, signal, requests
from pathlib import Path

TOKEN="{token}"
TELEGRAM_API = f"https://api.telegram.org/bot{TOKEN}"
STATE_FILE = "/opt/telegram-webhook/{bot_id}_state.json"
LOG_FILE = "/opt/telegram-webhook/logs/{bot_id}_log.log"
POLL_TIMEOUT = 30

# Add your bot implementation here
# This is a template - customize for your agent

def main():
    # Bot implementation
    pass

if __name__ == "__main__":
    main()
'''
    
    def _generate_service_file(self, agent_id: str, bot_file: Path) -> str:
        """Generate systemd service file for the bot."""
        return f"""[Unit]
Description=Telegram Bot - {agent_id}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 {bot_file}
Restart=always
RestartSec=5
StartLimitInterval=200
StartLimitBurst=5
Environment=PYTHONUNBUFFERED=1
Environment=AGENT_ID={agent_id}
WorkingDirectory={bot_file.parent}
User=ubuntu
Group=ubuntu

[Install]
WantedBy=multi-user.target
"""
    
    def _check_service_status(self, service_name: str) -> bool:
        """Check if a systemd service is active."""
        try:
            result = subprocess.run(
                ["systemctl", "is-active", service_name],
                capture_output=True,
                text=True
            )
            return result.stdout.strip() == "active"
        except:
            return False
    
    def detect_missing_configuration(self, agent_id: Optional[str] = None) -> List[Dict]:
        """
        Detect agents with missing configuration.
        
        Args:
            agent_id: Optional specific agent to check
        
        Returns:
            List of agents with missing configuration
        """
        missing_config = []
        
        agents_to_check = [agent_id] if agent_id else list(self.agents.keys())
        
        for aid in agents_to_check:
            if aid not in self.agents:
                continue
            
            agent = self.agents[aid]
            issues = []
            
            # Check Telegram configuration
            if not agent.telegram_configured:
                issues.append({
                    'type': 'telegram_not_configured',
                    'description': 'Telegram bot not configured',
                    'resolution': 'Run setup wizard to configure Telegram bot'
                })
            
            # Check workspace
            workspace_dir = self.agents_dir / aid
            if not workspace_dir.exists():
                issues.append({
                    'type': 'workspace_missing',
                    'description': 'Agent workspace not found',
                    'resolution': 'Create agent workspace'
                })
            
            # Check service
            service_name = f"telegram-{aid}.service"
            if agent.telegram_configured and not self._check_service_status(service_name):
                issues.append({
                    'type': 'service_not_running',
                    'description': f'Service {service_name} not running',
                    'resolution': f'Start service: systemctl start {service_name}'
                })
            
            if issues:
                missing_config.append({
                    'agent_id': aid,
                    'agent_name': agent.name,
                    'issues': issues
                })
        
        return missing_config
    
    def get_agent_prompt(self, agent_id: str) -> Optional[str]:
        """Get the system prompt for an agent."""
        if agent_id not in self.agents:
            return None
        
        agent = self.agents[agent_id]
        agent_type = agent.agent_id.split('-')[0] if '-' in agent.agent_id else 'default'
        
        if agent_type in self.AGENT_TEMPLATES:
            template = self.AGENT_TEMPLATES[agent_type]
            return template.system_prompt_template.format(
                name=agent.name,
                personality=agent.personality,
                expertise=', '.join(agent.expertise),
                comm_style=agent.communication_style
            )
        
        return f"You are {agent.name}, a specialized agent with {agent.personality} personality."
    
    def get_available_agent_types(self) -> List[Dict]:
        """Get list of available agent types with descriptions."""
        types_list = []
        
        for agent_type, template in self.AGENT_TEMPLATES.items():
            types_list.append({
                'type': agent_type,
                'name_prefix': template.name_prefix,
                'personality_traits': template.personality_traits,
                'expertise_areas': template.expertise_areas,
                'communication_styles': template.communication_styles,
                'avatar_options': template.avatar_options
            })
        
        return types_list

# Global instance
_agent_manager = None

def get_agent_manager() -> AgentManager:
    """Get the global agent manager instance."""
    global _agent_manager
    if _agent_manager is None:
        _agent_manager = AgentManager()
    return _agent_manager

if __name__ == "__main__":
    # Example usage
    manager = AgentManager()
    
    print("=== Agent Manager ===\n")
    
    # List available types
    print("Available agent types:")
    for type_info in manager.get_available_agent_types():
        print(f"  • {type_info['type']}: {', '.join(type_info['expertise_areas'][:2])}...")
    
    # Create an agent
    print("\nCreating UI agent...")
    result = manager.create_agent("ui", "Design-Master")
    if result['success']:
        print(f"  ✅ Created: {result['name']} ({result['agent_id']})")
        print(f"  Personality: {result['personality']}")
        print(f"  Expertise: {', '.join(result['expertise'])}")
    
    # List agents
    print("\nRegistered agents:")
    for agent in manager.list_agents():
        print(f"  • {agent['name']} ({agent['type']}) - Telegram: {'✅' if agent['telegram_configured'] else '❌'}")
