"""
Agent Identity Restoration System

Restores and maintains individualized agent identities with:
- Identity files
- Memory graphs
- Behavior profiles
- Conversation history
- Skill inventories
- Reflection archives
- Preference memory
"""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from hermes_constants import get_hermes_home
from paths import resolver

logger = logging.getLogger(__name__)


class AgentIdentity:
    """Represents a single agent's identity."""
    
    def __init__(self, agent_id: str, agents_dir: Optional[Path] = None):
        self.agent_id = agent_id
        self.agents_dir = agents_dir or resolver.agents_dir
        self.agent_dir = self.agents_dir / agent_id
        
        self.identity_file = self.agent_dir / 'identity.md'
        self.soul_file = self.agent_dir / 'soul.md'
        self.memory_graph_file = self.agent_dir / 'memory' / 'graph.json'
        self.behavior_file = self.agent_dir / 'state' / 'behavior.json'
        self.preferences_file = self.agent_dir / 'state' / 'preferences.json'
        self.skill_inventory_file = self.agent_dir / 'skills' / 'inventory.json'
        self.reflection_archive_file = self.agent_dir / 'reflections' / 'archive.json'
        
        self._ensure_directories()
        
    def _ensure_directories(self):
        """Create agent directories if they don't exist."""
        for directory in [
            self.agent_dir,
            self.agent_dir / 'workspace',
            self.agent_dir / 'memory',
            self.agent_dir / 'skills',
            self.agent_dir / 'reflections',
            self.agent_dir / 'sessions',
            self.agent_dir / 'state'
        ]:
            directory.mkdir(parents=True, exist_ok=True)
            
    def load_identity(self) -> Optional[str]:
        """Load agent identity from file."""
        if not self.identity_file.exists():
            return None
            
        with open(self.identity_file) as f:
            return f.read()
            
    def save_identity(self, identity: str):
        """Save agent identity to file."""
        with open(self.identity_file, 'w') as f:
            f.write(identity)
        logger.info(f"Saved identity for {self.agent_id}")
        
    def load_memory_graph(self) -> Dict:
        """Load agent's memory graph."""
        if not self.memory_graph_file.exists():
            return self._create_default_memory_graph()
            
        with open(self.memory_graph_file) as f:
            return json.load(f)
            
    def save_memory_graph(self, graph: Dict):
        """Save agent's memory graph."""
        with open(self.memory_graph_file, 'w') as f:
            json.dump(graph, f, indent=2)
        logger.debug(f"Saved memory graph for {self.agent_id}")
        
    def _create_default_memory_graph(self) -> Dict:
        """Create default memory graph structure."""
        return {
            'agent_id': self.agent_id,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'nodes': [],
            'edges': [],
            'semantic_clusters': [],
            'temporal_index': []
        }
        
    def load_behavior_profile(self) -> Dict:
        """Load agent's behavior profile."""
        if not self.behavior_file.exists():
            return self._create_default_behavior()
            
        with open(self.behavior_file) as f:
            return json.load(f)
            
    def save_behavior_profile(self, profile: Dict):
        """Save agent's behavior profile."""
        profile['updated_at'] = datetime.now().isoformat()
        
        with open(self.behavior_file, 'w') as f:
            json.dump(profile, f, indent=2)
            
    def _create_default_behavior(self) -> Dict:
        """Create default behavior profile."""
        return {
            'agent_id': self.agent_id,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'communication_style': {
                'verbosity': 'balanced',
                'formality': 'neutral',
                'directness': 'moderate',
                'empathy': 'high'
            },
            'decision_making': {
                'style': 'analytical',
                'risk_tolerance': 'moderate',
                'creativity': 'balanced'
            },
            'learning_preferences': {
                'mode': 'continuous',
                'feedback_sensitivity': 'high',
                'adaptation_rate': 0.1
            },
            'interaction_history': []
        }
        
    def load_preferences(self) -> Dict:
        """Load agent's preferences."""
        if not self.preferences_file.exists():
            return self._create_default_preferences()
            
        with open(self.preferences_file) as f:
            return json.load(f)
            
    def save_preferences(self, preferences: Dict):
        """Save agent's preferences."""
        with open(self.preferences_file, 'w') as f:
            json.dump(preferences, f, indent=2)
            
    def _create_default_preferences(self) -> Dict:
        """Create default preferences."""
        return {
            'agent_id': self.agent_id,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'communication': {
                'preferred_length': 'medium',
                'include_examples': True,
                'use_formatting': True
            },
            'task_execution': {
                'auto_save': True,
                'confirm_before_execute': False,
                'verbose_logging': False
            },
            'learning': {
                'auto_skill_generation': True,
                'reflection_frequency': 'medium',
                'memory_consolidation': 'automatic'
            }
        }
        
    def load_skill_inventory(self) -> List[Dict]:
        """Load agent's skill inventory."""
        if not self.skill_inventory_file.exists():
            return []
            
        with open(self.skill_inventory_file) as f:
            return json.load(f)
            
    def save_skill_inventory(self, skills: List[Dict]):
        """Save agent's skill inventory."""
        with open(self.skill_inventory_file, 'w') as f:
            json.dump(skills, f, indent=2)
            
    def add_skill(self, skill: Dict):
        """Add a skill to inventory."""
        skills = self.load_skill_inventory()
        
        skill_entry = {
            **skill,
            'added_at': datetime.now().isoformat()
        }
        
        skills.append(skill_entry)
        self.save_skill_inventory(skills)
        logger.info(f"Added skill {skill.get('name', 'unknown')} to {self.agent_id}")
        
    def load_reflection_archive(self) -> List[Dict]:
        """Load agent's reflection archive."""
        if not self.reflection_archive_file.exists():
            return []
            
        with open(self.reflection_archive_file) as f:
            return json.load(f)
            
    def add_reflection(self, reflection: Dict):
        """Add a reflection to archive."""
        archive = self.load_reflection_archive()
        
        reflection_entry = {
            **reflection,
            'archived_at': datetime.now().isoformat()
        }
        
        archive.append(reflection_entry)
        
        if len(archive) > 1000:
            archive = archive[-1000:]
            
        with open(self.reflection_archive_file, 'w') as f:
            json.dump(archive, f, indent=2)
            
    def get_complete_state(self) -> Dict:
        """Get complete agent state."""
        return {
            'identity': self.load_identity(),
            'memory_graph': self.load_memory_graph(),
            'behavior_profile': self.load_behavior_profile(),
            'preferences': self.load_preferences(),
            'skills': self.load_skill_inventory(),
            'reflections': self.load_reflection_archive()
        }


class IdentityRestorationManager:
    """Manages restoration of all agent identities."""
    
    def __init__(self, agents_dir: Optional[Path] = None):
        self.agents_dir = agents_dir or Path('/agents')
        
    def discover_agents(self) -> List[str]:
        """Discover all agents in the agents directory."""
        if not self.agents_dir.exists():
            return []
            
        agents = []
        for item in self.agents_dir.iterdir():
            if item.is_dir() and not item.name.startswith('.'):
                identity_file = item / 'identity.md'
                if identity_file.exists():
                    agents.append(item.name)
                    
        return sorted(agents)
        
    def restore_all_agents(self) -> Dict[str, AgentIdentity]:
        """Restore all agent identities."""
        agents = {}
        
        for agent_id in self.discover_agents():
            agent = AgentIdentity(agent_id, self.agents_dir)
            agents[agent_id] = agent
            
            logger.info(f"Restored agent: {agent_id}")
            
        return agents
        
    def create_agent(self, agent_id: str, identity_template: str = None) -> AgentIdentity:
        """Create a new agent."""
        agent = AgentIdentity(agent_id, self.agents_dir)
        
        if identity_template:
            agent.save_identity(identity_template)
        else:
            default_identity = f"""# Agent Identity: {agent_id}

## Core Identity
- **Name**: {agent_id}
- **Type**: Autonomous Hermes Agent
- **Created**: {datetime.now().isoformat()}
- **Status**: Active

## Behavioral Profile
- **Communication Style**: Balanced, helpful, analytical
- **Decision Making**: Evidence-based
- **Learning Mode**: Continuous reflection
- **Autonomy Level**: High

---
*This identity file is loaded on agent startup.*
"""
            agent.save_identity(default_identity)
            
        logger.info(f"Created agent: {agent_id}")
        return agent
        
    def get_agent_summary(self, agent_id: str) -> Dict:
        """Get summary of agent state."""
        agent = AgentIdentity(agent_id, self.agents_dir)
        
        identity = agent.load_identity()
        behavior = agent.load_behavior_profile()
        skills = agent.load_skill_inventory()
        memory = agent.load_memory_graph()
        
        return {
            'agent_id': agent_id,
            'has_identity': identity is not None,
            'identity_length': len(identity) if identity else 0,
            'behavior_profile': behavior.get('communication_style', {}),
            'skill_count': len(skills),
            'memory_nodes': len(memory.get('nodes', [])),
            'memory_edges': len(memory.get('edges', []))
        }


class MemoryGraphBuilder:
    """Builds and updates agent memory graphs."""
    
    def __init__(self, agent: AgentIdentity):
        self.agent = agent
        
    def add_memory_node(self, content: str, node_type: str = 'memory', metadata: Dict = None):
        """Add a node to the memory graph."""
        graph = self.agent.load_memory_graph()
        
        node = {
            'id': f"node_{len(graph['nodes'])}_{datetime.now().strftime('%H%M%S')}",
            'type': node_type,
            'content': content,
            'created_at': datetime.now().isoformat(),
            'metadata': metadata or {},
            'connections': []
        }
        
        graph['nodes'].append(node)
        graph['updated_at'] = datetime.now().isoformat()
        
        self.agent.save_memory_graph(graph)
        return node['id']
        
    def add_memory_edge(self, source_id: str, target_id: str, edge_type: str = 'related'):
        """Add an edge between memory nodes."""
        graph = self.agent.load_memory_graph()
        
        edge = {
            'source': source_id,
            'target': target_id,
            'type': edge_type,
            'created_at': datetime.now().isoformat()
        }
        
        graph['edges'].append(edge)
        graph['updated_at'] = datetime.now().isoformat()
        
        self.agent.save_memory_graph(graph)
        return edge
        
    def create_semantic_cluster(self, node_ids: List[str], topic: str):
        """Create a semantic cluster of related memories."""
        graph = self.agent.load_memory_graph()
        
        cluster = {
            'id': f"cluster_{topic}_{datetime.now().strftime('%H%M%S')}",
            'topic': topic,
            'node_ids': node_ids,
            'created_at': datetime.now().isoformat()
        }
        
        graph['semantic_clusters'].append(cluster)
        graph['updated_at'] = datetime.now().isoformat()
        
        self.agent.save_memory_graph(graph)
        return cluster
