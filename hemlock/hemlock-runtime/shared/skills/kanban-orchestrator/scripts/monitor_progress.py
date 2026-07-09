#!/usr/bin/env python3
"""
Kanban Orchestrator - Monitor Progress Script
Monitors the progress of decomposed tasks across profiles.
"""
import json
import sys
import os
from pathlib import Path
from datetime import datetime

def monitor_progress(assignments_file):
    """Monitor progress of task assignments."""
    try:
        with open(assignments_file, 'r') as f:
            assignments = json.load(f)
    except FileNotFoundError:
        return {"error": "Assignments file not found"}
    
    progress = {
        "timestamp": datetime.now().isoformat(),
        "total_tasks": len(assignments.get("assignments", [])),
        "completed": 0,
        "in_progress": 0,
        "pending": 0,
        "failed": 0,
        "details": []
    }
    
    for assignment in assignments.get("assignments", []):
        status = assignment.get("status", "unknown")
        
        if status == "completed":
            progress["completed"] += 1
        elif status == "in_progress":
            progress["in_progress"] += 1
        elif status == "ready" or status == "pending":
            progress["pending"] += 1
        elif status == "failed":
            progress["failed"] += 1
        
        progress["details"].append({
            "task": assignment.get("task"),
            "profile": assignment.get("profile"),
            "status": status
        })
    
    # Calculate completion percentage
    if progress["total_tasks"] > 0:
        progress["completion_percentage"] = round(
            (progress["completed"] / progress["total_tasks"]) * 100, 2
        )
    else:
        progress["completion_percentage"] = 0
    
    return progress

def main():
    if len(sys.argv) < 2:
        print("Usage: monitor_progress.py <assignments.json>")
        sys.exit(1)
    
    result = monitor_progress(sys.argv[1])
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()