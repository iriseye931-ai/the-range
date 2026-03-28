#!/bin/bash
# PostToolUse observation hook — logs tool calls to OpenViking as lightweight observations.
# Inspired by claude-mem's observation capture, without the external service overhead.
# Single python parse call. Skips noisy/low-value tools at both harness and script level.

INPUT=$(cat)

# One python call: parse, filter, and build the MCP payload
MCP_PAYLOAD=$(echo "$INPUT" | python3 -c "
import sys, json

SKIP = {'Bash', 'Read', 'Glob', 'Grep', 'ToolSearch', ''}

try:
    d = json.load(sys.stdin)
    tool_name  = d.get('tool_name', '')
    session_id = d.get('session_id', '')
    inp        = d.get('tool_input', {})
    resp       = str(d.get('tool_response', ''))

    if tool_name in SKIP:
        sys.exit(0)

    # For Edit/Write: log file path only, not content
    if tool_name in ('Edit', 'Write', 'NotebookEdit'):
        summary = {'file_path': inp.get('file_path', inp.get('notebook_path', ''))}
    else:
        summary = {k: str(v)[:200] for k, v in inp.items()}

    content = f'[observation] Tool: {tool_name} | Session: {session_id}\nInput: {json.dumps(summary)}\nResult: {resp[:300]}'

    print(json.dumps({
        'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call',
        'params': {'name': 'memory_store', 'arguments': {'text': content}}
    }))
except SystemExit:
    pass
except Exception:
    pass
" 2>/dev/null)

[ -z "$MCP_PAYLOAD" ] && exit 0

# Store to OpenViking via Memory MCP (fire and forget, timeout matches hook timeout)
curl -s -X POST "http://127.0.0.1:2033/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "$MCP_PAYLOAD" \
    --max-time 3 \
    -o /dev/null 2>/dev/null &

disown 2>/dev/null || true
exit 0
