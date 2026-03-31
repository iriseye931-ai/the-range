#!/bin/bash
# Auto-store: fires on Stop hook. Forks worker to background and exits immediately.
# The worker handles the slow OpenViking storage (up to 120s) without blocking.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', ''))
except:
    pass
" 2>/dev/null)

TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path', ''))
except:
    pass
" 2>/dev/null)

# Fork slow work to background and exit immediately (hook timeout is irrelevant)
/Users/iris/.claude/hooks/auto-store-worker.sh "$SESSION_ID" "$TRANSCRIPT_PATH" &
disown

/Users/iris/.claude/hooks/subconscious-worker.sh "$SESSION_ID" "$TRANSCRIPT_PATH" &
disown

exit 0
