#!/usr/bin/env python3
"""
TV Sitcom Show MCP Server — Exposes the agent TV room as an MCP server
for external company integration.
"""

import asyncio
import json
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict

# FastMCP for MCP server
try:
    from fastmcp import FastMCP
except ImportError:
    print("Installing fastmcp...")
    import subprocess
    subprocess.run(["pip", "install", "fastmcp"], check=True)
    from fastmcp import FastMCP

# Load environment
PORT = int(os.getenv("TV_MCP_PORT", "41208"))
HOST = os.getenv("TV_MCP_HOST", "0.0.0.0")
VAULT_PATH = Path(os.getenv("TV_VAULT_PATH", "${WORKSPACE_ROOT}/qwen-cloud-2026/memory"))

# ============================================================================
# Data Models
# ============================================================================

@dataclass
class AgentSnapshot:
    agent_id: str
    name: str
    role: str
    project: str
    status: str
    avatar: str
    room: str
    last_seen: str
    metrics: Dict[str, Any]

@dataclass
class RoomSnapshot:
    room_id: str
    project: str
    agents: List[AgentSnapshot]
    capacity: int
    is_production: bool

@dataclass
class TVFeedEntry:
    timestamp: str
    event_type: str
    agent_id: str
    agent_name: str
    project: str
    message: str
    priority: str

# ============================================================================
# TV Room State Manager
# ============================================================================

class TVRoomManager:
    def __init__(self, vault_path: Path):
        self.vault_path = vault_path
        self.projects = {
            "mnemosyne": {"name": "Mnemosyne", "emoji": "🧠", "color": "#3b82f6"},
            "agora": {"name": "Agora", "emoji": "🏛️", "color": "#f59e0b"},
            "aires": {"name": "Aires", "emoji": "🎬", "color": "#a855f7"},
            "autopilot": {"name": "Autopilot", "emoji": "⚙️", "color": "#22c55e"},
            "edgewalker": {"name": "Edgewalker", "emoji": "⚡", "color": "#ef4444"},
        }
        self.max_per_room = 35
    
    def get_all_rooms(self) -> List[RoomSnapshot]:
        rooms = []
        for project_id, project_info in self.projects.items():
            for room_num in range(1, 4):
                room_id = f"{project_id.upper()}-ROOM-{room_num}"
                agents = self._get_agents_for_room(project_id, room_num)
                rooms.append(RoomSnapshot(
                    room_id=room_id,
                    project=project_id,
                    agents=agents,
                    capacity=self.max_per_room,
                    is_production=room_num == 1
                ))
        return rooms
    
    def _get_agents_for_room(self, project_id: str, room_num: int) -> List[AgentSnapshot]:
        agents = []
        base_idx = (room_num - 1) * self.max_per_room
        for i in range(min(self.max_per_room, 8)):
            idx = base_idx + i + 1
            agents.append(AgentSnapshot(
                agent_id=f"{project_id[:2].upper()}-{idx:02d}",
                name=f"Agent {idx}",
                role=self._get_role(project_id, idx),
                project=project_id,
                status="active" if idx % 3 != 0 else "idle",
                avatar=self._get_avatar(project_id, idx),
                room=f"{project_id.upper()}-ROOM-{room_num}",
                last_seen=datetime.utcnow().isoformat() + "Z",
                metrics={"tasks_done": idx * 3, "errors": idx % 2}
            ))
        return agents
    
    def _get_role(self, project_id: str, idx: int) -> str:
        roles = {
            "mnemosyne": ["Scribe", "Indexer", "Recall", "Forgetter", "Learner", "Graph", "Shadow", "Privacy"],
            "agora": ["Legislator", "Judge", "Marshal", "Debater", "Voter", "Mesh", "Deception", "Policy"],
            "aires": ["Director", "Script", "Editor", "Casting", "Continuity", "Cost", "Shotlist", "Lighting"],
            "autopilot": ["Kernel", "Sovereign", "Connector", "Inference", "Operator", "Cynic", "Frontend", "Auditor"],
            "edgewalker": ["Runtime", "Watcher", "Mesh", "Deception", "Policy", "Runtime", "Watcher", "Mesh"]
        }
        return roles.get(project_id, ["Agent"])[idx % 8]
    
    def _get_avatar(self, project_id: str, idx: int) -> str:
        emojis = ["🤖", "🧠", "🎨", "⚙️", "🔍", "📊", "🛡️", "⚡"]
        return emojis[idx % len(emojis)]
    
    def get_tv_feed(self, limit: int = 50) -> List[TVFeedEntry]:
        feed = []
        events = [
            ("agent_registered", "joined the production", "high"),
            ("task_completed", "finished a task", "normal"),
            ("room_changed", "moved to production room", "high"),
            ("heartbeat", "sent heartbeat", "low"),
            ("error", "encountered an error", "high"),
        ]
        for i in range(limit):
            project = list(self.projects.keys())[i % 5]
            agent_idx = i + 1
            event_type, msg, priority = events[i % len(events)]
            feed.append(TVFeedEntry(
                timestamp=datetime.utcnow().isoformat() + "Z",
                event_type=event_type,
                agent_id=f"{project[:2].upper()}-{agent_idx:02d}",
                agent_name=f"Agent {agent_idx}",
                project=project,
                message=msg,
                priority=priority
            ))
        return feed

# ============================================================================
# MCP Server Setup
# ============================================================================

mcp = FastMCP("TV Sitcom Show")
tv_manager = TVRoomManager(VAULT_PATH)

# ============================================================================
# MCP Tools
# ============================================================================

@mcp.tool()
def get_all_rooms() -> List[Dict[str, Any]]:
    """Get all production rooms across all projects with agent counts."""
    rooms = tv_manager.get_all_rooms()
    return [
        {
            "room_id": r.room_id,
            "project": r.project,
            "project_name": tv_manager.projects[r.project]["name"],
            "project_emoji": tv_manager.projects[r.project]["emoji"],
            "agent_count": len(r.agents),
            "capacity": r.capacity,
            "utilization": round(len(r.agents) / r.capacity * 100, 1),
            "is_production": r.is_production,
            "agents": [asdict(a) for a in r.agents[:5]]
        }
        for r in rooms
    ]

@mcp.tool()
def get_room(room_id: str) -> Dict[str, Any]:
    """Get detailed view of a specific production room."""
    rooms = tv_manager.get_all_rooms()
    for r in rooms:
        if r.room_id == room_id:
            return {
                "room_id": r.room_id,
                "project": r.project,
                "project_name": tv_manager.projects[r.project]["name"],
                "project_emoji": tv_manager.projects[r.project]["emoji"],
                "project_color": tv_manager.projects[r.project]["color"],
                "agents": [asdict(a) for a in r.agents],
                "capacity": r.capacity,
                "utilization": round(len(r.agents) / r.capacity * 100, 1),
                "is_production": r.is_production
            }
    return {"error": f"Room {room_id} not found"}

@mcp.tool()
def get_tv_feed(limit: int = 50, project: str = None, priority: str = None) -> List[Dict[str, Any]]:
    """Get live TV feed of agent activity across all projects."""
    feed = tv_manager.get_tv_feed(limit * 2)
    
    if project:
        feed = [f for f in feed if f.project == project]
    if priority:
        feed = [f for f in feed if f.priority == priority]
    
    return [asdict(f) for f in feed[:limit]]

@mcp.tool()
def get_agent(agent_id: str) -> Dict[str, Any]:
    """Get detailed agent profile."""
    rooms = tv_manager.get_all_rooms()
    for r in rooms:
        for a in r.agents:
            if a.agent_id == agent_id:
                return asdict(a)
    return {"error": f"Agent {agent_id} not found"}

@mcp.tool()
def get_project_summary(project: str) -> Dict[str, Any]:
    """Get summary stats for a project."""
    if project not in tv_manager.projects:
        return {"error": f"Project {project} not found"}
    
    rooms = tv_manager.get_all_rooms()
    project_rooms = [r for r in rooms if r.project == project]
    total_agents = sum(len(r.agents) for r in project_rooms)
    active_agents = sum(len([a for a in r.agents if a.status == "active"]) for r in project_rooms)
    
    return {
        "project": project,
        "name": tv_manager.projects[project]["name"],
        "emoji": tv_manager.projects[project]["emoji"],
        "color": tv_manager.projects[project]["color"],
        "rooms": len(project_rooms),
        "total_agents": total_agents,
        "active_agents": active_agents,
        "utilization": round(total_agents / (len(project_rooms) * 35) * 100, 1) if project_rooms else 0
    }

@mcp.tool()
def get_system_status() -> Dict[str, Any]:
    """Get overall system health and stats."""
    rooms = tv_manager.get_all_rooms()
    total_agents = sum(len(r.agents) for r in rooms)
    active_agents = sum(len([a for a in r.agents if a.status == "active"]) for r in rooms)
    production_rooms = [r for r in rooms if r.is_production]
    
    return {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "projects": len(tv_manager.projects),
        "total_rooms": len(rooms),
        "production_rooms": len(production_rooms),
        "total_agents": total_agents,
        "active_agents": active_agents,
        "idle_agents": total_agents - active_agents,
        "global_utilization": round(total_agents / (len(rooms) * 35) * 100, 1) if rooms else 0,
        "projects": {p: tv_manager.projects[p]["name"] for p in tv_manager.projects}
    }

@mcp.tool()
def search_agents(query: str) -> List[Dict[str, Any]]:
    """Search agents by name, role, or project."""
    query = query.lower()
    results = []
    rooms = tv_manager.get_all_rooms()
    for r in rooms:
        for a in r.agents:
            if (query in a.name.lower() or 
                query in a.role.lower() or 
                query in a.project.lower() or
                query in a.agent_id.lower()):
                results.append(asdict(a))
    return results

# ============================================================================
# MCP Resources (for static data)
# ============================================================================

@mcp.resource("config://projects")
def projects_config() -> str:
    """Projects configuration."""
    return json.dumps({
        pid: {
            "name": info["name"],
            "emoji": info["emoji"],
            "color": info["color"]
        }
        for pid, info in tv_manager.projects.items()
    }, indent=2)

@mcp.resource("config://rooms")
def rooms_config() -> str:
    """Rooms configuration schema."""
    return json.dumps({
        "max_per_room": tv_manager.max_per_room,
        "projects": {p: {"rooms": 3} for p in tv_manager.projects}
    }, indent=2)

# ============================================================================
# Entry Point
# ============================================================================

if __name__ == "__main__":
    print(f"Starting TV Sitcom Show MCP Server on {HOST}:{PORT}")
    mcp.run(transport="streamable-http", host=HOST, port=PORT)
