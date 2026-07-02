#!/usr/bin/env bash
# Rotate the OpenViking API key everywhere in one command.
#
# Tonight's incident: the key lived hardcoded in ~13 files, and launchd
# caches a job's env at load time — so `kickstart` runs the job again but
# does NOT pick up an edited plist. This script updates every location and
# reloads the launchd jobs correctly (bootout + bootstrap).
#
# Usage:
#   scripts/rotate-ov-key.sh                # generate a new key
#   scripts/rotate-ov-key.sh <explicit-key> # use a given key
set -euo pipefail

NEW="${1:-ov-$(openssl rand -hex 24)}"
SECRETS="$HOME/.openviking/secrets.env"

echo "→ new key: ${NEW:0:10}…"

# 1. Canonical file that Python consumers read.
umask 077
cat > "$SECRETS" <<EOF
# Canonical OpenViking secret — single source of truth. Rotate with rotate-ov-key.sh
OV_API_KEY=$NEW
OPENVIKING_KEY=$NEW
EOF
chmod 600 "$SECRETS"

# 2. Config files that define/consume the key by value (can't source a file).
#    ov.conf is the server's own authority; keep it in sync.
update() {  # file  key-name
  [ -f "$1" ] || return 0
  sed -i '' -E "s|(${2}[[:space:]]*[=:][[:space:]]*[\"']?)[A-Za-z0-9._-]+|\1${NEW}|g" "$1" \
    && echo "  updated $1"
}
update "$HOME/.openviking/ov.conf"                       "api_key"
update "$HOME/.hermes/.env"                              "(OV_API_KEY|OPENVIKING_KEY)"
update "$HOME/Projects/mission-control-dashboard/backend/.env" "(OV_API_KEY|OPENVIKING_KEY|OPENVIKING_API_KEY)"

# 3. LaunchAgent plists (env baked into the job).
for plist in "$HOME"/Library/LaunchAgents/local.openviking-*.plist \
             "$HOME"/Library/LaunchAgents/local.mcd-backend.plist; do
  [ -f "$plist" ] || continue
  perl -0777 -pi -e "s|(<key>OV_API_KEY</key>\s*<string>)[^<]+|\${1}${NEW}|g" "$plist" \
    && echo "  updated $(basename "$plist")"
done

# 4. Reload the launchd jobs so the new env actually takes effect.
for label in local.openviking-server local.openviking-mcp local.mcd-backend; do
  plist="$HOME/Library/LaunchAgents/$label.plist"
  [ -f "$plist" ] || continue
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null && echo "  reloaded $label"
done

echo "✓ rotated. Verify: old key should 401, new key 200."
