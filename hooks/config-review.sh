#!/bin/bash
# PostToolUse hook — reviews config/settings/hook changes using local MLX.
# No Claude API usage. Fires async, does not block Atlas.

INPUT=$(cat)

# Parse tool name and file path
PARSED=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_name', '')
    inp = d.get('tool_input', {})
    path = inp.get('file_path', inp.get('notebook_path', ''))
    old = inp.get('old_string', '')[:400]
    new = inp.get('new_string', '')[:400]
    content = inp.get('content', '')[:600]
    print(json.dumps({'tool': tool, 'path': path, 'old': old, 'new': new, 'content': content}))
except:
    pass
" 2>/dev/null)

[ -z "$PARSED" ] && exit 0

FILE_PATH=$(echo "$PARSED" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])" 2>/dev/null)

# Only review config/settings/hook files
case "$FILE_PATH" in
    */.claude/settings*.json|\
    */.claude/hooks/*.sh|\
    */CLAUDE.md|\
    */.hermes/config.yaml|\
    */.hermes/SOUL.md|\
    */Library/LaunchAgents/*.plist|\
    */.mesh-subconscious.env|\
    */.atlas-telegram.env)
        : # proceed
        ;;
    *)
        exit 0
        ;;
esac

OLD=$(echo "$PARSED" | python3 -c "import sys,json; print(json.load(sys.stdin)['old'])" 2>/dev/null)
NEW=$(echo "$PARSED" | python3 -c "import sys,json; print(json.load(sys.stdin)['new'])" 2>/dev/null)
CONTENT=$(echo "$PARSED" | python3 -c "import sys,json; print(json.load(sys.stdin)['content'])" 2>/dev/null)

CHANGE=""
if [ -n "$OLD" ] || [ -n "$NEW" ]; then
    CHANGE="REMOVED:\n${OLD}\nADDED:\n${NEW}"
elif [ -n "$CONTENT" ]; then
    CHANGE="WRITTEN:\n${CONTENT}"
fi

LOG="$HOME/.claude/hooks/config-review.log"

# Run MLX review in background — does not block Atlas
(
python3 - "$FILE_PATH" "$CHANGE" "$LOG" << 'PYEOF'
import json, sys, urllib.request
from datetime import datetime

file_path, change, log = sys.argv[1], sys.argv[2], sys.argv[3]
mlx_url = "http://192.168.1.186:8081/v1/chat/completions"
date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

prompt = f"""You are Hermes, reviewing a config change made by Atlas (Claude Code).

File: {file_path}
Change:
{change}

Check for:
1. Missing files referenced (hooks, scripts that don't exist)
2. Hardcoded secrets or credentials
3. Hooks that would burn Claude API tokens (type: prompt or type: agent hooks)
4. LaunchAgent plists pointing to nonexistent scripts
5. Broken or circular dependencies
6. Anything that would cause unexpected behavior or cost

Respond with:
- STATUS: OK or ISSUE
- If ISSUE: one concise line per problem found
- If OK: one line confirming it looks clean"""

payload = json.dumps({
    "model": "/Users/iris/.mlx/models/Qwen3.5-35B-A3B-4bit",
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": 300,
    "temperature": 0.1,
    "stream": False
}).encode()

try:
    req = urllib.request.Request(mlx_url, data=payload, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        result = json.loads(r.read())["choices"][0]["message"]["content"].strip()
except Exception as e:
    result = f"MLX unavailable: {e}"

entry = f"[{date}] {file_path}\n{result}\n---\n"
with open(log, "a") as f:
    f.write(entry)

# If issue found, send Telegram alert via Hermes
if result.startswith("STATUS: ISSUE") or "ISSUE" in result.split("\n")[0]:
    try:
        amp_msg = f"[CONFIG REVIEW] Atlas changed {file_path}:\n{result}"
        import subprocess
        subprocess.run(
            ["/Users/iris/.local/bin/amp-send", "hermes", "config-issue", amp_msg, "--type", "task"],
            timeout=5, capture_output=True
        )
    except:
        pass
PYEOF
) &
disown

exit 0
