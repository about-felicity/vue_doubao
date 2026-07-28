#!/usr/bin/env python3
"""Fetch the latest stats from the local dynamic dashboard and rebuild the static site.

Run this after the local DouBao crawler finishes, then push the updated dist/ to GitHub
and deploy to the server.
"""
import json
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

BASE_URL = "http://127.0.0.1:8765/api/stats"
OUT_FILE = Path(__file__).with_name("src") / "snapshots.json"


def fetch(url, timeout=60):
    print(f"Fetching {url} ...")
    req = urllib.request.Request(url, headers={"Cache-Control": "no-store"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    base = fetch(BASE_URL)
    questions = [q["question"] for q in base.get("questions", [])]

    snapshots = {"__all__": base}
    for question in questions:
        url = f"{BASE_URL}?{urllib.parse.urlencode({'question': question})}"
        snapshots[question] = fetch(url)

    OUT_FILE.write_text(json.dumps(snapshots, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved {len(snapshots)} snapshots to {OUT_FILE}")

    print("Building static site...")
    result = subprocess.run(["npm", "run", "build"], cwd=Path(__file__).parent)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
