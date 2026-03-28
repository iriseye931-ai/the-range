#!/bin/bash
# PostToolUse observation hook — logs tool calls to OpenViking as lightweight observations.
# Inspired by claude-mem's observation capture, without the external service overhead.
# Fires after every tool use. Skips noisy/low-value tools to avoid spam.

SKIP_TOOLS="^(Bash|Read|Glob|Grep)$"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name', ''))
except:
    pass
" 2>/dev/null)

# Skip noisy tools
if echo "$TOOL_NAME" | grep -qE "$SKIP_TOOLS"; then
    exit 0
fi

SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', ''))
except:
    pass
" 2>/dev/null)

TOOL_INPUT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    inp = d.get('tool_input', {})
    # Summarize key fields, truncate large values
    summary = {}
    for k, v in inp.items():
        s = str(v)
        summary[k] = s[:200] if len(s) > 200 else s
    print(json.dumps(summary))
except:
    print('{}')
" 2>/dev/null)

TOOL_RESPONSE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    resp = str(d.get('tool_response', ''))
    print(resp[:300] if len(resp) > 300 else resp)
except:
    print('')
" 2>/dev/null)

# Build observation content
CONTENT="Tool: $TOOL_NAME
Session: $SESSION_ID
Input: $TOOL_INPUT
Result: $TOOL_RESPONSE"

# Store to OpenViking via Memory MCP (fire and forget)
CONTENT_JSON=$(echo "$CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
curl -s -X POST "http://127.0.0.1:2033/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"tools/call\",
        \"params\": {
            \"name\": \"memory_store\",
            \"arguments\": { \"text\": $CONTENT_JSON }
        }
    }" \
    --max-time 5 \
    -o /dev/null 2>/dev/null &

disown
exit 0
