#!/usr/bin/env python3
"""
TV Sitcom MCP - Client Test Script
Tests connectivity to the TV MCP server.
"""
import json
import sys
import os
from pathlib import Path

def test_connection(server_url="http://localhost:41208"):
    """Test connection to TV MCP server."""
    try:
        import urllib.request
        import urllib.error
        
        # Try to connect to the server
        response = urllib.request.urlopen(f"{server_url}/health", timeout=5)
        
        if response.status == 200:
            return {
                "status": "connected",
                "server": server_url,
                "health": "ok"
            }
        else:
            return {
                "status": "error",
                "server": server_url,
                "health": f"HTTP {response.status}"
            }
    except urllib.error.URLError as e:
        return {
            "status": "disconnected",
            "server": server_url,
            "error": str(e)
        }
    except Exception as e:
        return {
            "status": "error",
            "server": server_url,
            "error": str(e)
        }

def main():
    server_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:41208"
    result = test_connection(server_url)
    print(json.dumps(result, indent=2))
    
    if result["status"] != "connected":
        sys.exit(1)

if __name__ == "__main__":
    main()