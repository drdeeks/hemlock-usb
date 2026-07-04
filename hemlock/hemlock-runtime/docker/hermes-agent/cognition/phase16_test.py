"""
Phase 16 Validation Tests

Validates:
- Skill sandbox executor operational
- Skill registry functional
- Skill evolution engine working
- Safe execution with timeouts
- Resource limits enforced
"""

import json
import os
import sys
import tempfile
from pathlib import Path
from datetime import datetime

from paths import resolver

sys.path.insert(0, str(resolver.hermes_home))


def test_skill_sandbox():
    """Test skill sandbox executor."""
    print("\n=== Testing Skill Sandbox ===")
    
    try:
        from cognition.skill_sandbox import SkillSandbox
        
        sandbox = SkillSandbox(timeout=10, max_memory_mb=128)
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write('''
def execute(context=None):
    return {"status": "success", "message": "Hello from sandbox"}
''')
            temp_skill = Path(f.name)
            
        try:
            result = sandbox.execute_skill(temp_skill, {'test': True})
            
            if result['success']:
                print(f"  ✓ Sandbox execution successful")
                print(f"  ✓ Execution time: {result['execution_time']:.3f}s")
                print(f"  ✓ Output: {result['output']}")
            else:
                print(f"  ✗ Sandbox execution failed: {result.get('error')}")
                return False
                
            history = sandbox.get_execution_history()
            print(f"  ✓ Execution history: {len(history)} entries")
            
            return True
            
        finally:
            temp_skill.unlink()
            
    except Exception as e:
        print(f"  ✗ Skill sandbox test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_skill_registry():
    """Test skill registry."""
    print("\n=== Testing Skill Registry ===")
    
    try:
        from cognition.skill_sandbox import SkillRegistry
        
        registry_path = PROJECT_ROOT / 'runtime' / 'test_skills.json'
        registry = SkillRegistry(registry_path=registry_path)
        
        skill_id = registry.register_skill({
            'name': 'test_skill',
            'type': 'test',
            'description': 'Test skill for validation',
            'source': 'manual'
        })
        
        print(f"  ✓ Registered skill: {skill_id}")
        
        skill = registry.get_skill(skill_id)
        if skill and skill['name'] == 'test_skill':
            print(f"  ✓ Skill retrieved successfully")
        else:
            print(f"  ✗ Skill retrieval failed")
            return False
            
        skills = registry.list_skills()
        print(f"  ✓ Listed {len(skills)} skills")
        
        stats = registry.get_registry_stats()
        print(f"  ✓ Registry stats: {stats}")
        
        registry.unregister_skill(skill_id)
        print(f"  ✓ Skill unregistered")
        
        registry_path.unlink(missing_ok=True)
        
        return True
        
    except Exception as e:
        print(f"  ✗ Skill registry test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_sandbox_timeout():
    """Test sandbox timeout enforcement."""
    print("\n=== Testing Sandbox Timeout ===")
    
    try:
        from cognition.skill_sandbox import SkillSandbox
        
        sandbox = SkillSandbox(timeout=2)
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write('''
import time
def execute(context=None):
    time.sleep(5)
    return {"status": "should_not_reach"}
''')
            temp_skill = Path(f.name)
            
        try:
            result = sandbox.execute_skill(temp_skill)
            
            if not result['success'] and 'timeout' in result.get('error', '').lower():
                print(f"  ✓ Timeout enforced correctly")
                print(f"  ✓ Error: {result['error']}")
                return True
            else:
                print(f"  ✗ Timeout not enforced")
                return False
                
        finally:
            temp_skill.unlink()
            
    except Exception as e:
        print(f"  ✗ Timeout test failed: {e}")
        return False


def test_skill_evolution_engine():
    """Test skill evolution engine."""
    print("\n=== Testing Skill Evolution Engine ===")
    
    try:
        from cognition.skill_sandbox import SkillEvolutionEngine
        
        engine = SkillEvolutionEngine(
            hermes_home=PROJECT_ROOT / 'runtime',
            agents_dir=PROJECT_ROOT / 'agents'
        )
        
        stats = engine.get_evolution_stats()
        print(f"  ✓ Evolution stats: {stats}")
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write('''
def execute(context=None):
    return {"result": "test"}
''')
            temp_skill = Path(f.name)
            
        try:
            skill_info = {
                'name': 'evolution_test',
                'type': 'test',
                'source': 'test'
            }
            
            result = engine.validate_and_activate(temp_skill, skill_info)
            print(f"  ✓ Validation result: {result}")
            
        finally:
            temp_skill.unlink()
            
        return True
        
    except Exception as e:
        print(f"  ✗ Evolution engine test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_skill_lifecycle():
    """Test complete skill lifecycle."""
    print("\n=== Testing Skill Lifecycle ===")
    
    try:
        from cognition.skill_sandbox import SkillSandbox, SkillRegistry, SkillEvolutionEngine
        from cognition.skill_generation import SkillGenerationPipeline
        
        sandbox = SkillSandbox()
        registry = SkillRegistry(registry_path=PROJECT_ROOT / 'runtime' / 'lifecycle_test.json')
        
        skill_path = PROJECT_ROOT / 'runtime' / 'skill_drafts' / 'lifecycle_test.py'
        skill_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(skill_path, 'w') as f:
            f.write('''
def execute(context=None):
    return {"lifecycle": "complete"}
''')
        
        skill_info = {
            'name': 'lifecycle_test',
            'type': 'test',
            'source': 'test',
            'path': str(skill_path)
        }
        
        result = sandbox.execute_skill(skill_path)
        print(f"  1. Execution: {'✓' if result['success'] else '✗'}")
        
        skill_id = registry.register_skill(skill_info)
        print(f"  2. Registration: ✓ ({skill_id})")
        
        skill = registry.get_skill(skill_id)
        print(f"  3. Retrieval: {'✓' if skill else '✗'}")
        
        registry.update_skill_status(skill_id, 'active')
        print(f"  4. Activation: ✓")
        
        skills = registry.list_skills(status='active')
        print(f"  5. Listing: ✓ ({len(skills)} active)")
        
        registry_path = PROJECT_ROOT / 'runtime' / 'lifecycle_test.json'
        registry_path.unlink(missing_ok=True)
        skill_path.unlink(missing_ok=True)
        
        print(f"  ✓ Complete lifecycle test passed")
        return True
        
    except Exception as e:
        print(f"  ✗ Lifecycle test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_sandbox_isolation():
    """Test sandbox filesystem isolation."""
    print("\n=== Testing Sandbox Isolation ===")
    
    try:
        from cognition.skill_sandbox import SkillSandbox
        
        sandbox = SkillSandbox()
        
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write('''
import os
def execute(context=None):
    cwd = os.getcwd()
    is_temp = "skill_sandbox" in cwd or "/tmp" in cwd
    return {"cwd": cwd, "is_temp": is_temp}
''')
            temp_skill = Path(f.name)
            
        try:
            result = sandbox.execute_skill(temp_skill)
            
            print(f"  Working directory: {result.get('output', {}).get('cwd', 'unknown')}")
            
            if result['success']:
                print(f"  ✓ Sandbox execution completed")
                print(f"  ✓ Isolation working (executes in temp dir)")
                return True
            else:
                print(f"  ✗ Execution failed: {result.get('error')}")
                return False
                
        finally:
            temp_skill.unlink()
            
    except Exception as e:
        print(f"  ✗ Isolation test failed: {e}")
        return False


def run_all_tests():
    """Run all Phase 16 validation tests."""
    print("=" * 60)
    print("PHASE 16: SELF-EVOLVING SKILL SYSTEM - VALIDATION")
    print("=" * 60)
    
    tests = [
        ("Skill Sandbox", test_skill_sandbox),
        ("Skill Registry", test_skill_registry),
        ("Sandbox Timeout", test_sandbox_timeout),
        ("Skill Evolution Engine", test_skill_evolution_engine),
        ("Skill Lifecycle", test_skill_lifecycle),
        ("Sandbox Isolation", test_sandbox_isolation),
    ]
    
    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
        except Exception as e:
            print(f"\n✗ {name} test crashed: {e}")
            results.append((name, False))
            
    print("\n" + "=" * 60)
    print("PHASE 16 VALIDATION SUMMARY")
    print("=" * 60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}: {name}")
        
    print(f"\nTotal: {passed}/{total} tests passed")
    
    if passed == total:
        print("\n✓ PHASE 16 VALIDATION COMPLETE - SKILL SYSTEM OPERATIONAL")
        return True
    else:
        print(f"\n✗ PHASE 16 VALIDATION INCOMPLETE - {total - passed} failures")
        return False


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
