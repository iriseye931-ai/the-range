#!/bin/bash
# =============================================================================
# AMP → Hermes Bridge
# =============================================================================
# Watches Hermes's AMP inbox and processes messages via hermes chat -q.
# Replies back via AMP to the original sender.
#
# Run as a daemon (LaunchAgent: local.amp-hermes-bridge)
# =============================================================================

export CLAUDE_AGENT_NAME="hermes"
INBOX="$HOME/.agent-messaging/agents/hermes/messages/inbox"
PROCESSED="$HOME/.agent-messaging/agents/hermes/messages/processed"
LOG="$HOME/.agent-messaging/agents/hermes/bridge.log"
POLL_INTERVAL=5  # seconds

mkdir -p "$INBOX" "$PROCESSED"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "AMP-Hermes bridge started (PID $$)"

process_message() {
    local msg_file="$1"
    local msg_id
    msg_id=$(basename "$msg_file" .json)

    # Atomic claim: rename first to prevent double-processing on restart
    local claimed="$PROCESSED/${msg_id}.json"
    mv "$msg_file" "$claimed" 2>/dev/null || return 0  # already claimed by another instance

    # Parse all fields in one python call — pass filename as arg (no shell injection)
    local parsed
    parsed=$(python3 - "$claimed" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    env = d.get('envelope', {})
    pay = d.get('payload', {})
    print(json.dumps({
        'from':      env.get('from', ''),
        'subject':   env.get('subject', ''),
        'thread_id': env.get('thread_id', ''),
        'type':      pay.get('type', 'notification'),
        'body':      pay.get('message', '')
    }))
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    print('{}')
PYEOF
)

    local from subject thread_id type body
    from=$(      echo "$parsed" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('from',''))"      2>/dev/null)
    subject=$(   echo "$parsed" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('subject',''))"   2>/dev/null)
    local thread_id
    thread_id=$( echo "$parsed" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('thread_id',''))" 2>/dev/null)
    type=$(      echo "$parsed" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('type',''))"      2>/dev/null)
    body=$(      echo "$parsed" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('body',''))"      2>/dev/null)

    log "Processing $msg_id from=${from:-unknown} subject='$subject' type=$type"

    if [ -z "$body" ]; then
        log "Empty body in $msg_id — skipping"
        return 0
    fi

    # Build prompt and call MLX directly — ~1s vs 2-3min through full hermes stack
    local prompt="[AMP message from ${from:-unknown}]
Subject: $subject
Type: $type

$body"

    (
        local response
        response=$(python3 - "$prompt" <<'PYEOF'
import json, sys, urllib.request

prompt = sys.argv[1]
payload = json.dumps({
    "model": "/Users/iris/.mlx/models/Qwen3.5-35B-A3B-4bit",
    "messages": [
        {"role": "system", "content": "You are Hermes, a helpful AI agent on the teamirs mesh. Respond concisely to AMP messages from other agents. No greetings or preamble."},
        {"role": "user", "content": prompt}
    ],
    "max_tokens": 1024,
    "stream": False
}).encode()

req = urllib.request.Request(
    "http://192.168.1.186:8081/v1/chat/completions",
    data=payload,
    headers={"Content-Type": "application/json"}
)
try:
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.loads(r.read())
        print(d["choices"][0]["message"]["content"])
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)
        local exit_code=$?

        if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
            log "Hermes responded to $msg_id (${#response} chars)"

            if [ -n "$from" ]; then
                local sender_addr="${from%%@*}"
                # Safely build context JSON
                local ctx
                ctx=$(python3 -c "
import json, sys
print(json.dumps({'thread_id': sys.argv[1], 'reply_to_amp': sys.argv[2]}))" \
                    "$thread_id" "$msg_id" 2>/dev/null) || ctx='{}'

                amp-send "$sender_addr" "Re: $subject" "$response" \
                    --type response \
                    --context "$ctx" \
                    >> "$LOG" 2>&1 \
                    && log "Reply sent to $from" \
                    || log "Failed to send reply to $from"
            fi
        else
            log "Hermes no response for $msg_id (exit=$exit_code)"
        fi
    ) &
}

# Main polling loop
while true; do
    for msg_file in "$INBOX"/*.json; do
        [ -f "$msg_file" ] || continue
        process_message "$msg_file"
    done
    sleep "$POLL_INTERVAL"
done
