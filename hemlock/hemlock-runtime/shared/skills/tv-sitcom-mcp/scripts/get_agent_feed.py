#!/usr/bin/env python3
"""
TV Sitcom MCP - Agent Feed Script
Gets the agent feed from the TV MCP server.
"""
import json
import sys
import os
from pathlib import Path

def get_agent_feed(server_url="http://localhost:41208"):
    """Get agent feed from TV MCP server."""
    try:
        import urllib.request
        import urllib.error
        
        # Try to get agent feed
        response = urllib.request.urlopen(f"{server_url}/feed", timeout=5)
        
        if response.status == 200:
            data = json.loads(response.read().decode())
            return {
                "status": "ok",
                "feed": data.get("feed", []),
                "count": len(data.get("feed", [])),
                "latest": data.get("feed", [{}])[0] if data.get("feed") else None
            }
        else:
            return {
                "status": "error",
                "http_status": response.status
            }
    except urllib.error.URLError as e:
        return {
            "status": "error",
            "error": str(e)
        }
    except Exception as e:
        return {
            "status": "error",
            "error": str(e)
        }

def main():
    server_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:41208"
    result = get_agent_feed(server_url)
    print(json.dumps(result, indent=2))
    
    if result["status"] != "ok":
        sys.exit(1)

if __name__ == "__main__":
    main()