"""
Memory Synthesis Engine - Continuous memory processing and consolidation.

Converts conversation data into structured long-term memory.
"""

import asyncio
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from hermes_constants import get_hermes_home

logger = logging.getLogger(__name__)


class MemorySynthesisEngine:
    """Synthesizes and consolidates memories."""
    
    def __init__(self, hermes_home: Optional[Path] = None):
        self.hermes_home = hermes_home or get_hermes_home()
        self.memory_dir = self.hermes_home / 'memory'
        self.memory_dir.mkdir(parents=True, exist_ok=True)
        
        self.short_term_file = self.memory_dir / 'short_term.json'
        self.long_term_file = self.memory_dir / 'long_term.json'
        self.summaries_file = self.memory_dir / 'summaries.json'
        
        self._init_memory_files()
        
    def _init_memory_files(self):
        """Initialize memory files if they don't exist."""
        for file_path in [self.short_term_file, self.long_term_file, self.summaries_file]:
            if not file_path.exists():
                with open(file_path, 'w') as f:
                    json.dump([], f)
                    
    def add_short_term_memory(self, memory: Dict):
        """Add memory to short-term storage."""
        memory_entry = {
            **memory,
            'timestamp': datetime.now().isoformat(),
            'priority': memory.get('priority', 'normal')
        }
        
        memories = self._load_memories(self.short_term_file)
        memories.append(memory_entry)
        
        if len(memories) > 100:
            memories = memories[-100:]
            
        self._save_memories(self.short_term_file, memories)
        logger.debug(f"Added short-term memory: {memory.get('type', 'unknown')}")
        
    def consolidate_to_long_term(self, threshold: int = 10):
        """Consolidate important short-term memories to long-term."""
        short_term = self._load_memories(self.short_term_file)
        long_term = self._load_memories(self.long_term_file)
        
        to_consolidate = []
        
        for memory in short_term:
            if memory.get('priority') == 'high':
                to_consolidate.append(memory)
            elif memory.get('access_count', 0) >= threshold:
                to_consolidate.append(memory)
                
        for memory in to_consolidate:
            long_term_entry = {
                **memory,
                'consolidated_at': datetime.now().isoformat(),
                'source': 'short_term'
            }
            long_term.append(long_term_entry)
            
            short_term = [m for m in short_term if m != memory]
            
        self._save_memories(self.long_term_file, long_term)
        self._save_memories(self.short_term_file, short_term)
        
        logger.info(f"Consolidated {len(to_consolidate)} memories to long-term")
        return len(to_consolidate)
        
    def create_summary(self, memories: List[Dict], topic: str) -> Dict:
        """Create a memory summary from multiple memories."""
        summary = {
            'id': f"summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            'topic': topic,
            'created_at': datetime.now().isoformat(),
            'memory_count': len(memories),
            'key_points': self._extract_key_points(memories),
            'patterns': self._identify_memory_patterns(memories),
            'learnings': self._extract_learnings(memories)
        }
        
        summaries = self._load_memories(self.summaries_file)
        summaries.append(summary)
        self._save_memories(self.summaries_file, summaries)
        
        logger.info(f"Created summary: {topic} ({len(memories)} memories)")
        return summary
        
    def _extract_key_points(self, memories: List[Dict]) -> List[str]:
        """Extract key points from memories."""
        key_points = []
        
        for memory in memories[:20]:
            content = memory.get('content', '')
            if content and len(content) > 10:
                key_points.append(content[:200])
                
        return key_points[:10]
        
    def _identify_memory_patterns(self, memories: List[Dict]) -> List[Dict]:
        """Identify patterns across memories."""
        patterns = []
        type_counts = {}
        
        for memory in memories:
            mtype = memory.get('type', 'unknown')
            type_counts[mtype] = type_counts.get(mtype, 0) + 1
            
        for mtype, count in type_counts.items():
            if count >= 3:
                patterns.append({
                    'type': mtype,
                    'frequency': count,
                    'significance': 'high' if count > 10 else 'medium'
                })
                
        return patterns
        
    def _extract_learnings(self, memories: List[Dict]) -> List[str]:
        """Extract learnings from memories."""
        learnings = []
        
        for memory in memories:
            if memory.get('type') == 'learning':
                learnings.append(memory.get('content', '')[:200])
                
        return learnings[:5]
        
    def _load_memories(self, file_path: Path) -> List[Dict]:
        """Load memories from file."""
        if not file_path.exists():
            return []
            
        try:
            with open(file_path) as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load memories from {file_path}: {e}")
            return []
            
    def _save_memories(self, file_path: Path, memories: List[Dict]):
        """Save memories to file."""
        try:
            with open(file_path, 'w') as f:
                json.dump(memories, f, indent=2)
        except Exception as e:
            logger.error(f"Failed to save memories to {file_path}: {e}")
            
    def search_memories(self, query: str, limit: int = 10) -> List[Dict]:
        """Search memories by content."""
        all_memories = (
            self._load_memories(self.short_term_file) +
            self._load_memories(self.long_term_file)
        )
        
        query_lower = query.lower()
        matches = []
        
        for memory in all_memories:
            content = memory.get('content', '').lower()
            if query_lower in content:
                matches.append(memory)
                
        return matches[:limit]
        
    def get_memory_stats(self) -> Dict:
        """Get memory statistics."""
        short_term = self._load_memories(self.short_term_file)
        long_term = self._load_memories(self.long_term_file)
        summaries = self._load_memories(self.summaries_file)
        
        return {
            'short_term_count': len(short_term),
            'long_term_count': len(long_term),
            'summary_count': len(summaries),
            'total_memories': len(short_term) + len(long_term)
        }


class MemoryWriter:
    """Continuous memory writer - writes memories on every message."""
    
    def __init__(self, engine: MemorySynthesisEngine):
        self.engine = engine
        self.write_count = 0
        
    def write_message_memory(self, message: Dict, session_id: str):
        """Write a message to memory."""
        memory = {
            'type': 'message',
            'session_id': session_id,
            'role': message.get('role', 'unknown'),
            'content': message.get('content', '')[:1000],
            'timestamp': datetime.now().isoformat()
        }
        
        self.engine.add_short_term_memory(memory)
        self.write_count += 1
        
        if self.write_count % 10 == 0:
            logger.debug(f"Memory write count: {self.write_count}")
            
    def write_event_memory(self, event_type: str, event_data: Dict, priority: str = 'normal'):
        """Write an event to memory."""
        memory = {
            'type': 'event',
            'event_type': event_type,
            'data': event_data,
            'priority': priority,
            'timestamp': datetime.now().isoformat()
        }
        
        self.engine.add_short_term_memory(memory)
