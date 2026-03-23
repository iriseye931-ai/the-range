#!/bin/bash
# fabric-wrap.sh — wrapper that fixes the LM Studio jinja template issue
# Reads pattern, formats as proper user+system messages, calls LLM directly

PATTERN="$1"
LLM_BASE="${LLM_BASE_URL:-http://192.168.1.186:6698/v1}"
MODEL="${LLM_MODEL:-unsloth/qwen3.5-35b-a3b}"
PATTERNS_DIR="$HOME/.config/fabric/patterns"

if [[ -z "$PATTERN" ]]; then
  echo "Usage: echo 'input' | fabric-wrap.sh <pattern_name>"
  exit 1
fi

PATTERN_FILE="$PATTERNS_DIR/$PATTERN/system.md"
if [[ ! -f "$PATTERN_FILE" ]]; then
  echo "Pattern not found: $PATTERN"
  exit 1
fi

SYSTEM_PROMPT=$(cat "$PATTERN_FILE")
USER_INPUT=$(cat)  # read from stdin

python3 - <<PYEOF
import json, urllib.request, sys

system = """$SYSTEM_PROMPT"""
user = """$USER_INPUT"""

payload = {
    "model": "$MODEL",
    "messages": [
        {"role": "system", "content": system},
        {"role": "user", "content": user}
    ],
    "max_tokens": 2000
}

req = urllib.request.Request(
    "$LLM_BASE/chat/completions",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json", "Authorization": "Bearer local"},
    method="POST"
)

with urllib.request.urlopen(req, timeout=120) as resp:
    data = json.loads(resp.read())
    print(data["choices"][0]["message"]["content"])
PYEOF
