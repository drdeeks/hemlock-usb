"""
Behavior Profiling System - Tracks and adapts agent behavior.

Monitors behavioral patterns and suggests adaptations.
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from hermes_constants import get_hermes_home

logger = logging.getLogger(__name__)


class BehaviorProfiler:
    """Profiles and tracks agent behavior."""
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or get_hermes_home()
        self.behavior_dir = self.hermes_home / 'behavior'
        self.behavior_dir.mkdir(parents=True, exist_ok=True)
        
        self.profile_file = self.behavior_dir / 'current_profile.json'
        self.history_file = self.behavior_dir / 'history.json'
        
        self._init_profile()
        
    def _init_profile(self):
        """Initialize behavior profile."""
        if not self.profile_file.exists():
            default_profile = {
                'created_at': datetime.now().isoformat(),
                'updated_at': datetime.now().isoformat(),
                'communication_style': {
                    'verbosity': 'balanced',
                    'formality': 'neutral',
                    'directness': 'moderate'
                },
                'response_patterns': {
                    'avg_response_length': 0,
                    'question_ratio': 0,
                    'example_usage': 0
                },
                'adaptation_history': [],
                'active_adaptations': []
            }
            
            with open(self.profile_file, 'w') as f:
                json.dump(default_profile, f, indent=2)
                
    def update_from_interaction(self, messages: List[Dict], feedback: Dict = None):
        """Update behavior profile from interaction."""
        profile = self._load_profile()
        
        profile['updated_at'] = datetime.now().isoformat()
        
        response_lengths = [
            len(m.get('content', '')) 
            for m in messages 
            if m.get('role') == 'assistant'
        ]
        
        if response_lengths:
            current_avg = profile['response_patterns']['avg_response_length']
            new_avg = (current_avg * 0.9) + (sum(response_lengths) / len(response_lengths) * 0.1)
            profile['response_patterns']['avg_response_length'] = new_avg
            
        question_count = sum(
            1 for m in messages 
            if m.get('role') == 'user' and '?' in m.get('content', '')
        )
        
        profile['response_patterns']['question_ratio'] = (
            profile['response_patterns']['question_ratio'] * 0.9 +
            (question_count / max(len(messages), 1)) * 0.1
        )
        
        if feedback:
            adaptation = {
                'timestamp': datetime.now().isoformat(),
                'feedback': feedback,
                'action': self._determine_adaptation(feedback)
            }
            profile['adaptation_history'].append(adaptation)
            
            if len(profile['adaptation_history']) > 100:
                profile['adaptation_history'] = profile['adaptation_history'][-100:]
                
        self._save_profile(profile)
        
    def _determine_adaptation(self, feedback: Dict) -> Dict:
        """Determine adaptation based on feedback."""
        feedback_type = feedback.get('type', 'neutral')
        
        if feedback_type == 'too_verbose':
            return {
                'type': 'reduce_length',
                'magnitude': 0.1,
                'duration': '10_interactions'
            }
        elif feedback_type == 'too_brief':
            return {
                'type': 'increase_detail',
                'magnitude': 0.1,
                'duration': '10_interactions'
            }
        elif feedback_type == 'unclear':
            return {
                'type': 'increase_clarity',
                'magnitude': 0.2,
                'duration': '5_interactions'
            }
        else:
            return {
                'type': 'maintain',
                'magnitude': 0,
                'duration': 'ongoing'
            }
            
    def get_current_profile(self) -> Dict:
        """Get current behavior profile."""
        return self._load_profile()
        
    def get_active_adaptations(self) -> List[Dict]:
        """Get active behavioral adaptations."""
        profile = self._load_profile()
        return profile.get('active_adaptations', [])
        
    def apply_adaptation(self, adaptation: Dict):
        """Apply a behavioral adaptation."""
        profile = self._load_profile()
        
        profile['active_adaptations'].append({
            **adaptation,
            'applied_at': datetime.now().isoformat()
        })
        
        if len(profile['active_adaptations']) > 10:
            profile['active_adaptations'] = profile['active_adaptations'][-10:]
            
        self._save_profile(profile)
        logger.info(f"Applied adaptation: {adaptation.get('type', 'unknown')}")
        
    def expire_old_adaptations(self):
        """Expire old adaptations."""
        profile = self._load_profile()
        
        current_time = datetime.now()
        active = []
        
        for adaptation in profile.get('active_adaptations', []):
            applied_at = datetime.fromisoformat(adaptation.get('applied_at', ''))
            duration = adaptation.get('duration', 'ongoing')
            
            if duration == 'ongoing':
                active.append(adaptation)
            else:
                duration_parts = duration.split('_')
                if len(duration_parts) == 2:
                    count = int(duration_parts[0])
                    unit = duration_parts[1]
                    
                    elapsed = (current_time - applied_at).total_seconds()
                    max_age = count * (300 if unit == 'interactions' else 60)
                    
                    if elapsed < max_age:
                        active.append(adaptation)
                        
        profile['active_adaptations'] = active
        self._save_profile(profile)
        
    def _load_profile(self) -> Dict:
        """Load behavior profile."""
        if not self.profile_file.exists():
            self._init_profile()
            
        with open(self.profile_file) as f:
            return json.load(f)
            
    def _save_profile(self, profile: Dict):
        """Save behavior profile."""
        with open(self.profile_file, 'w') as f:
            json.dump(profile, f, indent=2)


class BehaviorAdaptationEngine:
    """Applies behavioral adaptations in real-time."""
    
    def __init__(self, profiler: BehaviorProfiler):
        self.profiler = profiler
        
    def adapt_response(self, response: str, context: Dict) -> str:
        """Adapt a response based on current behavior profile."""
        adaptations = self.profiler.get_active_adaptations()
        
        adapted_response = response
        
        for adaptation in adaptations:
            adapt_type = adaptation.get('type', '')
            
            if adapt_type == 'reduce_length':
                adapted_response = self._truncate_response(adapted_response)
            elif adapt_type == 'increase_detail':
                adapted_response = self._expand_response(adapted_response, context)
            elif adapt_type == 'increase_clarity':
                adapted_response = self._clarify_response(adapted_response)
                
        return adapted_response
        
    def _truncate_response(self, response: str) -> str:
        """Truncate response to reduce length."""
        sentences = response.split('.')
        if len(sentences) > 5:
            return '.'.join(sentences[:5]) + '.'
        return response
        
    def _expand_response(self, response: str, context: Dict) -> str:
        """Expand response with more detail."""
        expansion = "\n\nAdditional context: This is based on the current conversation patterns."
        return response + expansion
        
    def _clarify_response(self, response: str) -> str:
        """Add clarity markers to response."""
        lines = response.split('\n')
        clarified = []
        
        for i, line in enumerate(lines):
            if line.strip():
                clarified.append(f"{i+1}. {line}")
            else:
                clarified.append(line)
                
        return '\n'.join(clarified)
