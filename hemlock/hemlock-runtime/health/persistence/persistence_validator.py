#!/usr/bin/env python3
"""
Persistence validator for Hermes/OpenClaw framework.
Checks that persistence mechanisms are available.
"""
import sys
import os
import tempfile
from dataclasses import dataclass
from typing import List


@dataclass
class CheckResult:
    name: str
    status: str
    detail: str = ""
    path: str = ""


def test_persistence(fix=False) -> List[CheckResult]:
    """Test that we can write and read from persistence layer."""
    results = []
    
    try:
        # Test SQLite
        import sqlite3
        with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
            db_path = f.name
        try:
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute("CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, data TEXT)")
            cursor.execute("INSERT INTO test (data) VALUES (?)", ("test",))
            conn.commit()
            cursor.execute("SELECT data FROM test WHERE id=1")
            row = cursor.fetchone()
            if row and row[0] == "test":
                results.append(CheckResult("persistence_sqlite", "ok", "SQLite persistence test passed", db_path))
            else:
                results.append(CheckResult("persistence_sqlite", "fail", "SQLite persistence test failed: data mismatch", db_path))
            conn.close()
        finally:
            os.unlink(db_path)
        
        # Test JSON persistence
        import json
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json_path = f.name
            json.dump({"test": "data"}, f)
        try:
            with open(json_path, 'r') as f:
                data = json.load(f)
            if data.get("test") == "data":
                results.append(CheckResult("persistence_json", "ok", "JSON persistence test passed", json_path))
            else:
                results.append(CheckResult("persistence_json", "fail", "JSON persistence test failed: data mismatch", json_path))
        finally:
            os.unlink(json_path)
            
    except Exception as e:
        results.append(CheckResult("persistence_error", "fail", f"Unexpected error: {type(e).__name__}: {e}"))
    
    return results


if __name__ == "__main__":
    results = test_persistence()
    all_ok = all(r.status != "fail" for r in results)
    sys.exit(0 if all_ok else 1)
