#!/usr/bin/env python3
"""
graphrag-producer.py — collects mesh data and writes .md files for GraphRAG indexing.

Sources:
  - Claude session transcripts (~/.claude/projects/)
  - Hermes gateway logs (~/.hermes/logs/)
  - OpenViking memory files (~/.openviking/data/viking/)
  - zsh history (~/.zsh_history)

Output: ~/.graphrag/workspace/input/

Run daily or via LaunchAgent.
"""
import json
import os
import re
from datetime import datetime, timedelta
from pathlib import Path

OUTPUT_DIR = Path.home() / ".graphrag/workspace/input"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

CUTOFF = datetime.now() - timedelta(days=90)  # only index last 90 days


def write(name: str, content: str):
    if not content.strip():
        return
    path = OUTPUT_DIR / name
    path.write_text(content)
    print(f"  wrote {name} ({len(content)} chars)")


# ── 1. Claude session transcripts ────────────────────────────────────────────
def extract_claude_sessions():
    projects_dir = Path.home() / ".claude/projects"
    for project_dir in projects_dir.iterdir():
        if not project_dir.is_dir():
            continue
        project_name = project_dir.name.replace("-Users-iris-", "").replace("-Users-iris", "root")

        for jsonl in project_dir.glob("*.jsonl"):
            messages = []
            try:
                with open(jsonl) as f:
                    for line in f:
                        try:
                            d = json.loads(line)
                        except Exception:
                            continue
                        if d.get("type") not in ("user", "assistant"):
                            continue
                        msg = d.get("message", {})
                        role = msg.get("role", d.get("type", ""))
                        ts = d.get("timestamp", "")
                        content = msg.get("content", "")
                        if isinstance(content, list):
                            parts = []
                            for c in content:
                                if isinstance(c, dict) and c.get("type") == "text":
                                    parts.append(c["text"])
                            content = " ".join(parts)
                        if content and isinstance(content, str):
                            messages.append(f"[{ts[:16]}] {role.upper()}: {content[:2000]}")
            except Exception as e:
                print(f"  skip {jsonl.name}: {e}")
                continue

            if messages:
                session_id = jsonl.stem[:8]
                out = f"# Claude Session — {project_name} — {session_id}\n\n"
                out += "\n\n".join(messages)
                write(f"session-{project_name}-{session_id}.md", out)


# ── 2. Hermes logs ────────────────────────────────────────────────────────────
def extract_hermes_logs():
    log_paths = [
        Path.home() / ".hermes/logs/gateway.log",
        Path.home() / ".hermes/logs/gateway.error.log",
    ]
    for lp in log_paths:
        if not lp.exists():
            continue
        text = lp.read_text(errors="replace")
        # keep last 500 lines
        lines = text.strip().splitlines()[-500:]
        out = f"# Hermes Log — {lp.name}\n\n```\n" + "\n".join(lines) + "\n```\n"
        write(f"hermes-{lp.name}.md", out)


# ── 3. OpenViking memories ────────────────────────────────────────────────────
def extract_openviking_memories():
    base = Path.home() / ".openviking/data/viking"
    if not base.exists():
        return
    sections = []
    for account_dir in base.iterdir():
        if not account_dir.is_dir() or account_dir.name.startswith("_"):
            continue
        for md_file in account_dir.rglob("*.md"):
            try:
                content = md_file.read_text(errors="replace")
                rel = md_file.relative_to(base)
                sections.append(f"## {rel}\n\n{content}")
            except Exception:
                continue

    if sections:
        out = "# OpenViking Memory Snapshot\n\n" + "\n\n---\n\n".join(sections)
        write("openviking-memories.md", out)


# ── 4. zsh history (recent commands, deduplicated) ───────────────────────────
def extract_shell_history():
    hist = Path.home() / ".zsh_history"
    if not hist.exists():
        return
    raw = hist.read_text(errors="replace")
    # zsh extended history format: ": timestamp:elapsed;command"
    commands = []
    seen = set()
    for line in raw.splitlines():
        line = line.strip()
        m = re.match(r"^:\s*(\d+):\d+;(.+)$", line)
        if m:
            ts, cmd = int(m.group(1)), m.group(2)
            dt = datetime.fromtimestamp(ts)
            if dt < CUTOFF:
                continue
            if cmd not in seen:
                seen.add(cmd)
                commands.append(f"[{dt.strftime('%Y-%m-%d %H:%M')}] {cmd}")
        elif line and not line.startswith(":") and line not in seen:
            seen.add(line)
            commands.append(line)

    if commands:
        out = "# Shell History (last 90 days, deduplicated)\n\n```\n"
        out += "\n".join(commands[-2000:])  # cap at 2000
        out += "\n```\n"
        write("shell-history.md", out)


# ── Main ──────────────────────────────────────────────────────────────────────
print(f"GraphRAG producer — {datetime.now().strftime('%Y-%m-%d %H:%M')}")
print(f"Output: {OUTPUT_DIR}\n")

print("1. Claude sessions...")
extract_claude_sessions()

print("2. Hermes logs...")
extract_hermes_logs()

print("3. OpenViking memories...")
extract_openviking_memories()

print("4. Shell history...")
extract_shell_history()

print("\nDone. Run graphrag index when ready.")
