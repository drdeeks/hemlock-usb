#!/usr/bin/env python3
"""
Kanban Orchestrator - Decompose Task Script
Decomposes a complex task into subtasks for multi-agent routing.
"""
import json
import sys
import os
from pathlib import Path

def decompose_task(task_description, profiles=None):
    """Decompose a task into subtasks."""
    if profiles is None:
        profiles = []
    
    decomposition = {
        "original_task": task_description,
        "subtasks": [],
        "routing": {}
    }
    
    # Simple decomposition based on task keywords
    keywords = task_description.lower()
    
    if "research" in keywords or "analyze" in keywords:
        decomposition["subtasks"].append({
            "name": "research",
            "description": "Research and analyze the topic",
            "suggested_profile": profiles[0] if profiles else "researcher"
        })
    
    if "implement" in keywords or "build" in keywords or "code" in keywords:
        decomposition["subtasks"].append({
            "name": "implementation",
            "description": "Implement the solution",
            "suggested_profile": profiles[1] if len(profiles) > 1 else "developer"
        })
    
    if "test" in keywords or "verify" in keywords:
        decomposition["subtasks"].append({
            "name": "testing",
            "description": "Test and verify the implementation",
            "suggested_profile": profiles[2] if len(profiles) > 2 else "tester"
        })
    
    if "deploy" in keywords or "release" in keywords:
        decomposition["subtasks"].append({
            "name": "deployment",
            "description": "Deploy the solution",
            "suggested_profile": profiles[3] if len(profiles) > 3 else "deployer"
        })
    
    # If no specific keywords found, create generic subtasks
    if not decomposition["subtasks"]:
        decomposition["subtasks"] = [
            {"name": "analysis", "description": "Analyze requirements"},
            {"name": "implementation", "description": "Implement solution"},
            {"name": "verification", "description": "Verify results"}
        ]
    
    return decomposition

def main():
    if len(sys.argv) < 2:
        print("Usage: decompose_task.py <task_description> [profile1,profile2,...]")
        sys.exit(1)
    
    task = sys.argv[1]
    profiles = sys.argv[2].split(",") if len(sys.argv) > 2 else []
    
    result = decompose_task(task, profiles)
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()