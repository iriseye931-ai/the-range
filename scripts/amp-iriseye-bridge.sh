#!/bin/bash
# =============================================================================
# AMP → iriseye Bridge  (smart routing)
# =============================================================================
# Watches iriseye's AMP inbox and routes messages:
#   type=task  → openclaw agent -m (full agent with browser, terminal, etc.)
#   everything → MLX direct         (~1-2s round-trip, no tool overhead)
#
# Run as a daemon (LaunchAgent: local.amp-iriseye-bridge)
# =============================================================================

export CLAUDE_AGENT_NAME="iriseye"
INBOX="$HOME/.agent-messaging/agents/iriseye/messages/inbox"
PROCESSED="$HOME/.agent-messaging/agents/iriseye/messages/processed"
LOG="$HOME/.agent-messaging/agents/iriseye/bridge.log"
MLX_URL="http://192.168.1.186:8081/v1/chat/completions"
MLX_MODEL="/Users/iris/.mlx/models/Qwen3.5-35B-A3B-4bit"
POLL_INTERVAL=5

mkdir -p "$INBOX" "$PROCESSED"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

log "AMP-iriseye bridge started (PID $$)"

# ---------------------------------------------------------------------------
# respond_mlx: fast path — direct MLX inference, no tools (~1-2s)
# ---------------------------------------------------------------------------
respond_mlx() {
    local prompt="$1"
    python3 - "$prompt" "$MLX_URL" "$MLX_MODEL" <<'PYEOF'
import json, sys, urllib.request
prompt, url, model = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.dumps({
    "model": model,
    "messages": [
        {"role": "system", "content": "You are iriseye, an AI agent on the teamirs mesh. You specialize in file operations, web research, and automation tasks. Respond concisely and directly. No greetings or preamble."},
        {"role": "user", "content": prompt}
    ],
    "max_tokens": 1024,
    "stream": False
}).encode()
req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=90) as r:
        print(json.loads(r.read())["choices"][0]["message"]["content"])
except Exception as e:
    print(f"MLX error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# ---------------------------------------------------------------------------
# respond_iriseye: tool path — full openclaw agent (browser, terminal, file ops)
# ---------------------------------------------------------------------------
respond_iriseye() {
    local prompt="$1"
    cd "$HOME" && openclaw agent -m "$prompt" 2>/dev/null
}

# ---------------------------------------------------------------------------
# process_message: claim, parse, route, reply
# ---------------------------------------------------------------------------
process_message() {
    local msg_file="$1"
    local msg_id
    msg_id=$(basename "$msg_file" .json)

    # Atomic claim — prevents double-processing on restart
    local claimed="$PROCESSED/${msg_id}.json"
    mv "$msg_file" "$claimed" 2>/dev/null || return 0

    # Parse all fields in one python call (filename via sys.argv — no injection)
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
    print('{}', file=sys.stdout)
    print(f'parse error: {e}', file=sys.stderr)
PYEOF
)

    local from subject msg_type body
    from=$(      echo "$parsed" | python3 -c "import sys,json;d=json.loads(sys.stdin.read());print(d.get('from',''))"      2>/dev/null)
    subject=$(   echo "$parsed" | python3 -c "import sys,json;d=json.loads(sys.stdin.read());print(d.get('subject',''))"   2>/dev/null)
    local thread_id
    thread_id=$( echo "$parsed" | python3 -c "import sys,json;d=json.loads(sys.stdin.read());print(d.get('thread_id',''))" 2>/dev/null)
    msg_type=$(  echo "$parsed" | python3 -c "import sys,json;d=json.loads(sys.stdin.read());print(d.get('type',''))"      2>/dev/null)
    body=$(      echo "$parsed" | python3 -c "import sys,json;d=json.loads(sys.stdin.read());print(d.get('body',''))"      2>/dev/null)

    if [ -z "$body" ]; then
        log "[$msg_id] empty body — skipping"
        return 0
    fi

    # Route decision
    local route="mlx"
    [ "$msg_type" = "task" ] && route="iriseye"

    log "[$msg_id] from=${from:-unknown} type=$msg_type route=$route subject='$subject'"

    local prompt="[AMP from ${from:-unknown}] Subject: $subject | Type: $msg_type

$body"

    (
        local response exit_code
        if [ "$route" = "iriseye" ]; then
            response=$(respond_iriseye "$prompt")
            exit_code=$?
        else
            response=$(respond_mlx "$prompt")
            exit_code=$?
        fi

        if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
            log "[$msg_id] responded via $route (${#response} chars)"

            if [ -n "$from" ]; then
                local sender_addr="${from%%@*}"
                local ctx
                ctx=$(python3 -c "
import json,sys; print(json.dumps({'thread_id':sys.argv[1],'reply_to_amp':sys.argv[2],'route':sys.argv[3]}))" \
                    "$thread_id" "$msg_id" "$route" 2>/dev/null) || ctx='{}'

                amp-send "$sender_addr" "Re: $subject" "$response" \
                    --type response \
                    --context "$ctx" \
                    >> "$LOG" 2>&1 \
                    && log "[$msg_id] reply sent to $from" \
                    || log "[$msg_id] reply failed to $from"
            fi
        else
            log "[$msg_id] no response from $route (exit=$exit_code)"
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
