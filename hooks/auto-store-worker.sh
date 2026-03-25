#!/bin/bash
# Claude Code Stop hook worker — auto-stores session summaries to OpenViking memory.
# Runs detached after the Stop hook fires, reads the session transcript,
# extracts summary + failures + wins, and stores them via the MCP server.
#
# Install:
#   1. Copy this file to ~/.claude/hooks/auto-store-worker.sh
#   2. chmod +x ~/.claude/hooks/auto-store-worker.sh
#   3. Add to ~/.claude/settings.json hooks section:
#        "Stop": [{ "matcher": "", "hooks": [{ "type": "command",
#          "command": "SESSION_ID=$CLAUDE_SESSION_ID TRANSCRIPT=$CLAUDE_TRANSCRIPT_PATH
#                      nohup ~/.claude/hooks/auto-store-worker.sh \"$CLAUDE_SESSION_ID\"
#                      \"$CLAUDE_TRANSCRIPT_PATH\" >> ~/.claude/hooks/auto-store.log 2>&1 &" }] }]

SESSION_ID="${1:-unknown}"
TRANSCRIPT_PATH="${2:-}"
MCP_URL="http://127.0.0.1:2033"
LOG="$HOME/.claude/hooks/auto-store.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "worker start session=$SESSION_ID"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    log "no transcript at '$TRANSCRIPT_PATH', skipping"
    exit 0
fi

# Check MCP is up
if ! curl -sf --max-time 3 -X POST "$MCP_URL/mcp" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d '{"jsonrpc":"2.0","id":0,"method":"ping"}' > /dev/null 2>&1; then
    log "MCP not reachable, skipping"
    exit 0
fi

store_to_memory() {
    local text="$1"
    local id="$2"
    curl -sf --max-time 150 \
        -X POST "$MCP_URL/mcp" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\", \"id\": $id, \"method\": \"tools/call\",
            \"params\": {
                \"name\": \"memory_store\",
                \"arguments\": {
                    \"text\": $(echo "$text" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
                }
            }
        }" 2>/dev/null
}

# Claude Code transcript format: each line is a JSON object with a nested
# "message" dict containing "role" and "content". Content may be a string
# or a list of typed parts ({"type":"text","text":"..."}).
extract_content() {
    python3 -c "
import sys, json

def get_text(content):
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for c in content:
            if isinstance(c, dict):
                if c.get('type') == 'text':
                    parts.append(c.get('text', ''))
                elif c.get('type') == 'tool_result':
                    for inner in (c.get('content') or []):
                        if isinstance(inner, dict) and inner.get('type') == 'text':
                            parts.append(inner.get('text', ''))
        return ' '.join(parts).strip()
    return ''

lines = sys.stdin.read().strip().split('\n')
messages = []
for line in lines:
    if not line.strip():
        continue
    try:
        d = json.loads(line)
        msg = d.get('message', d)  # Claude transcripts nest under 'message' key
        role = msg.get('role', '')
        content = get_text(msg.get('content', ''))
        if role in ('user', 'assistant') and content and len(content) > 20:
            messages.append((role, content))
    except:
        pass
print(json.dumps(messages))
"
}

MESSAGES_JSON=$(tail -120 "$TRANSCRIPT_PATH" | extract_content 2>/dev/null)

# Extract session summary
SUMMARY=$(echo "$MESSAGES_JSON" | python3 -c "
import sys, json
messages = json.load(sys.stdin)
recent = messages[-16:]
if recent:
    parts = [f'{r}: {c[:250]}' for r, c in recent]
    print('Session ' + sys.argv[1] + ': ' + ' | '.join(parts)[:1800])
" "$SESSION_ID" 2>/dev/null)

if [ -n "$SUMMARY" ]; then
    RESULT=$(store_to_memory "$SUMMARY" 1)
    log "summary stored: $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('content',[{}])[0].get('text','?')[:80])" 2>/dev/null)"
fi

# Scan for failure patterns
FAILURES=$(echo "$MESSAGES_JSON" | python3 -c "
import sys, json, re
messages = json.load(sys.stdin)
found = []
patterns = ['error','failed','exception','traceback','permission denied','connection refused','timeout','FAILED','ERROR','not found']
for role, content in messages:
    if len(content) > 10 and any(p.lower() in content.lower() for p in patterns):
        found.append(content[:180])
if found:
    print('|'.join(found[:4]))
" 2>/dev/null)

if [ -n "$FAILURES" ]; then
    FAIL_TEXT="FAILURE $(date '+%Y-%m-%d') session=$SESSION_ID: $FAILURES"
    RESULT=$(store_to_memory "$FAIL_TEXT" 2)
    log "failures stored: $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('content',[{}])[0].get('text','?')[:80])" 2>/dev/null)"
fi

# Extract wins: fixes, decisions, things that worked
WINS=$(echo "$MESSAGES_JSON" | python3 -c "
import sys, json, re
messages = json.load(sys.stdin)
found = []
win_patterns = [
    'fixed', 'resolved', 'working now', 'successfully', 'confirmed working',
    'instinct', 'learned', 'decided to', 'approach:', 'root cause:',
    'the fix was', 'this works because', 'key insight', 'important:'
]
for role, content in messages:
    if role != 'assistant':
        continue
    if len(content) > 30 and any(p.lower() in content.lower() for p in win_patterns):
        sentences = re.split(r'[.!?\n]', content)
        for s in sentences:
            if any(p.lower() in s.lower() for p in win_patterns) and len(s.strip()) > 20:
                found.append(s.strip()[:200])
                break
if found:
    print('WIN ' + sys.argv[1] + ': ' + ' | '.join(dict.fromkeys(found[:4])))
" "$SESSION_ID" 2>/dev/null)

if [ -n "$WINS" ]; then
    WINS_TEXT="$(date '+%Y-%m-%d') $WINS"
    RESULT=$(store_to_memory "$WINS_TEXT" 3)
    log "wins stored: $(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',{}).get('content',[{}])[0].get('text','?')[:80])" 2>/dev/null)"
fi

log "worker done"
exit 0
