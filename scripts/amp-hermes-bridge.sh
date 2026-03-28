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

    # Parse message fields
    local from subject body type
    from=$(python3 -c "
import json, sys
d = json.load(open('$msg_file'))
print(d.get('envelope', {}).get('from', 'unknown'))
" 2>/dev/null)

    subject=$(python3 -c "
import json, sys
d = json.load(open('$msg_file'))
print(d.get('envelope', {}).get('subject', ''))
" 2>/dev/null)

    body=$(python3 -c "
import json, sys
d = json.load(open('$msg_file'))
print(d.get('payload', {}).get('message', ''))
" 2>/dev/null)

    type=$(python3 -c "
import json, sys
d = json.load(open('$msg_file'))
print(d.get('payload', {}).get('type', 'notification'))
" 2>/dev/null)

    thread_id=$(python3 -c "
import json, sys
d = json.load(open('$msg_file'))
print(d.get('envelope', {}).get('thread_id', ''))
" 2>/dev/null)

    log "Processing msg $msg_id from=$from subject='$subject' type=$type"

    # Build prompt for Hermes
    local prompt="[AMP message from $from]
Subject: $subject
Type: $type

$body"

    # Run Hermes single-query from home dir to avoid worktree issues
    local response
    response=$(cd "$HOME" && hermes chat -q "$prompt" 2>/dev/null)
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
        log "Hermes responded (${#response} chars)"

        # Send reply back via AMP if we know the sender
        if [ -n "$from" ] && [ "$from" != "unknown" ]; then
            # Extract sender name (before @)
            local sender_addr="${from%%@*}"
            amp-send "$sender_addr" "Re: $subject" "$response" \
                --type response \
                --context "{\"thread_id\": \"$thread_id\", \"reply_to_amp\": \"$msg_id\"}" \
                2>/dev/null && log "Reply sent to $from" || log "Failed to send reply to $from"
        fi
    else
        log "Hermes returned no response (exit=$exit_code)"
    fi

    # Move to processed
    mv "$msg_file" "$PROCESSED/${msg_id}.json"
    log "Moved $msg_id to processed"
}

# Main polling loop
while true; do
    for msg_file in "$INBOX"/*.json; do
        [ -f "$msg_file" ] || continue
        process_message "$msg_file"
    done
    sleep "$POLL_INTERVAL"
done
