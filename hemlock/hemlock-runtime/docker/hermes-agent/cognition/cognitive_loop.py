"""
Cognitive Loop Coordinator - Orchestrates continuous cognition.

Coordinates reflection, memory synthesis, skill generation, and behavior adaptation.
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from hermes_constants import get_hermes_home
from paths import resolver

logger = logging.getLogger(__name__)


class CognitiveLoopCoordinator:
    """Coordinates all cognitive processes."""
    
    def __init__(self, hermes_home: Optional[Path] = None, agents_dir: Optional[Path] = None):
        self.hermes_home = hermes_home or get_hermes_home()
        self.agents_dir = agents_dir or resolver.agents_dir
        
        from .reflection_engine import ReflectionEngine, ReflectionScheduler
        from .memory_synthesis import MemorySynthesisEngine, MemoryWriter
        from .skill_generation import SkillGenerationPipeline
        from .behavior_profiling import BehaviorProfiler, BehaviorAdaptationEngine
        
        self.reflection_engine = ReflectionEngine(self.hermes_home)
        self.memory_engine = MemorySynthesisEngine(self.hermes_home)
        self.memory_writer = MemoryWriter(self.memory_engine)
        self.skill_pipeline = SkillGenerationPipeline(self.hermes_home, self.agents_dir)
        self.behavior_profiler = BehaviorProfiler(self.hermes_home)
        self.behavior_adapter = BehaviorAdaptationEngine(self.behavior_profiler)
        
        self.running = False
        self.session_store = None
        
        self.timers = {
            'memory_write': 'every_message',
            'conversation_summary': 15,
            'reflection_pass': 45,
            'skill_generation': 300,
            'behavior_compression': 86400
        }
        
    def set_session_store(self, session_store):
        """Set session store for cognitive loop access."""
        self.session_store = session_store
        
    async def start(self):
        """Start the cognitive loop."""
        logger.info("Starting Cognitive Loop Coordinator...")
        self.running = True
        
        tasks = [
            asyncio.create_task(self._conversation_summary_loop()),
            asyncio.create_task(self._reflection_loop()),
            asyncio.create_task(self._skill_generation_loop()),
            asyncio.create_task(self._behavior_compression_loop()),
        ]
        
        try:
            await asyncio.gather(*tasks)
        except asyncio.CancelledError:
            logger.info("Cognitive loop shutting down...")
        finally:
            self.running = False
            
    def stop(self):
        """Stop the cognitive loop."""
        self.running = False
        logger.info("Cognitive loop stopped")
        
    def process_message(self, message: Dict, session_id: str):
        """Process a message through the cognitive loop."""
        self.memory_writer.write_message_memory(message, session_id)
        
        if self.session_store:
            messages = self.session_store.get_messages(session_id, limit=20)
            
            if len(messages) % 15 == 0:
                self._create_conversation_summary(session_id, messages)
                
    def _create_conversation_summary(self, session_id: str, messages: List[Dict]):
        """Create a conversation summary."""
        try:
            summary = self.memory_engine.create_summary(
                memories=[{'content': m.get('content', '')} for m in messages],
                topic=f"Session {session_id}"
            )
            logger.info(f"Created conversation summary: {summary['id']}")
        except Exception as e:
            logger.error(f"Failed to create summary: {e}")
            
    async def _conversation_summary_loop(self):
        """Periodic conversation summarization."""
        interval = self.timers['conversation_summary'] * 60
        
        while self.running:
            await asyncio.sleep(interval)
            
            try:
                if self.session_store:
                    sessions = self.session_store.list_sessions()[:5]
                    
                    for session in sessions:
                        messages = self.session_store.get_messages(session['id'], limit=30)
                        
                        if len(messages) > 10:
                            self._create_conversation_summary(session['id'], messages)
                            
            except Exception as e:
                logger.error(f"Summary loop error: {e}")
                
    async def _reflection_loop(self):
        """Periodic reflection generation."""
        interval = self.timers['reflection_pass'] * 60
        
        while self.running:
            await asyncio.sleep(interval)
            
            try:
                if self.session_store:
                    sessions = self.session_store.list_sessions()[:10]
                    
                    for session in sessions:
                        messages = self.session_store.get_messages(session['id'])
                        
                        if len(messages) > 5:
                            reflection = self.reflection_engine.generate_reflection(
                                conversation_id=session['id'],
                                messages=messages
                            )
                            
                            if reflection.get('adaptations'):
                                for adaptation in reflection['adaptations']:
                                    self.behavior_profiler.apply_adaptation(adaptation)
                                    
                self.memory_engine.consolidate_to_long_term()
                
            except Exception as e:
                logger.error(f"Reflection loop error: {e}")
                
    async def _skill_generation_loop(self):
        """Periodic skill generation analysis."""
        interval = self.timers['skill_generation']
        
        while self.running:
            await asyncio.sleep(interval)
            
            try:
                for agent_dir in self.agents_dir.iterdir():
                    if not agent_dir.is_dir() or agent_dir.name.startswith('.'):
                        continue
                        
                    agent_id = agent_dir.name
                    
                    if self.session_store:
                        sessions = self.session_store.list_sessions()
                        conversations = []
                        
                        for session in sessions[:20]:
                            messages = self.session_store.get_messages(session['id'])
                            if messages:
                                conversations.append({'messages': messages})
                                
                        potential_skills = self.skill_pipeline.analyze_for_skills(
                            conversations, agent_id
                        )
                        
                        for proposal in potential_skills[:2]:
                            skill = self.skill_pipeline.generate_skill(proposal)
                            
                            if skill:
                                validated = self.skill_pipeline.validate_skill(skill)
                                
                                if validated['status'] == 'validated':
                                    self.skill_pipeline.register_skill(validated, agent_id)
                                    
            except Exception as e:
                logger.error(f"Skill generation loop error: {e}")
                
    async def _behavior_compression_loop(self):
        """Daily behavior pattern compression."""
        interval = self.timers['behavior_compression']
        
        while self.running:
            await asyncio.sleep(interval)
            
            try:
                self.behavior_profiler.expire_old_adaptations()
                
                pattern_analysis = self.reflection_engine.analyze_patterns()
                
                logger.info(f"Behavior compression complete: {pattern_analysis}")
                
            except Exception as e:
                logger.error(f"Behavior compression error: {e}")
                
    def get_cognitive_state(self) -> Dict:
        """Get current cognitive state."""
        return {
            'running': self.running,
            'memory_stats': self.memory_engine.get_memory_stats(),
            'behavior_profile': self.behavior_profiler.get_current_profile(),
            'recent_reflections': len(self.reflection_engine.get_recent_reflections(10)),
            'active_adaptations': len(self.behavior_profiler.get_active_adaptations())
        }


class PromptAdaptationLayer:
    """Adapts prompts based on cognitive state."""
    
    def __init__(self, coordinator: CognitiveLoopCoordinator):
        self.coordinator = coordinator
        
    def adapt_prompt(self, base_prompt: str, session_id: str) -> str:
        """Adapt a prompt based on current cognitive state."""
        adaptations = self.coordinator.behavior_profiler.get_active_adaptations()
        
        adapted_prompt = base_prompt
        
        for adaptation in adaptations:
            adapt_type = adaptation.get('type', '')
            
            if adapt_type == 'reduce_length':
                adapted_prompt += "\n\n[System: Keep responses concise and focused.]"
            elif adapt_type == 'increase_detail':
                adapted_prompt += "\n\n[System: Provide detailed explanations with examples.]"
            elif adapt_type == 'increase_clarity':
                adapted_prompt += "\n\n[System: Use clear structure with numbered steps.]"
                
        return adapted_prompt
        
    def get_system_prompt(self, agent_id: str) -> str:
        """Get the current system prompt for an agent."""
        profile = self.coordinator.behavior_profiler.get_current_profile()
        
        base_prompt = f"""You are an autonomous AI agent.

Current behavioral profile:
- Verbosity: {profile['communication_style']['verbosity']}
- Formality: {profile['communication_style']['formality']}
- Directness: {profile['communication_style']['directness']}

Active adaptations: {len(profile['active_adaptations'])}

Respond naturally while maintaining your behavioral profile."""

        return base_prompt
