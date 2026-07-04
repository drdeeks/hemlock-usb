"""
Phase 14 Validation Tests

Validates:
- Reflection engine operational
- Memory synthesis engine operational
- Skill generation pipeline operational
- Behavior profiling system operational
- Cognitive loop coordinator operational
"""

import asyncio
import json
import os
import sys
from pathlib import Path
from datetime import datetime

from paths import resolver

PROJECT_ROOT = resolver.root
sys.path.insert(0, str(resolver.hermes_home))

from hermes_constants import get_hermes_home


def test_cognition_directories():
    """Test cognition directories exist."""
    print("\n=== Testing Cognition Directories ===")
    
    hermes_home = resolver.hermes_home
    
    required_dirs = [
        hermes_home / 'reflections',
        hermes_home / 'summaries',
        hermes_home / 'embeddings',
        hermes_home / 'behavior',
        hermes_home / 'evolution',
        hermes_home / 'generated_skills',
        hermes_home / 'skill_drafts',
        hermes_home / 'skill_tests',
    ]
    
    all_exist = True
    for directory in required_dirs:
        exists = directory.exists()
        status = "✓" if exists else "!"
        print(f"  {status} {directory}")
        if not exists:
            all_exist = False
            
    return all_exist


def test_reflection_engine():
    """Test reflection engine."""
    print("\n=== Testing Reflection Engine ===")
    
    try:
        from cognition.reflection_engine import ReflectionEngine
        
        engine = ReflectionEngine(hermes_home=PROJECT_ROOT / 'runtime')
        
        test_messages = [
            {'role': 'user', 'content': 'How do I create a Python function?'},
            {'role': 'assistant', 'content': 'To create a Python function, use the def keyword...'},
            {'role': 'user', 'content': 'Can you show me an example?'},
            {'role': 'assistant', 'content': 'Here is an example: def my_function(): pass'}
        ]
        
        reflection = engine.generate_reflection(
            conversation_id='test_conv',
            messages=test_messages
        )
        
        print(f"  ✓ Generated reflection: {reflection['id']}")
        print(f"  ✓ Type: {reflection['type']}")
        print(f"  ✓ Patterns found: {len(reflection['patterns'])}")
        print(f"  ✓ Insights: {len(reflection['insights'])}")
        print(f"  ✓ Adaptations: {len(reflection['adaptations'])}")
        
        recent = engine.get_recent_reflections(limit=5)
        print(f"  ✓ Retrieved {len(recent)} recent reflections")
        
        pattern_analysis = engine.analyze_patterns()
        print(f"  ✓ Pattern analysis: {pattern_analysis['total_reflections']} total")
        
        return True
        
    except Exception as e:
        print(f"  ✗ Reflection engine test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_memory_synthesis():
    """Test memory synthesis engine."""
    print("\n=== Testing Memory Synthesis Engine ===")
    
    try:
        from cognition.memory_synthesis import MemorySynthesisEngine, MemoryWriter
        
        engine = MemorySynthesisEngine(hermes_home=PROJECT_ROOT / 'runtime')
        writer = MemoryWriter(engine)
        
        writer.write_message_memory(
            {'role': 'user', 'content': 'Testing memory write'},
            'test_session'
        )
        
        writer.write_event_memory(
            'skill_learned',
            {'skill_name': 'test_skill'},
            priority='high'
        )
        
        stats = engine.get_memory_stats()
        print(f"  ✓ Memory stats: {stats}")
        
        consolidated = engine.consolidate_to_long_term(threshold=1)
        print(f"  ✓ Consolidated {consolidated} memories")
        
        summary = engine.create_summary(
            [{'content': 'Test memory 1'}, {'content': 'Test memory 2'}],
            'test_topic'
        )
        print(f"  ✓ Created summary: {summary['id']}")
        
        results = engine.search_memories('test', limit=5)
        print(f"  ✓ Search returned {len(results)} results")
        
        return True
        
    except Exception as e:
        print(f"  ✗ Memory synthesis test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_skill_generation():
    """Test skill generation pipeline."""
    print("\n=== Testing Skill Generation Pipeline ===")
    
    try:
        from cognition.skill_generation import SkillGenerationPipeline
        
        pipeline = SkillGenerationPipeline(
            hermes_home=PROJECT_ROOT / 'runtime',
            agents_dir=PROJECT_ROOT / 'agents'
        )
        
        test_conversations = [
            {
                'messages': [
                    {'role': 'user', 'content': 'Create a function to add numbers'},
                    {'role': 'assistant', 'content': 'def add(a, b): return a + b'},
                    {'role': 'user', 'content': 'Now create a function to multiply'},
                    {'role': 'assistant', 'content': 'def multiply(a, b): return a * b'},
                ]
            }
        ]
        
        potential_skills = pipeline.analyze_for_skills(test_conversations, 'jack')
        print(f"  ✓ Identified {len(potential_skills)} potential skills")
        
        if potential_skills:
            skill = pipeline.generate_skill(potential_skills[0])
            print(f"  ✓ Generated skill: {skill['name']}")
            
            validated = pipeline.validate_skill(skill)
            print(f"  ✓ Validation status: {validated['status']}")
            
        return True
        
    except Exception as e:
        print(f"  ✗ Skill generation test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_behavior_profiling():
    """Test behavior profiling system."""
    print("\n=== Testing Behavior Profiling System ===")
    
    try:
        from cognition.behavior_profiling import BehaviorProfiler, BehaviorAdaptationEngine
        
        profiler = BehaviorProfiler(hermes_home=PROJECT_ROOT / 'runtime')
        
        test_messages = [
            {'role': 'user', 'content': 'What is this?'},
            {'role': 'assistant', 'content': 'This is a very long and detailed explanation...'},
            {'role': 'user', 'content': 'Too verbose, please be shorter'},
        ]
        
        profiler.update_from_interaction(
            test_messages,
            feedback={'type': 'too_verbose'}
        )
        
        profile = profiler.get_current_profile()
        print(f"  ✓ Profile updated: {profile['updated_at']}")
        print(f"  ✓ Avg response length: {profile['response_patterns']['avg_response_length']:.1f}")
        print(f"  ✓ Adaptation history: {len(profile['adaptation_history'])} entries")
        
        profiler.apply_adaptation({
            'type': 'reduce_length',
            'magnitude': 0.1,
            'duration': '10_interactions'
        })
        
        adaptations = profiler.get_active_adaptations()
        print(f"  ✓ Active adaptations: {len(adaptations)}")
        
        adapter = BehaviorAdaptationEngine(profiler)
        adapted = adapter.adapt_response("This is a test response", {})
        print(f"  ✓ Response adaptation working")
        
        return True
        
    except Exception as e:
        print(f"  ✗ Behavior profiling test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_cognitive_loop_coordinator():
    """Test cognitive loop coordinator."""
    print("\n=== Testing Cognitive Loop Coordinator ===")
    
    try:
        from cognition.cognitive_loop import CognitiveLoopCoordinator, PromptAdaptationLayer
        
        coordinator = CognitiveLoopCoordinator(
            hermes_home=PROJECT_ROOT / 'runtime',
            agents_dir=PROJECT_ROOT / 'agents'
        )
        
        state = coordinator.get_cognitive_state()
        print(f"  ✓ Cognitive state retrieved")
        print(f"  ✓ Running: {state['running']}")
        print(f"  ✓ Memory stats: {state['memory_stats']}")
        print(f"  ✓ Active adaptations: {state['active_adaptations']}")
        
        adapter = PromptAdaptationLayer(coordinator)
        adapted_prompt = adapter.adapt_prompt("Base prompt", "test_session")
        print(f"  ✓ Prompt adaptation working")
        
        system_prompt = adapter.get_system_prompt('jack')
        print(f"  ✓ System prompt generated ({len(system_prompt)} chars)")
        
        return True
        
    except Exception as e:
        print(f"  ✗ Cognitive loop coordinator test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_cognitive_timers():
    """Test cognitive timer configuration."""
    print("\n=== Testing Cognitive Timers ===")
    
    expected_timers = {
        'memory_write': 'every_message',
        'conversation_summary': 15,
        'reflection_pass': 45,
        'skill_generation': 300,
        'behavior_compression': 86400
    }
    
    try:
        from cognition.cognitive_loop import CognitiveLoopCoordinator
        
        coordinator = CognitiveLoopCoordinator(
            hermes_home=PROJECT_ROOT / 'runtime',
            agents_dir=PROJECT_ROOT / 'agents'
        )
        
        all_match = True
        for timer_name, expected_value in expected_timers.items():
            actual_value = coordinator.timers.get(timer_name)
            matches = actual_value == expected_value
            status = "✓" if matches else "✗"
            print(f"  {status} {timer_name}: {actual_value}")
            if not matches:
                all_match = False
                
        return all_match
        
    except Exception as e:
        print(f"  ✗ Timer test failed: {e}")
        return False


def run_all_tests():
    """Run all Phase 14 validation tests."""
    print("=" * 60)
    print("PHASE 14: CONTINUOUS COGNITIVE LOOP - VALIDATION")
    print("=" * 60)
    
    tests = [
        ("Cognition Directories", test_cognition_directories),
        ("Reflection Engine", test_reflection_engine),
        ("Memory Synthesis", test_memory_synthesis),
        ("Skill Generation", test_skill_generation),
        ("Behavior Profiling", test_behavior_profiling),
        ("Cognitive Loop Coordinator", test_cognitive_loop_coordinator),
        ("Cognitive Timers", test_cognitive_timers),
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
    print("PHASE 14 VALIDATION SUMMARY")
    print("=" * 60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}: {name}")
        
    print(f"\nTotal: {passed}/{total} tests passed")
    
    if passed == total:
        print("\n✓ PHASE 14 VALIDATION COMPLETE - COGNITIVE LOOP OPERATIONAL")
        return True
    else:
        print(f"\n✗ PHASE 14 VALIDATION INCOMPLETE - {total - passed} failures")
        return False


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
