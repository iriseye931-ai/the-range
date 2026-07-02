#!/usr/bin/env bash
# Correctly restart a mesh LaunchAgent so it re-reads its plist.
#
# `launchctl kickstart -k <label>` re-RUNS the job but keeps the env launchd
# cached when the job was first loaded — so an edited plist (new key, new
# path, new port) is NOT picked up. Only bootout + bootstrap reloads the
# definition from disk. This wrapper does it right.
#
# Usage: scripts/restart-service.sh local.openviking-mcp
set -euo pipefail

label="${1:?usage: restart-service.sh <launchd-label, e.g. local.openviking-mcp>}"
plist="$HOME/Library/LaunchAgents/${label}.plist"
[ -f "$plist" ] || { echo "no plist at $plist" >&2; exit 1; }

launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "✓ reloaded ${label} (plist re-read from disk)"
