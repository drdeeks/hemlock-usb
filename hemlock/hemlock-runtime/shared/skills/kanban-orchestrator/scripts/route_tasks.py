#!/usr/bin/env python3
"""
Kanban Orchestrator - Route Tasks Script
Routes decomposed tasks to appropriate agent profiles.
"""
import json
import sys
import os
from pathlib import Path

def route_tasks(decomposition, available_profiles):
    """Route tasks to appropriate profiles."""
    routing = {
        "assignments": [],
        "unassigned": []
    }
    
    for subtask in decomposition.get("subtasks", []):
        suggested = subtask.get("suggested_profile", "")
        
        # Check if suggested profile is available
        if suggested in available_profiles:
            routing["assignments"].append({
                "task": subtask["name"],
                "profile": suggested,
                "status": "ready"
            })
        else:
            # Try to find a suitable profile
            assigned = False
            for profile in available_profiles:
                if any(keyword in profile.lower() for keyword in subtask["name"].lower().split()):
                    routing["assignments"].append({
                        "task": subtask["name"],
                        "profile": profile,
                        "status": "ready"
                    })
                    assigned = True
                    break
            
            if not assigned:
                routing["unassigned"].append({
                    "task": subtask["name"],
                    "reason": "No suitable profile found"
                })
    
    return routing

def main():
    if len(sys.argv) < 3:
        print("Usage: route_tasks.py <decomposition.json> <profile1,profile2,...>")
        sys.exit(1)
    
    # Load decomposition from file
    with open(sys.argv[1], 'r') as f:
        decomposition = json.load(f)
    
    profiles = sys.argv[2].split(",")
    
    result = route_tasks(decomposition, profiles)
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()