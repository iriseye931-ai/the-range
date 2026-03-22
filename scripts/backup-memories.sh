#!/bin/bash
# backup-memories.sh — Snapshot OpenViking memory files on a schedule
# Run via cron or the provided LaunchAgent plist (every 30 min by default)
#
# Commits only markdown memory files — skips vectordb, model weights, etc.
# If the vector index ever breaks, run rebuild-index.py to restore it from
# these committed files.

set -euo pipefail

OV_DATA="${OV_DATA:-$HOME/.openviking/data}"
OV_ACCOUNT="${OV_ACCOUNT:-default}"
OV_USER="${OV_USER:-$(whoami)}"
CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/.claude/projects/memory}"
LOG="${OV_LOG:-$HOME/.openviking/logs/backup.log}"

mkdir -p "$(dirname "$LOG")"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

cd "$OV_DATA"

# Initialize git repo if needed
if [ ! -d ".git" ]; then
  git init
  git config user.email "${OV_USER}@iriseye.local"
  git config user.name "${OV_USER}"
  echo "vectordb/" >> .gitignore
  echo "*.bin" >> .gitignore
  echo "mlx-*/" >> .gitignore
  echo "atlas-lora/" >> .gitignore
fi

MEMORY_PATH="viking/${OV_ACCOUNT}/user/${OV_USER}/memories"

# Stage only memory markdown files
git add "$MEMORY_PATH" 2>/dev/null || true

# Also backup claude-code file-based memory if it exists
[ -d "$CLAUDE_MEMORY_DIR" ] && git add "$CLAUDE_MEMORY_DIR" 2>/dev/null || true

# Only commit if there are staged changes
if git diff --cached --quiet; then
  echo "[$(timestamp)] No changes to snapshot" >> "$LOG"
  exit 0
fi

CHANGED=$(git diff --cached --name-only | wc -l | tr -d ' ')
git commit -m "memory snapshot $(date '+%Y-%m-%d %H:%M') — ${CHANGED} file(s)" 2>/dev/null

echo "[$(timestamp)] Snapshot committed (${CHANGED} files)" >> "$LOG"
