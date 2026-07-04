"""
Phase 15 Validation Tests

Validates:
- Agent identity files loaded
- Memory graphs functional
- Behavior profiles restored
- Skill inventories accessible
- Reflection archives accessible
- Preference memory restored
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime

from paths import resolver

sys.path.insert(0, str(resolver.hermes_home))


def test_agent_identity_files():
    """Test agent identity files exist and load."""
    print("\n=== Testing Agent Identity Files ===")
    
    agents_dir = resolver.agents_dir
    identity_files = list(agents_dir.glob('*/identity.md'))
    
    if len(identity_files) == 0:
        print(f"  ✗ No identity files found")
        return False
        
    print(f"  ✓ Found {len(identity_files)} identity files:")
    
    for identity_file in identity_files:
        agent_name = identity_file.parent.name
        with open(identity_file) as f:
            content = f.read()
        print(f"    ✓ {agent_name}: {len(content)} bytes")
        
    return True


def test_agent_identity_class():
    """Test AgentIdentity class functionality."""
    print("\n=== Testing AgentIdentity Class ===")
    
    try:
        from identity.agent_identity import AgentIdentity
        
        agent = AgentIdentity('jack', agents_dir=PROJECT_ROOT / 'agents')
        
        identity = agent.load_identity()
        if identity:
            print(f"  ✓ Identity loaded: {len(identity)} bytes")
        else:
            print(f"  ✗ Identity not found")
            return False
            
        behavior = agent.load_behavior_profile()
        print(f"  ✓ Behavior profile: {behavior['communication_style']}")
        
        preferences = agent.load_preferences()
        print(f"  ✓ Preferences: {preferences['communication']}")
        
        skills = agent.load_skill_inventory()
        print(f"  ✓ Skill inventory: {len(skills)} skills")
        
        memory_graph = agent.load_memory_graph()
        print(f"  ✓ Memory graph: {len(memory_graph['nodes'])} nodes")
        
        return True
        
    except Exception as e:
        print(f"  ✗ AgentIdentity test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_identity_restoration_manager():
    """Test IdentityRestorationManager."""
    print("\n=== Testing Identity Restoration Manager ===")
    
    try:
        from identity.agent_identity import IdentityRestorationManager
        
        manager = IdentityRestorationManager(agents_dir=PROJECT_ROOT / 'agents')
        
        agents = manager.discover_agents()
        print(f"  ✓ Discovered {len(agents)} agents: {agents}")
        
        restored = manager.restore_all_agents()
        print(f"  ✓ Restored {len(restored)} agents")
        
        for agent_id in agents[:3]:
            summary = manager.get_agent_summary(agent_id)
            print(f"    - {agent_id}: identity={summary['has_identity']}, skills={summary['skill_count']}")
            
        return True
        
    except Exception as e:
        print(f"  ✗ IdentityRestorationManager test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_memory_graph_builder():
    """Test MemoryGraphBuilder."""
    print("\n=== Testing Memory Graph Builder ===")
    
    try:
        from identity.agent_identity import AgentIdentity, MemoryGraphBuilder
        
        agent = AgentIdentity('jack', agents_dir=PROJECT_ROOT / 'agents')
        builder = MemoryGraphBuilder(agent)
        
        node1 = builder.add_memory_node(
            "User asked about Python functions",
            node_type='conversation',
            metadata={'session': 'test'}
        )
        print(f"  ✓ Added memory node: {node1}")
        
        node2 = builder.add_memory_node(
            "Explained def keyword",
            node_type='knowledge',
            metadata={'topic': 'python'}
        )
        print(f"  ✓ Added memory node: {node2}")
        
        edge = builder.add_memory_edge(node1, node2, edge_type='related_to')
        print(f"  ✓ Added memory edge")
        
        cluster = builder.create_semantic_cluster([node1, node2], 'python_basics')
        print(f"  ✓ Created semantic cluster: {cluster['id']}")
        
        graph = agent.load_memory_graph()
        print(f"  ✓ Graph state: {len(graph['nodes'])} nodes, {len(graph['edges'])} edges, {len(graph['semantic_clusters'])} clusters")
        
        return True
        
    except Exception as e:
        print(f"  ✗ MemoryGraphBuilder test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_behavior_profile_persistence():
    """Test behavior profile persistence."""
    print("\n=== Testing Behavior Profile Persistence ===")
    
    try:
        from identity.agent_identity import AgentIdentity
        
        agent = AgentIdentity('orca', agents_dir=PROJECT_ROOT / 'agents')
        
        profile = agent.load_behavior_profile()
        original_style = profile['communication_style'].copy()
        
        profile['communication_style']['verbosity'] = 'detailed'
        profile['communication_style']['formality'] = 'professional'
        
        agent.save_behavior_profile(profile)
        
        loaded = agent.load_behavior_profile()
        
        if loaded['communication_style']['verbosity'] == 'detailed':
            print(f"  ✓ Behavior profile persisted correctly")
        else:
            print(f"  ✗ Behavior profile not persisted")
            return False
            
        profile['communication_style'] = original_style
        agent.save_behavior_profile(profile)
        
        return True
        
    except Exception as e:
        print(f"  ✗ Behavior profile test failed: {e}")
        return False


def test_skill_inventory_management():
    """Test skill inventory management."""
    print("\n=== Testing Skill Inventory Management ===")
    
    try:
        from identity.agent_identity import AgentIdentity
        
        agent = AgentIdentity('dev-agent', agents_dir=PROJECT_ROOT / 'agents')
        
        initial_count = len(agent.load_skill_inventory())
        print(f"  ✓ Initial skill count: {initial_count}")
        
        agent.add_skill({
            'name': 'test_skill',
            'type': 'auto_generated',
            'description': 'Test skill for validation'
        })
        
        updated_count = len(agent.load_skill_inventory())
        print(f"  ✓ Updated skill count: {updated_count}")
        
        if updated_count == initial_count + 1:
            print(f"  ✓ Skill added successfully")
        else:
            print(f"  ✗ Skill not added correctly")
            return False
            
        return True
        
    except Exception as e:
        print(f"  ✗ Skill inventory test failed: {e}")
        return False


def test_agent_state_completeness():
    """Test complete agent state retrieval."""
    print("\n=== Testing Agent State Completeness ===")
    
    try:
        from identity.agent_identity import AgentIdentity
        
        agent = AgentIdentity('jack', agents_dir=PROJECT_ROOT / 'agents')
        state = agent.get_complete_state()
        
        checks = {
            'identity': state['identity'] is not None,
            'memory_graph': 'nodes' in state['memory_graph'],
            'behavior_profile': 'communication_style' in state['behavior_profile'],
            'preferences': 'communication' in state['preferences'],
            'skills': isinstance(state['skills'], list),
            'reflections': isinstance(state['reflections'], list)
        }
        
        all_pass = True
        for component, passed in checks.items():
            status = "✓" if passed else "✗"
            print(f"  {status} {component}")
            if not passed:
                all_pass = False
                
        return all_pass
        
    except Exception as e:
        print(f"  ✗ Agent state test failed: {e}")
        return False


def run_all_tests():
    """Run all Phase 15 validation tests."""
    print("=" * 60)
    print("PHASE 15: AGENT IDENTITY RESTORATION - VALIDATION")
    print("=" * 60)
    
    tests = [
        ("Agent Identity Files", test_agent_identity_files),
        ("AgentIdentity Class", test_agent_identity_class),
        ("Identity Restoration Manager", test_identity_restoration_manager),
        ("Memory Graph Builder", test_memory_graph_builder),
        ("Behavior Profile Persistence", test_behavior_profile_persistence),
        ("Skill Inventory Management", test_skill_inventory_management),
        ("Agent State Completeness", test_agent_state_completeness),
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
    print("PHASE 15 VALIDATION SUMMARY")
    print("=" * 60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}: {name}")
        
    print(f"\nTotal: {passed}/{total} tests passed")
    
    if passed == total:
        print("\n✓ PHASE 15 VALIDATION COMPLETE - AGENT IDENTITIES RESTORED")
        return True
    else:
        print(f"\n✗ PHASE 15 VALIDATION INCOMPLETE - {total - passed} failures")
        return False


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
