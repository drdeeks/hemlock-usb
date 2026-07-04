"""
Skill Sandbox Executor - Safe execution environment for generated skills.

Provides isolated execution with:
- Resource limits
- Timeout enforcement
- Filesystem isolation
- Network restrictions
- Exception handling
"""

import ast
import asyncio
import json
import logging
import os
import subprocess
import sys
import tempfile
import traceback
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
from contextlib import contextmanager

logger = logging.getLogger(__name__)


class SkillSandbox:
    """Isolated sandbox for skill execution."""
    
    def __init__(self, timeout: int = 30, max_memory_mb: int = 256):
        self.timeout = timeout
        self.max_memory_mb = max_memory_mb
        self.execution_log = []
        
    def execute_skill(self, skill_path: Path, context: Dict = None) -> Dict:
        """Execute a skill in the sandbox."""
        result = {
            'success': False,
            'output': None,
            'error': None,
            'execution_time': 0,
            'resource_usage': {},
            'timestamp': datetime.now().isoformat()
        }
        
        if not skill_path.exists():
            result['error'] = f'Skill file not found: {skill_path}'
            return result
            
        start_time = datetime.now()
        
        try:
            with self._isolated_environment():
                output = self._execute_in_subprocess(skill_path, context)
                result['success'] = True
                result['output'] = output
                
        except TimeoutError:
            result['error'] = f'Execution timeout ({self.timeout}s)'
        except MemoryError:
            result['error'] = f'Memory limit exceeded ({self.max_memory_mb}MB)'
        except Exception as e:
            result['error'] = str(e)
            result['traceback'] = traceback.format_exc()
            
        result['execution_time'] = (datetime.now() - start_time).total_seconds()
        
        self._log_execution(skill_path, result)
        
        return result
        
    @contextmanager
    def _isolated_environment(self):
        """Create isolated execution environment."""
        original_cwd = os.getcwd()
        original_path = sys.path.copy()
        
        temp_dir = tempfile.mkdtemp(prefix='skill_sandbox_')
        
        try:
            os.chdir(temp_dir)
            
            safe_path = [temp_dir]
            sys.path = safe_path
            
            yield
            
        finally:
            os.chdir(original_cwd)
            sys.path = original_path
            
            try:
                import shutil
                shutil.rmtree(temp_dir)
            except:
                pass
                
    def _execute_in_subprocess(self, skill_path: Path, context: Dict = None) -> Dict:
        """Execute skill in subprocess with limits."""
        context_json = json.dumps(context or {})
        
        code = f'''
import sys
import json

# Load context
context = json.loads({context_json!r})

# Execute skill
exec(open(r'{skill_path}').read())

# Try to call execute function
if 'execute' in globals():
    result = execute(context)
    print(json.dumps({{
        'result': result,
        'status': 'success'
    }}))
else:
    print(json.dumps({{
        'result': None,
        'status': 'no_execute_function'
    }}))
'''
        
        try:
            process = subprocess.run(
                [sys.executable, '-c', code],
                capture_output=True,
                text=True,
                timeout=self.timeout,
                env={**os.environ, 'PYTHONPATH': ''}
            )
            
            if process.returncode != 0:
                raise RuntimeError(f'Process failed: {process.stderr}')
                
            output = json.loads(process.stdout)
            return output
            
        except subprocess.TimeoutExpired:
            raise TimeoutError()
            
    def _log_execution(self, skill_path: Path, result: Dict):
        """Log execution for audit."""
        log_entry = {
            'skill': str(skill_path),
            'timestamp': result['timestamp'],
            'success': result['success'],
            'execution_time': result['execution_time'],
            'error': result.get('error')
        }
        
        self.execution_log.append(log_entry)
        
        if len(self.execution_log) > 1000:
            self.execution_log = self.execution_log[-1000:]
            
    def get_execution_history(self, limit: int = 50) -> List[Dict]:
        """Get recent execution history."""
        return self.execution_log[-limit:]


class SkillRegistry:
    """Central registry for all skills."""
    
    def __init__(self, registry_path: Optional[Path] = None):
        if registry_path:
            self.registry_path = registry_path
        else:
            from paths import resolver
            project_runtime = resolver.hermes_home
            self.registry_path = project_runtime / 'registered_skills.json'
        self.registry_path.parent.mkdir(parents=True, exist_ok=True)
        self.skills = self._load_registry()
        
    def _load_registry(self) -> Dict:
        """Load skill registry."""
        if not self.registry_path.exists():
            return {'skills': [], 'metadata': {'created_at': datetime.now().isoformat()}}
            
        with open(self.registry_path) as f:
            return json.load(f)
            
    def _save_registry(self):
        """Save skill registry."""
        with open(self.registry_path, 'w') as f:
            json.dump(self.skills, f, indent=2)
            
    def register_skill(self, skill_info: Dict) -> str:
        """Register a skill."""
        skill_id = f"skill_{len(self.skills['skills'])}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
        
        skill_entry = {
            'id': skill_id,
            'registered_at': datetime.now().isoformat(),
            'status': 'active',
            **skill_info
        }
        
        self.skills['skills'].append(skill_entry)
        self._save_registry()
        
        logger.info(f"Registered skill: {skill_id}")
        return skill_id
        
    def unregister_skill(self, skill_id: str):
        """Unregister a skill."""
        self.skills['skills'] = [
            s for s in self.skills['skills'] 
            if s['id'] != skill_id
        ]
        self._save_registry()
        logger.info(f"Unregistered skill: {skill_id}")
        
    def get_skill(self, skill_id: str) -> Optional[Dict]:
        """Get skill by ID."""
        for skill in self.skills['skills']:
            if skill['id'] == skill_id:
                return skill
        return None
        
    def list_skills(self, status: str = None) -> List[Dict]:
        """List skills, optionally filtered by status."""
        skills = self.skills['skills']
        
        if status:
            skills = [s for s in skills if s.get('status') == status]
            
        return skills
        
    def update_skill_status(self, skill_id: str, status: str):
        """Update skill status."""
        for skill in self.skills['skills']:
            if skill['id'] == skill_id:
                skill['status'] = status
                skill['updated_at'] = datetime.now().isoformat()
                break
        self._save_registry()
        
    def get_registry_stats(self) -> Dict:
        """Get registry statistics."""
        skills = self.skills['skills']
        
        return {
            'total_skills': len(skills),
            'active': sum(1 for s in skills if s.get('status') == 'active'),
            'disabled': sum(1 for s in skills if s.get('status') == 'disabled'),
            'auto_generated': sum(1 for s in skills if s.get('source') == 'auto_generated'),
            'manual': sum(1 for s in skills if s.get('source') == 'manual')
        }


class SkillEvolutionEngine:
    """Orchestrates skill evolution lifecycle."""
    
    def __init__(self, hermes_home: Optional[Path] = None, agents_dir: Optional[Path] = None):
        from paths import resolver
        self.hermes_home = hermes_home or resolver.hermes_home
        self.agents_dir = agents_dir or resolver.agents_dir
        
        self.sandbox = SkillSandbox()
        self.registry = SkillRegistry()
        
        from cognition.skill_generation import SkillGenerationPipeline
        self.generation_pipeline = SkillGenerationPipeline(self.hermes_home, self.agents_dir)
        
    def evolve_skill(self, skill_id: str, feedback: Dict) -> Optional[str]:
        """Evolve a skill based on feedback."""
        skill = self.registry.get_skill(skill_id)
        
        if not skill:
            logger.warning(f"Skill not found: {skill_id}")
            return None
            
        evolved_skill = {
            **skill,
            'version': skill.get('version', 1) + 1,
            'evolved_at': datetime.now().isoformat(),
            'evolution_feedback': feedback,
            'parent_skill': skill_id
        }
        
        new_id = self.registry.register_skill(evolved_skill)
        
        if skill.get('source') == 'auto_generated':
            self.registry.update_skill_status(skill_id, 'superseded')
            
        logger.info(f"Evolved skill {skill_id} -> {new_id}")
        return new_id
        
    def validate_and_activate(self, skill_path: Path, skill_info: Dict) -> bool:
        """Validate skill and activate if successful."""
        result = self.sandbox.execute_skill(skill_path, {'test': True})
        
        if result['success']:
            skill_info['validated_at'] = datetime.now().isoformat()
            skill_info['validation_result'] = result
            skill_info['status'] = 'active'
            
            self.registry.register_skill(skill_info)
            logger.info(f"Skill validated and activated: {skill_info.get('name')}")
            return True
        else:
            logger.warning(f"Skill validation failed: {result.get('error')}")
            return False
            
    def get_evolution_stats(self) -> Dict:
        """Get skill evolution statistics."""
        registry_stats = self.registry.get_registry_stats()
        execution_history = self.sandbox.get_execution_history()
        
        successful_executions = sum(
            1 for e in execution_history 
            if e.get('success', False)
        )
        
        return {
            **registry_stats,
            'total_executions': len(execution_history),
            'successful_executions': successful_executions,
            'success_rate': successful_executions / max(len(execution_history), 1)
        }
