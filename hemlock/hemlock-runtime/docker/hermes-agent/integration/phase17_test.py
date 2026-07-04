"""
Phase 17 Validation Tests

Validates:
- OpenClaw-Hermes bridge operational
- Transport layer integration
- MCP coordination
- Message routing through cognition
- Responsibility split maintained
"""

import asyncio
import sys
from pathlib import Path
from datetime import datetime

from paths import resolver

sys.path.insert(0, str(resolver.hermes_home))


def test_bridge_initialization():
    """Test bridge initialization."""
    print("\n=== Testing Bridge Initialization ===")
    
    try:
        from integration.openclaw_bridge import OpenClawHermesBridge
        
        bridge = OpenClawHermesBridge(
            hermes_home=resolver.hermes_home,
            agents_dir=resolver.agents_dir
        )
        
        status = bridge.get_bridge_status()
        print(f"  ✓ Bridge created: {status['status']}")
        print(f"  ✓ Hermes ready: {status['hermes_ready']}")
        
        return True
        
    except Exception as e:
        print(f"  ✗ Bridge initialization failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_hermes_components():
    """Test Hermes components are loaded."""
    print("\n=== Testing Hermes Components ===")
    
    try:
        from integration.openclaw_bridge import OpenClawHermesBridge
        
        bridge = OpenClawHermesBridge(
            hermes_home=resolver.hermes_home,
            agents_dir=resolver.agents_dir
        )
        
        components = bridge.get_bridge_status()['hermes_components']
        
        all_loaded = True
        for component, loaded in components.items():
            status = "✓" if loaded else "✗"
            print(f"  {status} {component}")
            if not loaded:
                all_loaded = False
                
        return all_loaded
        
    except Exception as e:
        print(f"  ✗ Hermes components test failed: {e}")
        return False


def test_message_routing():
    """Test message routing through cognition."""
    print("\n=== Testing Message Routing ===")
    
    try:
        from integration.openclaw_bridge import OpenClawHermesBridge
        
        bridge = OpenClawHermesBridge(
            hermes_home=resolver.hermes_home,
            agents_dir=resolver.agents_dir
        )
        
        response = bridge.route_message(
            platform='test',
            user_id='test_user',
            message={'content': 'Hello, this is a test message'}
        )
        
        if response.get('content'):
            print(f"  ✓ Message routed successfully")
            print(f"  ✓ Response: {response['content'][:50]}...")
            print(f"  ✓ Session ID: {response.get('session_id')}")
            return True
        else:
            print(f"  ✗ No response generated")
            return False
            
    except Exception as e:
        print(f"  ✗ Message routing failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_runtime_host():
    """Test OpenClaw runtime host."""
    print("\n=== Testing Runtime Host ===")
    
    try:
        from integration.openclaw_bridge import OpenClawRuntimeHost
        
        host = OpenClawRuntimeHost()
        
        status = host.get_status()
        print(f"  ✓ Runtime host created")
        print(f"  ✓ Running: {status['running']}")
        
        return True
        
    except Exception as e:
        print(f"  ✗ Runtime host test failed: {e}")
        return False


def test_responsibility_split():
    """Test responsibility split is maintained."""
    print("\n=== Testing Responsibility Split ===")
    
    try:
        from integration.openclaw_bridge import OpenClawHermesBridge
        
        bridge = OpenClawHermesBridge(
            hermes_home=resolver.hermes_home,
            agents_dir=resolver.agents_dir
        )
        
        status = bridge.get_bridge_status()
        
        hermes_components = status['hermes_components']
        openclaw_components = status['openclaw_components']
        
        print("  Hermes (Cognition + Learning + Memory):")
        for component, loaded in hermes_components.items():
            status_mark = "✓" if loaded else "✗"
            print(f"    {status_mark} {component}")
            
        print("  OpenClaw (Transport + Runtime + Infrastructure):")
        for component, loaded in openclaw_components.items():
            status_mark = "✓" if loaded else "!"
            print(f"    {status_mark} {component}")
            
        hermes_loaded = all(hermes_components.values())
        
        if hermes_loaded:
            print(f"  ✓ Responsibility split maintained")
            return True
        else:
            print(f"  ✗ Hermes components not fully loaded")
            return False
            
    except Exception as e:
        print(f"  ✗ Responsibility split test failed: {e}")
        return False


def test_cognitive_preservation():
    """Test that Hermes cognition is preserved (not replaced)."""
    print("\n=== Testing Cognitive Preservation ===")
    
    try:
        from integration.openclaw_bridge import OpenClawHermesBridge
        from cognition.cognitive_loop import CognitiveLoopCoordinator
        
        bridge = OpenClawHermesBridge(
            hermes_home=resolver.hermes_home,
            agents_dir=resolver.agents_dir
        )
        
        coordinator = bridge.cognitive_coordinator
        
        cognitive_state = coordinator.get_cognitive_state()
        
        checks = {
            'memory_stats': 'memory_stats' in cognitive_state,
            'behavior_profile': 'behavior_profile' in cognitive_state,
            'reflections': 'recent_reflections' in cognitive_state,
            'adaptations': 'active_adaptations' in cognitive_state
        }
        
        all_pass = True
        for check, passed in checks.items():
            status = "✓" if passed else "✗"
            print(f"  {status} {check}")
            if not passed:
                all_pass = False
                
        if all_pass:
            print(f"  ✓ Hermes cognition preserved and accessible")
            return True
        else:
            print(f"  ✗ Cognition components missing")
            return False
            
    except Exception as e:
        print(f"  ✗ Cognitive preservation test failed: {e}")
        return False


def test_integration_topology():
    """Test correct runtime topology."""
    print("\n=== Testing Runtime Topology ===")
    
    print("  Expected topology:")
    print("    OpenClaw Gateway")
    print("          ↓")
    print("    Hermes Gateway Runtime")
    print("          ↓")
    print("    Agent Runtime Layer")
    print("          ↓")
    print("    Memory + Reflection + Skills")
    print("          ↓")
    print("    Persistent Storage")
    
    try:
        from integration.openclaw_bridge import OpenClawHermesBridge
        
        bridge = OpenClawHermesBridge(
            hermes_home=resolver.hermes_home,
            agents_dir=resolver.agents_dir
        )
        
        status = bridge.get_bridge_status()
        
        topology_valid = (
            status['hermes_components']['cognitive_coordinator'] and
            status['hermes_components']['session_store'] and
            status['hermes_components']['identity_manager']
        )
        
        if topology_valid:
            print(f"  ✓ Topology correctly implemented")
            return True
        else:
            print(f"  ✗ Topology incomplete")
            return False
            
    except Exception as e:
        print(f"  ✗ Topology test failed: {e}")
        return False


def run_all_tests():
    """Run all Phase 17 validation tests."""
    print("=" * 60)
    print("PHASE 17: OPENCLAW INTEGRATION LAYER - VALIDATION")
    print("=" * 60)
    
    tests = [
        ("Bridge Initialization", test_bridge_initialization),
        ("Hermes Components", test_hermes_components),
        ("Message Routing", test_message_routing),
        ("Runtime Host", test_runtime_host),
        ("Responsibility Split", test_responsibility_split),
        ("Cognitive Preservation", test_cognitive_preservation),
        ("Integration Topology", test_integration_topology),
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
    print("PHASE 17 VALIDATION SUMMARY")
    print("=" * 60)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}: {name}")
        
    print(f"\nTotal: {passed}/{total} tests passed")
    
    if passed == total:
        print("\n✓ PHASE 17 VALIDATION COMPLETE - INTEGRATION LAYER OPERATIONAL")
        print("\n  OpenClaw HOSTS Hermes - does NOT replace cognition")
        return True
    else:
        print(f"\n✗ PHASE 17 VALIDATION INCOMPLETE - {total - passed} failures")
        return False


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)
