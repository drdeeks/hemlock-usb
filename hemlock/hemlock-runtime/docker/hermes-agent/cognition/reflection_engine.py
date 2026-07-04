"""
Reflection Engine - Autonomous cognitive reflection system.

Generates reflections from conversations, identifies patterns,
and triggers behavioral adaptations.
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from hermes_constants import get_hermes_home

logger = logging.getLogger(__name__)


class ReflectionEngine:
    """Generates and manages cognitive reflections."""
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or get_hermes_home()
        self.reflections_dir = self.hermes_home / 'reflections'
        self.reflections_dir.mkdir(parents=True, exist_ok=True)
        
        self.patterns_memory = []
        self.last_reflection_time = None
        
    def _reflection_path(self, reflection_id: str) -> Path:
        """Get path for reflection file."""
        return self.reflections_dir / f'{reflection_id}.json'
        
    def generate_reflection(
        self,
        conversation_id: str,
        messages: List[Dict],
        context: Dict = None
    ) -> Dict:
        """Generate a reflection from conversation."""
        
        reflection_id = f"refl_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        reflection = {
            'id': reflection_id,
            'conversation_id': conversation_id,
            'timestamp': datetime.now().isoformat(),
            'type': self._classify_reflection(messages),
            'summary': self._summarize_conversation(messages),
            'patterns': self._identify_patterns(messages),
            'insights': self._generate_insights(messages),
            'adaptations': self._suggest_adaptations(messages),
            'context': context or {}
        }
        
        self._save_reflection(reflection)
        logger.info(f"Generated reflection: {reflection_id}")
        
        return reflection
        
    def _classify_reflection(self, messages: List[Dict]) -> str:
        """Classify the type of reflection."""
        if not messages:
            return 'empty'
            
        content = ' '.join([m.get('content', '') for m in messages])
        
        if 'error' in content.lower() or 'fail' in content.lower():
            return 'problem_solving'
        elif 'how' in content.lower() or 'what' in content.lower():
            return 'learning'
        elif 'task' in content.lower() or 'do' in content.lower():
            return 'task_execution'
        elif 'thank' in content.lower() or 'great' in content.lower():
            return 'positive_feedback'
        else:
            return 'general'
            
    def _summarize_conversation(self, messages: List[Dict]) -> str:
        """Generate a summary of the conversation."""
        if not messages:
            return "No conversation content"
            
        user_messages = [m for m in messages if m.get('role') == 'user']
        assistant_messages = [m for m in messages if m.get('role') == 'assistant']
        
        summary_parts = []
        
        if user_messages:
            last_user = user_messages[-1].get('content', '')[:200]
            summary_parts.append(f"User asked about: {last_user}")
            
        if assistant_messages:
            last_assistant = assistant_messages[-1].get('content', '')[:200]
            summary_parts.append(f"Assistant responded: {last_assistant}")
            
        return '. '.join(summary_parts) if summary_parts else "Conversation summary unavailable"
        
    def _identify_patterns(self, messages: List[Dict]) -> List[Dict]:
        """Identify patterns in the conversation."""
        patterns = []
        
        content = ' '.join([m.get('content', '') for m in messages])
        
        if content.count('?') > 3:
            patterns.append({
                'type': 'high_questioning',
                'description': 'User is asking many questions - may need clarification',
                'confidence': 0.8
            })
            
        if len(messages) > 20:
            patterns.append({
                'type': 'extended_conversation',
                'description': 'Long conversation - consider summarization',
                'confidence': 0.9
            })
            
        if 'code' in content.lower() or 'function' in content.lower():
            patterns.append({
                'type': 'technical_content',
                'description': 'Technical discussion detected',
                'confidence': 0.7
            })
            
        return patterns
        
    def _generate_insights(self, messages: List[Dict]) -> List[str]:
        """Generate insights from the conversation."""
        insights = []
        
        if not messages:
            return insights
            
        user_count = sum(1 for m in messages if m.get('role') == 'user')
        assistant_count = sum(1 for m in messages if m.get('role') == 'assistant')
        
        if assistant_count > user_count * 2:
            insights.append("Assistant providing very detailed responses")
            
        if user_count > 10:
            insights.append("User highly engaged in conversation")
            
        content = ' '.join([m.get('content', '') for m in messages])
        if 'sorry' in content.lower() or 'apologize' in content.lower():
            insights.append("Correction or apology occurred - review for accuracy")
            
        return insights
        
    def _suggest_adaptations(self, messages: List[Dict]) -> List[Dict]:
        """Suggest behavioral adaptations."""
        adaptations = []
        
        content = ' '.join([m.get('content', '') for m in messages])
        
        if 'confusing' in content.lower() or 'unclear' in content.lower():
            adaptations.append({
                'type': 'communication_style',
                'suggestion': 'Use clearer, more structured explanations',
                'priority': 'high'
            })
            
        if 'too long' in content.lower() or 'verbose' in content.lower():
            adaptations.append({
                'type': 'response_length',
                'suggestion': 'Provide more concise responses',
                'priority': 'medium'
            })
            
        if 'example' in content.lower() and content.count('example') > 2:
            adaptations.append({
                'type': 'teaching_style',
                'suggestion': 'User prefers examples - include more concrete demonstrations',
                'priority': 'medium'
            })
            
        return adaptations
        
    def _save_reflection(self, reflection: Dict):
        """Save reflection to persistent storage."""
        reflection_path = self._reflection_path(reflection['id'])
        
        with open(reflection_path, 'w') as f:
            json.dump(reflection, f, indent=2)
            
    def load_reflection(self, reflection_id: str) -> Optional[Dict]:
        """Load reflection from storage."""
        reflection_path = self._reflection_path(reflection_id)
        
        if not reflection_path.exists():
            return None
            
        try:
            with open(reflection_path) as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load reflection {reflection_id}: {e}")
            return None
            
    def get_recent_reflections(self, limit: int = 10) -> List[Dict]:
        """Get recent reflections."""
        reflections = []
        
        for refl_file in sorted(self.reflections_dir.glob('*.json'), reverse=True)[:limit]:
            try:
                with open(refl_file) as f:
                    reflections.append(json.load(f))
            except Exception as e:
                logger.warning(f"Failed to read reflection {refl_file}: {e}")
                
        return reflections
        
    def analyze_patterns(self, time_window: int = 60) -> Dict:
        """Analyze patterns across recent reflections."""
        recent = self.get_recent_reflections(limit=50)
        
        pattern_counts = {}
        type_counts = {}
        
        for refl in recent:
            refl_type = refl.get('type', 'unknown')
            type_counts[refl_type] = type_counts.get(refl_type, 0) + 1
            
            for pattern in refl.get('patterns', []):
                ptype = pattern.get('type', 'unknown')
                pattern_counts[ptype] = pattern_counts.get(ptype, 0) + 1
                
        return {
            'total_reflections': len(recent),
            'type_distribution': type_counts,
            'pattern_frequency': pattern_counts,
            'time_window_minutes': time_window
        }


class ReflectionScheduler:
    """Schedules periodic reflection passes."""
    
    def __init__(self, engine: ReflectionEngine, interval_minutes: int = 30):
        self.engine = engine
        self.interval = interval_minutes * 60
        self.running = False
        
    async def start(self, session_store):
        """Start periodic reflection generation."""
        self.running = True
        logger.info(f"Starting reflection scheduler (interval: {self.interval}s)")
        
        while self.running:
            await asyncio.sleep(self.interval)
            
            try:
                sessions = session_store.list_sessions()
                
                for session in sessions[:5]:
                    messages = session_store.get_messages(session['id'])
                    
                    if len(messages) > 5:
                        self.engine.generate_reflection(
                            conversation_id=session['id'],
                            messages=messages
                        )
                        
            except Exception as e:
                logger.error(f"Reflection pass failed: {e}")
                
    def stop(self):
        """Stop the scheduler."""
        self.running = False
        logger.info("Reflection scheduler stopped")
