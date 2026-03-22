#!/usr/bin/env python3
"""
rebuild-index.py — Rebuild OpenViking vector index from existing memory files.

Use this after:
  - Changing the embedding model or dimension in ov.conf
  - Wiping the vectordb directory
  - A crash that left the index in a bad state

Re-stores each memory through the sessions API so they get re-embedded.
"""

import asyncio
import os
import sys
from pathlib import Path
import httpx

BASE_URL  = os.getenv("OV_BASE_URL",  "http://127.0.0.1:1933")
API_KEY   = os.getenv("OV_API_KEY",   "your-api-key")
ACCOUNT   = os.getenv("OV_ACCOUNT",   "default")
USER      = os.getenv("OV_USER",      os.getenv("USER", "user"))
AGENT_ID  = os.getenv("OV_AGENT_ID",  "claude")

MEMORIES_DIR = Path.home() / f".openviking/data/viking/{ACCOUNT}/user/{USER}/memories"

HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "X-OpenViking-Account": ACCOUNT,
    "X-OpenViking-User": USER,
    "X-OpenViking-Agent": AGENT_ID,
    "Content-Type": "application/json",
}


async def store_memory(client: httpx.AsyncClient, text: str, label: str) -> bool:
    resp = await client.post(f"{BASE_URL}/api/v1/sessions", headers=HEADERS, json={"metadata": {}})
    if resp.status_code != 200:
        print(f"  [fail] {label} — session create failed: {resp.status_code}")
        return False
    session_id = resp.json()["result"]["session_id"]

    await client.post(f"{BASE_URL}/api/v1/sessions/{session_id}/messages",
                      headers=HEADERS, json={"role": "user", "content": text})
    await client.post(f"{BASE_URL}/api/v1/sessions/{session_id}/messages",
                      headers=HEADERS, json={"role": "assistant", "content": "Understood. I have noted this information."})

    resp = await client.post(f"{BASE_URL}/api/v1/sessions/{session_id}/commit?wait=false",
                             headers=HEADERS, json={}, timeout=15)
    if resp.status_code not in (200, 202):
        print(f"  [warn] {label} — commit returned {resp.status_code}")
    return True


async def main():
    if not MEMORIES_DIR.exists():
        print(f"Memories directory not found: {MEMORIES_DIR}")
        print("Set OV_ACCOUNT and OV_USER env vars if your account/user differ from defaults.")
        sys.exit(1)

    subdirs = ["entities", "events", "preferences"]
    files = []
    for d in subdirs:
        p = MEMORIES_DIR / d
        if p.exists():
            for f in sorted(p.glob("*.md")):
                # skip abstract/overview index files
                if f.name.startswith("."):
                    continue
                files.append((d, f))

    print(f"Found {len(files)} memory files to re-index")
    print(f"  Account: {ACCOUNT}  User: {USER}  Server: {BASE_URL}")
    print()

    async with httpx.AsyncClient(timeout=130) as client:
        resp = await client.get(f"{BASE_URL}/health")
        if resp.json().get("healthy") is not True:
            print("OpenViking server not healthy — aborting")
            print(f"  Make sure OpenViking is running on {BASE_URL}")
            sys.exit(1)

        ok = 0
        for i, (category, fpath) in enumerate(files, 1):
            text = fpath.read_text().strip()
            if not text:
                print(f"  [skip] {category}/{fpath.name} — empty")
                continue
            label = f"{category}/{fpath.name}"
            print(f"  [{i}/{len(files)}] {label}")
            success = await store_memory(client, text, label)
            if success:
                ok += 1
            await asyncio.sleep(0.5)

    print()
    print(f"Done. {ok}/{len(files)} memories re-stored.")
    print("Extraction runs in background (~60-120s per memory).")
    print("Run a test search after a couple minutes to verify.")


if __name__ == "__main__":
    asyncio.run(main())
