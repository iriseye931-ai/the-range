#!/bin/bash
# Subconscious worker — fires on Stop hook.
# Uses MLX to update structured memory blocks from transcript + git state.
# Improvements: last_session.md snapshot, pending pruning, project_context updates.

SESSION_ID="${1:-unknown}"
TRANSCRIPT_PATH="${2:-}"
MLX_URL="http://127.0.0.1:8081"
SUB_DIR="$HOME/.claude/subconscious"
LOG="$HOME/.claude/hooks/auto-store.log"
DATE=$(date '+%Y-%m-%d')

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] subconscious: $*" >> "$LOG"; }

# Git backup — defined first so it can be called anywhere
do_git_backup() {
    local BACKUP_REPO="$HOME/Projects/mission-control-dashboard"
    local BACKUP_DIR="$BACKUP_REPO/.claude-subconscious"
    if [ -d "$BACKUP_REPO/.git" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$SUB_DIR/"*.md "$BACKUP_DIR/" 2>/dev/null
        cd "$BACKUP_REPO" || return
        git add ".claude-subconscious/" 2>/dev/null
        local CHANGES
        CHANGES=$(git diff --cached --name-only 2>/dev/null)
        if [ -n "$CHANGES" ]; then
            git commit -m "chore: subconscious memory update $DATE [skip ci]" 2>/dev/null
            log "subconscious blocks committed to git"
        fi
    fi
}

# Tmp flag cleanup — remove flags older than 7 days
find /tmp -name "subconscious-*" -mtime +7 -delete 2>/dev/null

log "worker start session=$SESSION_ID"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    log "no transcript, skipping"
    do_git_backup
    exit 0
fi

# Check MLX is up
if ! curl -sf --max-time 3 "$MLX_URL/v1/models" > /dev/null 2>&1; then
    log "MLX not reachable, skipping MLX update — doing git backup only"
    do_git_backup
    exit 0
fi

# Extract conversation from transcript
CONVO=$(python3 -c "
import sys, json

def get_text(content):
    if isinstance(content, str): return content.strip()
    if isinstance(content, list):
        parts = []
        for c in content:
            if isinstance(c, dict):
                if c.get('type') == 'text': parts.append(c.get('text',''))
        return ' '.join(parts).strip()
    return ''

lines = open('$TRANSCRIPT_PATH', encoding='utf-8', errors='ignore').read().strip().split('\n')
msgs = []
for line in lines[-150:]:
    if not line.strip(): continue
    try:
        d = json.loads(line)
        msg = d.get('message', d)
        role = msg.get('role','')
        content = get_text(msg.get('content',''))
        if role in ('user','assistant') and content and len(content) > 20:
            label = 'Punch' if role == 'user' else 'Atlas'
            msgs.append(f'{label}: {content[:350]}')
    except: pass
print('\n'.join(msgs[-25:]))
" 2>/dev/null)

if [ -z "$CONVO" ]; then
    log "no conversation extracted"
    do_git_backup
    exit 0
fi

# Get git context from active repos
GIT_CONTEXT=""
for repo in "$HOME/Projects/mission-control-dashboard" "$HOME/Projects/OpenViking" "$HOME/Projects/claude-hud" "$HOME/Projects/worldmonitor"; do
    if [ -d "$repo/.git" ]; then
        CHANGES=$(cd "$repo" && git diff --name-only HEAD 2>/dev/null | head -10)
        RECENT=$(cd "$repo" && git log --oneline -3 2>/dev/null)
        if [ -n "$CHANGES" ] || [ -n "$RECENT" ]; then
            GIT_CONTEXT="$GIT_CONTEXT\n$(basename $repo) changed: $CHANGES | recent: $RECENT"
        fi
    fi
done

# Read current blocks
PENDING=$(cat "$SUB_DIR/pending_items.md" 2>/dev/null | head -60)
GUIDANCE=$(cat "$SUB_DIR/guidance.md" 2>/dev/null | head -30)
PROJECT=$(cat "$SUB_DIR/project_context.md" 2>/dev/null | head -50)
PENDING_LINES=$(wc -l < "$SUB_DIR/pending_items.md" 2>/dev/null || echo 0)

# Ask MLX to analyze session and generate structured updates
UPDATES=$(python3 -c "
import json, urllib.request

convo = open('/dev/stdin').read()

prompt = '''You are updating structured memory blocks for an AI agent named Atlas working with Punch.
Today: $DATE. Session: $SESSION_ID

CONVERSATION:
''' + convo + '''

CURRENT PENDING ITEMS:
$PENDING

CURRENT GUIDANCE:
$GUIDANCE

CURRENT PROJECT CONTEXT (excerpt):
$PROJECT

GIT CHANGES THIS SESSION:
$GIT_CONTEXT

PENDING LINE COUNT: $PENDING_LINES

Analyze the conversation carefully. Output ONLY this exact JSON (no explanation, no markdown):
{
  \"completed_items\": [\"exact text of pending items completed or resolved this session\"],
  \"new_pending\": [\"new TODO items discovered this session not yet in pending\"],
  \"guidance_focus\": \"1-2 sentence current focus summary for next session\",
  \"guidance_suggestions\": [\"2-3 concrete next steps for Punch\"],
  \"project_context_update\": \"if any NEW ports, file paths, services, or architectural patterns were added this session, describe them concisely (1-3 sentences). Empty string if nothing changed.\",
  \"last_session_accomplished\": [\"3-5 bullet points: what was actually completed this session\"],
  \"last_session_changed\": [\"files or services that changed architecturally\"],
  \"last_session_open\": [\"open threads or unresolved items\"],
  \"session_summary\": \"one line: what this session accomplished\",
  \"needs_pending_prune\": ''' + ('true' if int('$PENDING_LINES') > 40 else 'false') + ''',
  \"pruned_pending\": \"if needs_pending_prune is true, rewrite pending_items.md content keeping only active/backlog/deferred items under 30 lines total. Empty string otherwise.\"
}'''

payload = json.dumps({
    'model': 'local',
    'messages': [{'role': 'user', 'content': prompt}],
    'max_tokens': 900,
    'temperature': 0.1,
    'stream': False,
})
req = urllib.request.Request(
    '$MLX_URL/v1/chat/completions',
    data=payload.encode(),
    headers={'Content-Type': 'application/json'},
)
try:
    with urllib.request.urlopen(req, timeout=45) as resp:
        d = json.load(resp)
        print(d['choices'][0]['message']['content'].strip())
except:
    print('')
" <<< "$CONVO" 2>/dev/null)

# Apply updates
_UPDATES_FILE=$(mktemp /tmp/subconscious-XXXXXX.json)
echo "$UPDATES" > "$_UPDATES_FILE"
python3 - "$_UPDATES_FILE" << 'PYEOF'
import json, os, re, sys
from pathlib import Path
from datetime import datetime

sub_dir = Path(os.environ['HOME']) / '.claude' / 'subconscious'
log_file = Path(os.environ['HOME']) / '.claude' / 'hooks' / 'auto-store.log'
date = datetime.now().strftime('%Y-%m-%d')

def log(msg):
    with open(log_file, 'a') as f:
        f.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] subconscious: {msg}\n")

updates_raw = open(sys.argv[1]).read()
match = re.search(r'\{.*\}', updates_raw, re.DOTALL)
if not match:
    log("no JSON in MLX response")
    sys.exit(0)

try:
    updates = json.loads(match.group())
except Exception as e:
    log(f"JSON parse error: {e}")
    sys.exit(0)

# ── 1. last_session.md — always overwrite with clean snapshot ──────────────
accomplished = updates.get('last_session_accomplished', [])
changed = updates.get('last_session_changed', [])
open_threads = updates.get('last_session_open', [])
summary = updates.get('session_summary', '').strip()

if accomplished or summary:
    acc_lines = '\n'.join(f'- {a}' for a in accomplished)
    chg_lines = '\n'.join(f'- {c}' for c in changed)
    open_lines = '\n'.join(f'- {o}' for o in open_threads)
    (sub_dir / 'last_session.md').write_text(
        f"# Last Session\n_Single-block snapshot. Always overwritten._\n\n"
        f"## Date\n{date}\n\n"
        f"## What was accomplished\n{acc_lines or '- (see session summary)'}\n\n"
        f"## What changed architecturally\n{chg_lines or '- nothing major'}\n\n"
        f"## Open threads\n{open_lines or '- none'}\n"
    )
    log(f"last_session.md updated: {summary}")

# ── 2. pending_items.md — prune if over limit, then add/complete ───────────
pending_path = sub_dir / 'pending_items.md'
pending_content = pending_path.read_text() if pending_path.exists() else ''
completed = updates.get('completed_items', [])
new_pending = updates.get('new_pending', [])
pruned = updates.get('pruned_pending', '').strip()

if pruned:
    # MLX rewrote the whole file — use it, then append completed section
    pending_content = pruned
    log("pending_items pruned by MLX")

if completed:
    block = '\n'.join(f'- {c} ✓' for c in completed)
    # Move completed items to a Completed section instead of appending raw
    if '## Completed' not in pending_content:
        pending_content += f'\n\n## Completed (recent)\n{block}'
    else:
        pending_content = re.sub(
            r'(## Completed.*?)(\n## |\Z)',
            lambda m: m.group(1) + '\n' + block + m.group(2),
            pending_content, flags=re.DOTALL
        )
    log(f"marked {len(completed)} items completed")

if new_pending:
    block = '\n'.join(f'- {p}' for p in new_pending)
    if '## Backlog' in pending_content:
        pending_content = pending_content.replace('## Backlog\n', f'## Backlog\n{block}\n')
    else:
        pending_content += f'\n\n## Backlog\n{block}'
    log(f"added {len(new_pending)} new pending items")

if completed or new_pending or pruned:
    pending_path.write_text(pending_content)

# ── 3. guidance.md — rewrite with fresh focus ─────────────────────────────
focus = updates.get('guidance_focus', '').strip()
suggestions = updates.get('guidance_suggestions', [])
if focus or suggestions:
    sugg_lines = '\n'.join(f'- {s}' for s in suggestions)
    (sub_dir / 'guidance.md').write_text(
        f"# Guidance\n_Updated {date}_\n\n## Current Focus\n{focus}\n\n## Suggestions for Next Session\n{sugg_lines}\n"
    )
    log("updated guidance.md")

# ── 4. project_context.md — append new architectural facts only ───────────
ctx = updates.get('project_context_update', '').strip()
if ctx:
    p = sub_dir / 'project_context.md'
    existing = p.read_text() if p.exists() else ''
    p.write_text(existing + f'\n\n## Updated {date}\n{ctx}')
    log("updated project_context.md")

# ── 5. session_patterns.md — append one-liner ─────────────────────────────
if summary:
    sp = sub_dir / 'session_patterns.md'
    content = sp.read_text() if sp.exists() else '# Session Patterns\n'
    sp.write_text(content + f'\n- {date}: {summary}')
    log(f"session: {summary}")

log("blocks updated")
PYEOF
rm -f "$_UPDATES_FILE"

do_git_backup
log "worker done"
exit 0
