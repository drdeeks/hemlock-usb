"""
OpenClaw Integration Layer

Integrates OpenClaw infrastructure with Hermes cognition.
OpenClaw HOSTS Hermes - it does NOT replace it.

Responsibility split:
- OpenClaw: Transport + Runtime + Device Pairing + Infrastructure
- Hermes: Cognition + Learning + Memory
- MCP: Inter-process coordination
- Docker: Containment + persistence
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any

from paths import resolver

logger = logging.getLogger(__name__)


class OpenClawHermesBridge:
    """Bridge between OpenClaw infrastructure and Hermes cognition."""
    
    def __init__(self, hermes_home: Optional[Path] = None, agents_dir: Optional[Path] = None):
        self.hermes_home = hermes_home or resolver.hermes_home
        self.agents_dir = agents_dir or resolver.agents_dir
        
        self.bridge_state = {
            'status': 'initializing',
            'openclaw_connected': False,
            'hermes_ready': False,
            'active_sessions': {},
            'message_queue': []
        }
        
        self._init_components_sync()
        
    def _init_components_sync(self):
        """Initialize components synchronously for immediate availability."""
        try:
            from cognition.cognitive_loop import CognitiveLoopCoordinator
            from identity.agent_identity import IdentityRestorationManager
            from gateway.session_store import SessionStore
            
            self.cognitive_coordinator = CognitiveLoopCoordinator(
                hermes_home=self.hermes_home,
                agents_dir=self.agents_dir
            )
            
            self.identity_manager = IdentityRestorationManager(agents_dir=self.agents_dir)
            self.session_store = SessionStore(hermes_home=self.hermes_home)
            
            self.cognitive_coordinator.set_session_store(self.session_store)
            
            self.bridge_state['hermes_ready'] = True
            self.bridge_state['status'] = 'ready'
            
        except Exception as e:
            logger.warning(f"Component initialization deferred: {e}")
            self.cognitive_coordinator = None
            self.identity_manager = None
            self.session_store = None
        
    async def initialize(self):
        """Initialize the bridge."""
        logger.info("Initializing OpenClaw-Hermes Bridge...")
        
        try:
            await self._init_hermes_components()
            await self._init_openclaw_transport()
            await self._init_mcp_coordination()
            
            self.bridge_state['status'] = 'ready'
            self.bridge_state['hermes_ready'] = True
            
            logger.info("OpenClaw-Hermes Bridge ready")
            
        except Exception as e:
            logger.error(f"Bridge initialization failed: {e}")
            self.bridge_state['status'] = 'error'
            raise
            
    async def _init_hermes_components(self):
        """Initialize Hermes cognition components."""
        from cognition.cognitive_loop import CognitiveLoopCoordinator
        from identity.agent_identity import IdentityRestorationManager
        from runtime.session_store import SessionStore
        
        self.cognitive_coordinator = CognitiveLoopCoordinator(
            hermes_home=self.hermes_home,
            agents_dir=self.agents_dir
        )
        
        self.identity_manager = IdentityRestorationManager(agents_dir=self.agents_dir)
        self.session_store = SessionStore(hermes_home=self.hermes_home)
        
        self.cognitive_coordinator.set_session_store(self.session_store)
        
        logger.info("Hermes components initialized")
        
    async def _init_openclaw_transport(self):
        """Initialize OpenClaw transport layer."""
        from gateway.platforms.telegram import TelegramAdapter
        from gateway.platforms.discord import DiscordAdapter
        
        self.telegram_adapter = TelegramAdapter()
        self.discord_adapter = DiscordAdapter()
        
        logger.info("OpenClaw transport initialized")
        
    async def _init_mcp_coordination(self):
        """Initialize MCP coordination."""
        try:
            from agent_brain_mcp import AgentBrainMCP
            self.mcp_brain = AgentBrainMCP()
            logger.info("MCP coordination initialized")
        except ImportError:
            logger.warning("MCP brain not available - using direct coordination")
            self.mcp_brain = None
            
    def route_message(self, platform: str, user_id: str, message: Dict) -> Dict:
        """Route incoming message through Hermes cognition."""
        session_id = f"{platform}_{user_id}"
        
        session = self.session_store.get_or_create_session(session_id)
        
        self.session_store.add_message(session_id, {
            'role': 'user',
            'content': message.get('content', ''),
            'platform': platform,
            'timestamp': datetime.now().isoformat()
        })
        
        self.cognitive_coordinator.process_message(message, session_id)
        
        response = self._generate_response(session_id, message)
        
        self.session_store.add_message(session_id, {
            'role': 'assistant',
            'content': response.get('content', ''),
            'timestamp': datetime.now().isoformat()
        })
        
        return response
        
    def _generate_response(self, session_id: str, user_message: Dict) -> Dict:
        """Generate response using Hermes cognition."""
        from cognition.cognitive_loop import PromptAdaptationLayer
        
        adapter = PromptAdaptationLayer(self.cognitive_coordinator)
        
        messages = self.session_store.get_messages(session_id, limit=20)
        
        system_prompt = adapter.get_system_prompt('jack')
        
        context = {
            'session_id': session_id,
            'messages': messages,
            'user_message': user_message
        }
        
        response_content = self._synthesize_response(system_prompt, context)
        
        adapted_content = adapter.adapt_prompt(response_content, session_id)
        
        return {
            'content': adapted_content,
            'session_id': session_id,
            'timestamp': datetime.now().isoformat(),
            'cognitive_state': self.cognitive_coordinator.get_cognitive_state()
        }
        
    def _synthesize_response(self, system_prompt: str, context: Dict) -> str:
        """Synthesize response from cognitive state."""
        messages = context.get('messages', [])
        user_message = context.get('user_message', {})
        
        if not messages:
            return "Hello! I'm ready to help."
            
        recent_context = messages[-5:] if len(messages) > 5 else messages
        
        response = f"Received: {user_message.get('content', '')[:100]}"
        
        return response
        
    def get_bridge_status(self) -> Dict:
        """Get bridge status."""
        return {
            **self.bridge_state,
            'hermes_components': {
                'cognitive_coordinator': hasattr(self, 'cognitive_coordinator'),
                'identity_manager': hasattr(self, 'identity_manager'),
                'session_store': hasattr(self, 'session_store')
            },
            'openclaw_components': {
                'telegram': hasattr(self, 'telegram_adapter'),
                'discord': hasattr(self, 'discord_adapter')
            },
            'mcp': {
                'available': hasattr(self, 'mcp_brain') and self.mcp_brain is not None
            }
        }


class OpenClawRuntimeHost:
    """OpenClaw as runtime host for Hermes."""
    
    def __init__(self):
        self.bridge = None
        self.running = False
        
    async def start(self):
        """Start OpenClaw runtime hosting Hermes."""
        logger.info("Starting OpenClaw Runtime Host...")
        
        self.bridge = OpenClawHermesBridge(
            hermes_home=Path('/runtime'),
            agents_dir=Path('/agents')
        )
        
        await self.bridge.initialize()
        
        self.running = True
        
        logger.info("OpenClaw Runtime Host started - Hermes cognition active")
        
    async def stop(self):
        """Stop the runtime host."""
        logger.info("Stopping OpenClaw Runtime Host...")
        
        self.running = False
        
        if self.bridge and self.bridge.cognitive_coordinator:
            self.bridge.cognitive_coordinator.stop()
            
        logger.info("OpenClaw Runtime Host stopped")
        
    def get_status(self) -> Dict:
        """Get runtime host status."""
        return {
            'running': self.running,
            'bridge_status': self.bridge.get_bridge_status() if self.bridge else None
        }


class TransportLayer:
    """OpenClaw transport layer for Hermes."""
    
    def __init__(self, bridge: OpenClawHermesBridge):
        self.bridge = bridge
        self.active_connections = {}
        
    async def handle_telegram_message(self, update, context):
        """Handle incoming Telegram message."""
        user_id = str(update.effective_user.id)
        message_text = update.message.text
        
        response = self.bridge.route_message(
            platform='telegram',
            user_id=user_id,
            message={'content': message_text}
        )
        
        await update.message.reply_text(response['content'])
        
    async def handle_discord_message(self, message):
        """Handle incoming Discord message."""
        user_id = str(message.author.id)
        message_text = message.content
        
        response = self.bridge.route_message(
            platform='discord',
            user_id=user_id,
            message={'content': message_text}
        )
        
        await message.channel.send(response['content'])
        
    def get_connection_stats(self) -> Dict:
        """Get connection statistics."""
        return {
            'active_connections': len(self.active_connections),
            'platforms': list(self.active_connections.keys())
        }


def create_integration_layer() -> OpenClawRuntimeHost:
    """Create the OpenClaw-Hermes integration layer."""
    return OpenClawRuntimeHost()
