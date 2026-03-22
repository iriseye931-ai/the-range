#!/bin/bash
# start-mesh.sh — Start all iriseye mesh services
# Services: OpenViking (memory), AI Maestro (orchestration)
#
# Configure via environment or edit the variables below.
# Default paths assume install locations from the iriseye setup guide.

set -euo pipefail

OV_VENV="${OV_VENV:-$HOME/.openviking/venv/bin/python}"
OV_CONF="${OV_CONF:-$HOME/.openviking/ov.conf}"
OV_DATA="${OV_DATA:-$HOME/.openviking/data}"
OV_LOG="${OV_LOG:-$HOME/.openviking/logs/server.log}"
OV_PID="/tmp/openviking-server.pid"

MAESTRO_DIR="${MAESTRO_DIR:-$HOME/ai-maestro}"
MAESTRO_LOG="${MAESTRO_LOG:-$HOME/ai-maestro/logs/server.log}"
MAESTRO_PID="/tmp/ai-maestro.pid"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  [ok]${NC} $1"; }
fail() { echo -e "${RED}  [fail]${NC} $1"; }
info() { echo -e "${YELLOW}  [--]${NC} $1"; }

wait_for_port() {
  local port=$1 tries=20
  for i in $(seq 1 $tries); do
    if curl -s -o /dev/null "http://localhost:$port/health" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# ── OpenViking ──────────────────────────────────────────────────────────────
start_openviking() {
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:1933/health 2>/dev/null | grep -q "200"; then
    ok "OpenViking already running on :1933"
    return
  fi

  info "Starting OpenViking on :1933..."
  mkdir -p "$OV_DATA" "$(dirname "$OV_LOG")"

  OPENVIKING_CONFIG_FILE="$OV_CONF" \
  nohup "$OV_VENV" -c "
import uvicorn
from openviking.server import create_app
app = create_app()
uvicorn.run(app, host='0.0.0.0', port=1933)
" >> "$OV_LOG" 2>&1 &

  echo $! > "$OV_PID"

  if wait_for_port 1933; then
    ok "OpenViking up (pid $(cat $OV_PID))"
  else
    fail "OpenViking did not respond on :1933 — check $OV_LOG"
  fi
}

# ── AI Maestro ──────────────────────────────────────────────────────────────
start_maestro() {
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:23000/health 2>/dev/null | grep -qE "200|404"; then
    ok "AI Maestro already running on :23000"
    return
  fi

  info "Starting AI Maestro on :23000..."
  mkdir -p "$MAESTRO_DIR/logs"

  cd "$MAESTRO_DIR"
  PORT=23000 NODE_ENV=production \
  nohup bash scripts/start-with-ssh.sh >> "$MAESTRO_LOG" 2>&1 &

  echo $! > "$MAESTRO_PID"

  local tries=40
  for i in $(seq 1 $tries); do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:23000/ 2>/dev/null)
    if [[ "$code" =~ ^(200|404|301|302) ]]; then
      ok "AI Maestro up (pid $(cat $MAESTRO_PID))"
      return
    fi
    sleep 0.5
  done
  fail "AI Maestro did not respond on :23000 — check $MAESTRO_LOG"
}

# ── Status ──────────────────────────────────────────────────────────────────
check_status() {
  echo ""
  echo "── Service Status ──────────────────────────"

  local services=(
    "OpenViking:1933"
    "Memory MCP:2033"
    "OpenClaw MCP:2034"
    "OpenClaw Gateway:18789"
    "AI Maestro:23000"
    "Page Agent hub:38401"
  )

  for s in "${services[@]}"; do
    name="${s%%:*}"
    port="${s##*:}"
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/" 2>/dev/null)
    if [[ "$code" =~ ^(200|404|301|302) ]]; then
      ok "$name (:$port)"
    else
      fail "$name (:$port) — not responding"
    fi
  done

  echo ""
  local llm_host="${LLM_HOST:-192.168.1.186}:${LLM_PORT:-6698}"
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://$llm_host/v1/models" 2>/dev/null)
  if [[ "$code" == "200" ]]; then
    ok "Local LLM ($llm_host)"
  else
    fail "Local LLM ($llm_host) — check LLM_HOST / LLM_PORT env vars"
  fi
  echo "────────────────────────────────────────────"
}

echo "Starting iriseye mesh services..."
echo ""

start_openviking
start_maestro
check_status
