#!/usr/bin/env python3
"""
Lead Agent - The manager and coordinator for autonomous crews.
Responsible for creating, configuring, and managing specialized agents.
"""

import json
import os
import sys
import logging
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Any

# Import agent manager
sys.path.insert(0, str(Path(__file__).parent))
from agent_manager import get_agent_manager, AgentManager

logger = logging.getLogger(__name__)

class LeadAgent:
    """
    Lead Agent acts as the manager for autonomous crews.
    Responsibilities:
    - Create and configure specialized agents
    - Manage agent lifecycle
    - Coordinate crew workflows
    - Ensure proper agent configuration
    - Guide setup processes
    """
    
    def __init__(self):
        self.agent_manager = get_agent_manager()
        self.active_crews: Dict[str, Dict] = {}
        self.setup_sessions: Dict[str, Dict] = {}
    
    # ============================================
    # AGENT MANAGEMENT COMMANDS
    # ============================================
    
    def list_agents(self, filter_type: Optional[str] = None) -> str:
        """List all agents with their status."""
        agents = self.agent_manager.list_agents(filter_type)
        
        if not agents:
            return """📋 No Agents Found

No agents have been created yet.

💡 To create your first agent:
   /agent create <type> [name]

Available types:
  • ui - UI/UX Specialist
  • integration - Integration Architect
  • blockchain - Blockchain & Security
  • debugger - Debugger
  • documentation - Documentation Specialist
  • optimization - Optimization Expert
  • architecture - Organizational Architect
  • validation - Validation Expert
"""
        
        response = "📋 Agent Registry\n\n"
        
        # Group by type
        by_type = {}
        for agent in agents:
            agent_type = agent['type']
            if agent_type not in by_type:
                by_type[agent_type] = []
            by_type[agent_type].append(agent)
        
        for agent_type, type_agents in sorted(by_type.items()):
            response += f"🏷️ {agent_type.upper()} Agents:\n"
            
            for agent in type_agents:
                telegram_status = "✅" if agent['telegram_configured'] else "❌"
                response += f"  {agent['avatar_emoji'] if 'avatar_emoji' in agent else '🤖'} {agent['name']}\n"
                response += f"     ID: {agent['agent_id']}\n"
                response += f"     Personality: {agent['personality']}\n"
                response += f"     Telegram: {telegram_status}\n"
                response += f"     Created: {agent['created_at'][:10]}\n\n"
        
        response += f"📊 Total: {len(agents)} agents\n"
        response += f"✅ Configured: {sum(1 for a in agents if a['telegram_configured'])}\n"
        response += f"❌ Needs Setup: {sum(1 for a in agents if not a['telegram_configured'])}"
        
        return response
    
    def get_agent_details(self, agent_id: str) -> str:
        """Get detailed information about a specific agent."""
        details = self.agent_manager.get_agent_details(agent_id)
        
        if not details:
            return f"❌ Agent '{agent_id}' not found.\n\nUse /agent list to see all agents."
        
        response = f"🤖 Agent Details: {details['display_name']}\n\n"
        
        response += f"🆔 Identity:\n"
        response += f"  • ID: {details['agent_id']}\n"
        response += f"  • Name: {details['name']}\n"
        response += f"  • Display Name: {details['display_name']}\n"
        response += f"  • Emoji: {details['avatar_emoji']}\n\n"
        
        response += f"🧠 Personality & Expertise:\n"
        response += f"  • Personality: {details['personality']}\n"
        response += f"  • Communication: {details['communication_style']}\n"
        response += f"  • Expertise:\n"
        for exp in details['expertise']:
            response += f"    - {exp}\n"
        
        response += f"\n📱 Telegram Configuration:\n"
        if details['telegram_configured']:
            response += f"  • Status: ✅ Configured\n"
            response += f"  • Bot: @{details['bot_username']}\n"
            response += f"  • Service: {details['service_name']}\n"
            response += f"  • Running: {'✅' if details['service_active'] else '❌'}\n"
        else:
            response += f"  • Status: ❌ Not configured\n"
            response += f"  • Action: Run /agent setup {agent_id}\n"
        
        response += f"\n📁 Workspace:\n"
        if details['workspace_exists']:
            response += f"  • Path: {details['workspace_path']}\n"
            response += f"  • Status: ✅ Exists\n"
        else:
            response += f"  • Status: ❌ Missing\n"
        
        response += f"\n📅 Created: {details['created_at']}"
        
        return response
    
    def create_agent(self, agent_type: str, custom_name: Optional[str] = None) -> str:
        """Create a new specialized agent."""
        result = self.agent_manager.create_agent(agent_type, custom_name)
        
        if not result['success']:
            error_msg = result.get('error', 'Unknown error')
            if 'available_types' in result:
                types = ', '.join(result['available_types'])
                return f"❌ {error_msg}\n\nAvailable types: {types}"
            return f"❌ {error_msg}"
        
        response = f"✅ Agent Created Successfully!\n\n"
        response += f"🤖 {result['display_name']} ({result['avatar_emoji']})\n\n"
        
        response += f"🆔 Identity:\n"
        response += f"  • ID: {result['agent_id']}\n"
        response += f"  • Name: {result['name']}\n"
        response += f"  • Type: {result['type']}\n\n"
        
        response += f"🧠 Characteristics:\n"
        response += f"  • Personality: {result['personality']}\n"
        response += f"  • Communication: {result['communication_style']}\n"
        response += f"  • Expertise:\n"
        for exp in result['expertise']:
            response += f"    - {exp}\n"
        
        response += f"\n📁 Workspace: {result['workspace']}\n"
        
        response += f"\n📋 Next Steps:\n"
        for i, step in enumerate(result['next_steps'], 1):
            response += f"  {i}. {step}\n"
        
        response += f"\n💡 To set up Telegram bot:\n"
        response += f"   /agent setup {result['agent_id']}"
        
        return response
    
    def setup_agent_telegram(self, agent_id: str, bot_token: Optional[str] = None) -> str:
        """Set up Telegram bot for an agent."""
        # Check if agent exists
        details = self.agent_manager.get_agent_details(agent_id)
        if not details:
            return f"❌ Agent '{agent_id}' not found.\n\nUse /agent list to see all agents."
        
        # Check if already configured
        if details['telegram_configured']:
            return f"✅ Telegram bot already configured for {details['display_name']}\n\n"
            f"Bot: @{details['bot_username']}\n"
            f"Service: {details['service_name']}\n"
            f"Running: {'Yes' if details['service_active'] else 'No'}"
        
        # If token provided, set up directly
        if bot_token:
            result = self.agent_manager.setup_telegram_bot(agent_id, bot_token)
            
            if result['success']:
                return f"✅ Telegram Bot Configured!\n\n"
                f"🤖 {details['display_name']}\n"
                f"📱 Bot: @{result['bot_username']}\n"
                f"🔧 Service: {result['service_name']}\n\n"
                f"The bot is now running and ready to use!"
            else:
                return f"❌ Setup failed: {result.get('error', 'Unknown error')}"
        
        # Start setup wizard
        result = self.agent_manager.setup_telegram_bot(agent_id)
        
        if result.get('wizard_id'):
            # Store wizard session
            self.setup_sessions[result['wizard_id']] = {
                'agent_id': agent_id,
                'agent_name': details['display_name'],
                'created_at': datetime.now().isoformat()
            }
            
            response = f"🧙 Telegram Bot Setup Wizard\n\n"
            response += f"Setting up bot for: {details['display_name']}\n\n"
            response += f"📋 Steps:\n"
            for instruction in result['instructions']:
                response += f"  {instruction}\n"
            response += f"\n💬 Send the bot token when you have it.\n"
            response += f"Example: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
            
            return response
        
        return f"❌ Could not start setup wizard: {result.get('error', 'Unknown error')}"
    
    def process_setup_input(self, user_input: str) -> str:
        """Process input during setup wizard."""
        # Find active wizard
        wizard_id = None
        for wid, session in self.setup_sessions.items():
            wizard_id = wid
            break
        
        if not wizard_id:
            return "❌ No active setup wizard. Use /agent setup <agent_id> to start."
        
        result = self.agent_manager.process_wizard_input(wizard_id, user_input)
        
        if result['success']:
            # Clean up session
            if wizard_id in self.setup_sessions:
                del self.setup_sessions[wizard_id]
            
            if 'bot_username' in result:
                return f"✅ Setup Complete!\n\n"
                f"🤖 {result.get('agent_name', 'Agent')}\n"
                f"📱 Bot: @{result['bot_username']}\n"
                f"🔧 Service: {result['service_name']}\n\n"
                f"The bot is now running!"
            else:
                return f"✅ {result.get('message', 'Setup completed')}"
        else:
            return f"❌ {result.get('error', 'Setup failed')}\n\n"
            f"{result.get('message', '')}"
    
    def detect_issues(self, agent_id: Optional[str] = None) -> str:
        """Detect agents with missing configuration."""
        issues = self.agent_manager.detect_missing_configuration(agent_id)
        
        if not issues:
            return "✅ All agents are properly configured!"
        
        response = "⚠️ Configuration Issues Detected\n\n"
        
        for agent_issues in issues:
            response += f"🤖 {agent_issues['agent_name']} ({agent_issues['agent_id']})\n"
            
            for issue in agent_issues['issues']:
                response += f"  ❌ {issue['description']}\n"
                response += f"     Resolution: {issue['resolution']}\n"
            
            response += "\n"
        
        response += "💡 To fix, use:\n"
        response += "  • /agent setup <agent_id> - Configure Telegram\n"
        response += "  • /agent create <type> - Create new agent"
        
        return response
    
    def get_agent_types(self) -> str:
        """Get available agent types with descriptions."""
        types = self.agent_manager.get_available_agent_types()
        
        response = "🏷️ Available Agent Types\n\n"
        
        for type_info in types:
            response += f"**{type_info['type'].upper()}** ({type_info['name_prefix']})\n"
            response += f"  Expertise: {', '.join(type_info['expertise_areas'][:3])}...\n"
            response += f"  Personality: {', '.join(type_info['personality_traits'][:2])}...\n"
            response += f"  Avatars: {' '.join(type_info['avatar_options'])}\n\n"
        
        response += "💡 Create an agent with:\n"
        response += "  /agent create <type> [name]\n\n"
        response += "Example: /agent create ui Design-Master"
        
        return response
    
    def get_agent_prompt(self, agent_id: str) -> str:
        """Get the system prompt for an agent."""
        prompt = self.agent_manager.get_agent_prompt(agent_id)
        
        if not prompt:
            return f"❌ Agent '{agent_id}' not found."
        
        details = self.agent_manager.get_agent_details(agent_id)
        
        response = f"📝 System Prompt for {details['display_name']}\n\n"
        response += "```\n"
        response += prompt
        response += "\n```\n\n"
        response += f"This prompt is automatically used when the agent starts."
        
        return response

# Global instance
_lead_agent = None

def get_lead_agent() -> LeadAgent:
    """Get the global lead agent instance."""
    global _lead_agent
    if _lead_agent is None:
        _lead_agent = LeadAgent()
    return _lead_agent

if __name__ == "__main__":
    # Example usage
    lead = LeadAgent()
    
    print("=== Lead Agent Manager ===\n")
    
    # List available types
    print(lead.get_agent_types())
    
    # Create an agent
    print("\n" + lead.create_agent("ui", "Design-Master"))
    
    # List agents
    print("\n" + lead.list_agents())
