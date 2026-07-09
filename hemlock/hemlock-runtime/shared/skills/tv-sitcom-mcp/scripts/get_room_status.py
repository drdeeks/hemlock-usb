#!/usr/bin/env python3
"""
TV Sitcom MCP - Room Status Script
Gets the status of TV rooms from the MCP server.
"""
import json
import sys
import os
from pathlib import Path

def get_room_status(server_url="http://localhost:41208"):
    """Get room status from TV MCP server."""
    try:
        import urllib.request
        import urllib.error
        
        # Try to get room status
        response = urllib.request.urlopen(f"{server_url}/rooms", timeout=5)
        
        if response.status == 200:
            data = json.loads(response.read().decode())
            return {
                "status": "ok",
                "rooms": data.get("rooms", []),
                "count": len(data.get("rooms", []))
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
    result = get_room_status(server_url)
    print(json.dumps(result, indent=2))
    
    if result["status"] != "ok":
        sys.exit(1)

if __name__ == "__main__":
    main()