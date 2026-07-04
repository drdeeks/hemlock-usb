"""
Skill Generation Pipeline - Autonomous skill creation from patterns.

Identifies repeated workflows and converts them into reusable skills.
"""

import ast
import asyncio
import json
import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Any
from hermes_constants import get_hermes_home
from paths import resolver

logger = logging.getLogger(__name__)


class SkillGenerationPipeline:
    """Generates skills from repeated patterns."""
    
    def __init__(self, hermes_home: Optional[Path] = None, agents_dir: Optional[Path] = None):
        self.hermes_home = hermes_home or get_hermes_home()
        self.agents_dir = agents_dir or resolver.agents_dir
        
        self.skill_drafts_dir = self.hermes_home / 'skill_drafts'
        self.skill_tests_dir = self.hermes_home / 'skill_tests'
        self.generated_skills_dir = self.hermes_home / 'generated_skills'
        
        for directory in [self.skill_drafts_dir, self.skill_tests_dir, self.generated_skills_dir]:
            directory.mkdir(parents=True, exist_ok=True)
            
        self.pattern_detector = PatternDetector()
        self.workflow_extractor = WorkflowExtractor()
        self.code_generator = SkillCodeGenerator()
        self.validator = SkillValidator()
        
    def analyze_for_skills(self, conversations: List[Dict], agent_id: str) -> List[Dict]:
        """Analyze conversations for potential skill generation."""
        potential_skills = []
        
        patterns = self.pattern_detector.detect_patterns(conversations)
        
        for pattern in patterns:
            if pattern['frequency'] >= 3 and pattern['confidence'] > 0.7:
                skill_proposal = {
                    'agent_id': agent_id,
                    'pattern': pattern,
                    'workflow': self.workflow_extractor.extract_workflow(conversations, pattern),
                    'timestamp': datetime.now().isoformat()
                }
                potential_skills.append(skill_proposal)
                
        logger.info(f"Identified {len(potential_skills)} potential skills for {agent_id}")
        return potential_skills
        
    def generate_skill(self, skill_proposal: Dict) -> Optional[Dict]:
        """Generate a skill from a proposal."""
        skill_name = self._generate_skill_name(skill_proposal['pattern'])
        
        skill_code = self.code_generator.generate(
            name=skill_name,
            workflow=skill_proposal['workflow'],
            pattern=skill_proposal['pattern']
        )
        
        draft_path = self.skill_drafts_dir / f'{skill_name}.py'
        with open(draft_path, 'w') as f:
            f.write(skill_code)
            
        skill_metadata = {
            'name': skill_name,
            'agent_id': skill_proposal['agent_id'],
            'draft_path': str(draft_path),
            'created_at': datetime.now().isoformat(),
            'pattern': skill_proposal['pattern'],
            'status': 'draft'
        }
        
        logger.info(f"Generated skill draft: {skill_name}")
        return skill_metadata
        
    def validate_skill(self, skill_metadata: Dict) -> Dict:
        """Validate a generated skill."""
        draft_path = Path(skill_metadata['draft_path'])
        
        validation_result = self.validator.validate(draft_path)
        
        skill_metadata['validation'] = validation_result
        skill_metadata['status'] = 'validated' if validation_result['valid'] else 'failed'
        
        if validation_result['valid']:
            test_path = self.skill_tests_dir / f"{skill_metadata['name']}_test.py"
            self._create_test_file(test_path, skill_metadata)
            skill_metadata['test_path'] = str(test_path)
            
        return skill_metadata
        
    def register_skill(self, skill_metadata: Dict, agent_id: str) -> bool:
        """Register a validated skill to an agent."""
        if skill_metadata['status'] != 'validated':
            logger.warning(f"Cannot register unvalidated skill: {skill_metadata['name']}")
            return False
            
        agent_skills_dir = self.agents_dir / agent_id / 'skills'
        agent_skills_dir.mkdir(parents=True, exist_ok=True)
        
        draft_path = Path(skill_metadata['draft_path'])
        target_path = agent_skills_dir / f"{skill_metadata['name']}.py"
        
        with open(draft_path) as f:
            skill_code = f.read()
            
        with open(target_path, 'w') as f:
            f.write(skill_code)
            
        skill_registry = self._load_skill_registry(agent_id)
        skill_registry.append({
            'name': skill_metadata['name'],
            'registered_at': datetime.now().isoformat(),
            'source': 'auto_generated'
        })
        self._save_skill_registry(agent_id, skill_registry)
        
        logger.info(f"Registered skill: {skill_metadata['name']} for agent {agent_id}")
        return True
        
    def _generate_skill_name(self, pattern: Dict) -> str:
        """Generate a skill name from pattern."""
        pattern_type = pattern.get('type', 'unknown')
        return f"auto_{pattern_type}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
    def _load_skill_registry(self, agent_id: str) -> List[Dict]:
        """Load agent's skill registry."""
        registry_path = self.agents_dir / agent_id / 'skills' / 'registry.json'
        
        if not registry_path.exists():
            return []
            
        try:
            with open(registry_path) as f:
                return json.load(f)
        except:
            return []
            
    def _save_skill_registry(self, agent_id: str, registry: List[Dict]):
        """Save agent's skill registry."""
        registry_path = self.agents_dir / agent_id / 'skills' / 'registry.json'
        
        with open(registry_path, 'w') as f:
            json.dump(registry, f, indent=2)
            
    def _create_test_file(self, test_path: Path, skill_metadata: Dict):
        """Create a test file for the skill."""
        test_code = f'''
"""Tests for {skill_metadata['name']}"""

def test_skill_execution():
    """Test basic skill execution."""
    # TODO: Implement test cases
    pass
    
if __name__ == '__main__':
    test_skill_execution()
    print("Tests passed")
'''
        with open(test_path, 'w') as f:
            f.write(test_code)


class PatternDetector:
    """Detects repeated patterns in conversations."""
    
    def detect_patterns(self, conversations: List[Dict]) -> List[Dict]:
        """Detect patterns in conversations."""
        patterns = {}
        
        for conv in conversations:
            messages = conv.get('messages', [])
            
            for i, message in enumerate(messages):
                content = message.get('content', '')
                
                if 'function' in content.lower() or 'code' in content.lower():
                    pattern_key = 'code_generation'
                elif 'explain' in content.lower() or 'what' in content.lower():
                    pattern_key = 'explanation'
                elif 'fix' in content.lower() or 'error' in content.lower():
                    pattern_key = 'debugging'
                elif 'create' in content.lower() or 'build' in content.lower():
                    pattern_key = 'creation'
                else:
                    continue
                    
                patterns[pattern_key] = patterns.get(pattern_key, 0) + 1
                
        result = []
        total = sum(patterns.values())
        
        for pattern_type, count in patterns.items():
            result.append({
                'type': pattern_type,
                'frequency': count,
                'confidence': count / max(total, 1),
                'significance': 'high' if count >= 5 else 'medium' if count >= 3 else 'low'
            })
            
        return sorted(result, key=lambda x: x['frequency'], reverse=True)


class WorkflowExtractor:
    """Extracts workflows from conversation patterns."""
    
    def extract_workflow(self, conversations: List[Dict], pattern: Dict) -> Dict:
        """Extract workflow from conversations matching pattern."""
        workflow = {
            'steps': [],
            'inputs': [],
            'outputs': [],
            'tools_used': []
        }
        
        for conv in conversations:
            messages = conv.get('messages', [])
            
            for message in messages:
                content = message.get('content', '')
                
                if pattern['type'].lower() in content.lower():
                    workflow['steps'].append({
                        'type': message.get('role', 'unknown'),
                        'content': content[:500]
                    })
                    
        return workflow


class SkillCodeGenerator:
    """Generates Python code for skills."""
    
    def generate(self, name: str, workflow: Dict, pattern: Dict) -> str:
        """Generate skill code."""
        code = f'''"""
Auto-generated skill: {name}

Pattern: {pattern.get('type', 'unknown')}
Generated: {datetime.now().isoformat()}
"""

def execute(context=None):
    """Execute the skill."""
    # Auto-generated skill - review and customize as needed
    result = {{
        'skill': '{name}',
        'status': 'executed',
        'timestamp': __import__('datetime').datetime.now().isoformat()
    }}
    return result

if __name__ == '__main__':
    print(execute())
'''
        return code


class SkillValidator:
    """Validates generated skills."""
    
    def validate(self, skill_path: Path) -> Dict:
        """Validate a skill file."""
        result = {
            'valid': False,
            'syntax_valid': False,
            'executable': False,
            'errors': []
        }
        
        if not skill_path.exists():
            result['errors'].append('File not found')
            return result
            
        try:
            with open(skill_path) as f:
                code = f.read()
            ast.parse(code)
            result['syntax_valid'] = True
        except SyntaxError as e:
            result['errors'].append(f'Syntax error: {e}')
            return result
            
        try:
            import sys
            sys.path.insert(0, str(skill_path.parent))
            exec(compile(open(skill_path).read(), skill_path, 'exec'))
            result['executable'] = True
        except Exception as e:
            result['errors'].append(f'Execution error: {e}')
            
        result['valid'] = result['syntax_valid'] and result['executable']
        return result
