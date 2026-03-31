# Setup Guide

This is the exact setup we run. Follow it step by step and you'll have an identical mesh.

---

## Prerequisites

- macOS (LaunchAgents provided) or Linux (adapt plists to systemd)
- Python 3.11+
- Node.js 18+
- [Claude Code](https://claude.ai/code) installed and authenticated (`claude --version`)
- A local LLM server with OpenAI-compatible API
  - Recommended: [LM Studio](https://lmstudio.ai) or [Ollama](https://ollama.com)
  - You need **two models**: a chat/reasoning model and an embedding model
  - Tested: `unsloth/qwen3.5-35b-a3b` (chat) + `nomic-embed-text-v1.5` (embeddings, 768-dim)

---

## Directory layout

After setup, your machine will look like this:

```
~/.openviking/
├── venv/                        # Python venv with openviking + mcp deps
├── ov.conf                      # OpenViking config (API key, LLM endpoints)
├── data/                        # Git repo — memory files + vector index
│   └── viking/<account>/user/<user>/memories/
│       ├── entities/
│       ├── events/
│       └── preferences/
└── logs/

~/iriseye/  (or wherever you cloned)
├── backend/                     # FastAPI server on :8000
├── dashboard/                   # mission-control.html
├── mcp/                         # MCP servers (openviking :2033, openclaw :2034)
├── scripts/                     # start-mesh.sh, backup-memories.sh, rebuild-index.py
├── launchagents/                # macOS auto-start templates
└── config/

~/Library/LaunchAgents/
├── local.openviking-server.plist    # OpenViking on :1933
├── local.openviking-mcp.plist       # Memory MCP on :2033
├── local.openclaw-mcp.plist         # OpenClaw MCP on :2034 (optional)
├── local.mission-control-backend.plist  # FastAPI backend on :8000
└── local.memory-backup.plist        # 30-min memory snapshots
```

---

## Step 1 — Clone iriseye

```bash
git clone https://github.com/iriseye931-ai/iriseye ~/iriseye
cd ~/iriseye
```

---

## Step 2 — Install OpenViking

```bash
python3 -m venv ~/.openviking/venv
source ~/.openviking/venv/bin/activate
pip install openviking mcp[server] fastmcp httpx
```

Configure it:

```bash
mkdir -p ~/.openviking/data ~/.openviking/logs
cp config/ov.conf.example ~/.openviking/ov.conf
nano ~/.openviking/ov.conf
```

Fill in your values:
- `root_api_key` — any secret string, you'll use this everywhere
- `api_base` — your LLM server URL (e.g. `http://192.168.1.x:6698/v1`)
- `model` in both `embedding` and `vlm` sections
- **`"dimension": 768`** in the embedding section — must match your embedding model exactly
  - `nomic-embed-text-v1.5` → `768`
  - `text-embedding-ada-002` → `1536`
  - Wrong value = memory search returns nothing, no error

Initialize the data dir as a git repo:

```bash
cd ~/.openviking/data
git init
git config user.email "you@example.com"
git config user.name "your-name"
```

---

## Step 3 — Install LaunchAgents

All services auto-start on login and restart on crash.

**Edit paths in every plist before loading.** Replace `/path/to/` with your real paths.

```bash
# Copy all plist templates
cp ~/iriseye/launchagents/local.openviking-server.plist ~/Library/LaunchAgents/
cp ~/iriseye/launchagents/local.openviking-mcp.plist ~/Library/LaunchAgents/
cp ~/iriseye/launchagents/local.mission-control-backend.plist ~/Library/LaunchAgents/
cp ~/iriseye/launchagents/local.memory-backup.plist ~/Library/LaunchAgents/
```

Edit each one — at minimum update:
- All `/path/to/` references → your actual paths
- `OV_API_KEY` → your key from ov.conf
- `OV_ACCOUNT` / `OV_USER` → your account/username

Then load them all:

```bash
for plist in ~/Library/LaunchAgents/local.openviking-server.plist \
             ~/Library/LaunchAgents/local.openviking-mcp.plist \
             ~/Library/LaunchAgents/local.mission-control-backend.plist \
             ~/Library/LaunchAgents/local.memory-backup.plist; do
  launchctl load "$plist" && echo "loaded: $plist"
done
```

---

## Step 4 — Install the backend

```bash
cd ~/iriseye/backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
nano .env   # set OPENVIKING_KEY, LLM_URL, etc.
```

The backend LaunchAgent (step 3) uses uvicorn directly from the venv — make sure the paths match.

---

## Step 5 — Register memory tools with Claude Code

```bash
claude mcp add --transport http --scope user openviking-memory http://127.0.0.1:2033/mcp
```

Now Claude Code has `memory_recall`, `memory_store`, `memory_forget` in every session.

Test it:

```bash
claude -p "use memory_recall with query 'test' and show me what comes back"
```

---

## Step 6 — Add Page Agent (browser automation)

```bash
claude mcp add --scope user page-agent \
  -e LLM_BASE_URL=http://YOUR_LLM_HOST:PORT/v1 \
  -e LLM_MODEL_NAME=your-model-name \
  -e LLM_API_KEY=local \
  -- npx @page-agent/mcp
```

Install the [Page Agent Chrome extension](https://chromewebstore.google.com/search/page%20agent).
Once the extension connects, Claude Code can control your browser via `execute_task`.

---

## Step 7 — Add Hermes (long-running tasks + cron)

[Hermes](https://github.com/NousResearch/hermes-agent) by Nous Research handles scheduled automations and long-running tasks. Its cron state feeds into the dashboard automatically.

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
hermes model   # point it at your local LLM
```

The dashboard reads `~/.hermes/cron/jobs.json` — no extra config needed.

---

## Step 8 — Add Hermes (optional second agent)

If you have [Hermes](https://github.com/NousResearch/hermes-agent) installed:

```bash
cp ~/iriseye/launchagents/local.hermes-mcp.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/local.hermes-mcp.plist

# Register with Claude Code
claude mcp add --transport stdio --scope user hermes -- hermes mcp serve
```

---

## Step 9 — Verify everything

```bash
chmod +x ~/iriseye/scripts/start-mesh.sh
~/iriseye/scripts/start-mesh.sh
```

Expected output:
```
  [ok] OpenViking (:1933)
  [ok] Memory MCP (:2033)
  [ok] AI Maestro (:23000)       ← only if you have AI Maestro
  [ok] Page Agent hub (:38401)   ← only after page-agent MCP first runs
  [ok] Local LLM (host:port)
```

---

## Step 10 — Open the dashboard

Open `~/iriseye/dashboard/mission-control.html` in your browser.

It connects to `ws://localhost:8000/ws` and `http://localhost:8000/api/status`. If the backend is running you'll see live agent status, service health, memory activity, and Hermes cron jobs.

---

## Port reference

| Port | Service | Required |
|------|---------|---------|
| 1933 | OpenViking memory server | Yes |
| 2033 | Memory MCP (Claude Code tools) | Yes |
| 2034 | OpenClaw MCP | Optional |
| 8000 | Mission Control backend | Yes |
| 18789 | OpenClaw gateway | Optional |
| 23000 | AI Maestro | Optional |
| 38401 | Page Agent Chrome bridge | Optional |

---

## Troubleshooting

### memory_recall returns nothing

```bash
# 1. Wipe the broken vector index
rm -rf ~/.openviking/data/vectordb

# 2. Restart OpenViking
launchctl unload ~/Library/LaunchAgents/local.openviking-server.plist
launchctl load  ~/Library/LaunchAgents/local.openviking-server.plist

# 3. Re-index from disk files
OV_API_KEY=your-key OV_ACCOUNT=your-account OV_USER=$(whoami) \
  python ~/iriseye/scripts/rebuild-index.py
# Wait ~2 min for background extraction, then test again
```

### LLM hangs or is very slow first response

Context length too large. In LM Studio: unload the model and reload with `context_length=32768`.

### OpenViking won't start — port in use

```bash
lsof -i :1933    # find the stale PID
kill <PID>       # LaunchAgent will restart cleanly
```

### Dashboard shows nothing

```bash
curl http://localhost:8000/api/status   # check backend is up
# Check browser console for WebSocket errors
```

### git committer identity warning on backup

```bash
git config --global user.email "you@example.com"
git config --global user.name "your-name"
```
