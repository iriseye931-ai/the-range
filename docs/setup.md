# Setup Guide

Full walkthrough to get the iriseye mesh running from scratch.

---

## What you'll need

- macOS or Linux (macOS LaunchAgents provided; Linux: adapt to systemd)
- Python 3.11+
- Node.js 18+
- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- A local LLM server with an OpenAI-compatible API
  - Recommended: [LM Studio](https://lmstudio.ai) or [Ollama](https://ollama.com)
  - Models tested: `unsloth/qwen3.5-35b-a3b`, `nomic-embed-text-v1.5` (embedding)

---

## Step 1 — Clone the repo

```bash
git clone https://github.com/iriseye931-ai/iriseye
cd iriseye
```

---

## Step 2 — Install OpenViking

OpenViking is the shared memory store. All agents read/write to it.

```bash
# Create a dedicated venv
python3 -m venv ~/.openviking/venv
source ~/.openviking/venv/bin/activate

# Install OpenViking
pip install openviking
```

Configure it:

```bash
mkdir -p ~/.openviking/data ~/.openviking/logs
cp config/ov.conf.example ~/.openviking/ov.conf
```

Edit `~/.openviking/ov.conf`:
- Set `root_api_key` to a secret string of your choice
- Set `api_base` to your LLM server URL (e.g. `http://localhost:6698/v1`)
- Set `model` to your preferred model for memory extraction
- **Critical:** set `"dimension"` to match your embedding model's output size
  - `nomic-embed-text-v1.5` → `768`
  - `text-embedding-ada-002` → `1536`
  - Wrong dimension = memory search silently returns nothing

Initialize the data directory as a git repo (for backups):

```bash
cd ~/.openviking/data
git init
git config user.email "you@example.com"
git config user.name "your-name"
```

Start OpenViking:

```bash
OPENVIKING_CONFIG_FILE=~/.openviking/ov.conf \
  ~/.openviking/venv/bin/python -c "
import uvicorn
from openviking.server import create_app
app = create_app()
uvicorn.run(app, host='0.0.0.0', port=1933)
" &

# Verify
curl http://localhost:1933/health
```

---

## Step 3 — Start the OpenViking MCP server

This lets Claude Code use memory tools (`memory_recall`, `memory_store`, `memory_forget`).

```bash
# Install dependencies
pip install mcp[server] fastmcp httpx

# Set env vars and start
OV_API_KEY=your-api-key \
OV_ACCOUNT=your-account \
OV_USER=$(whoami) \
  python mcp/openviking-mcp-server.py &

# Verify
curl http://localhost:2033/mcp
```

Register it with Claude Code:

```bash
claude mcp add --transport http --scope user openviking-memory http://127.0.0.1:2033/mcp
```

Test it:

```bash
claude -p "use memory_recall to search for 'recent activity' and show the results"
```

---

## Step 4 — Start the Mission Control backend

```bash
cd backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Copy and edit config
cp .env.example .env
# Edit .env: set OPENVIKING_KEY, LLM_URL, etc.

# Run
uvicorn main:app --host 0.0.0.0 --port 8000
```

---

## Step 5 — Open the dashboard

Open `dashboard/mission-control.html` in your browser.

The dashboard connects to the backend at `ws://localhost:8000/ws` and `http://localhost:8000`. If the backend is running you'll see live agent status, service health, and memory activity.

---

## Step 6 — Add Hermes (optional but recommended)

[Hermes](https://github.com/NousResearch/hermes-agent) is a self-improving AI agent by Nous Research. It runs long tasks, manages cron jobs, and delivers results to Telegram/Discord/Slack. It integrates with the mesh via its cron jobs file (`~/.hermes/cron/jobs.json`) which the dashboard reads automatically.

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
hermes model  # set to your local LLM endpoint
```

---

## Step 7 — Add Page Agent (optional)

Browser automation for your agents.

```bash
claude mcp add --scope user page-agent \
  -e LLM_BASE_URL=http://YOUR_LLM_HOST:PORT/v1 \
  -e LLM_MODEL_NAME=your-model-name \
  -e LLM_API_KEY=local \
  -- npx @page-agent/mcp
```

Install the [Page Agent Chrome extension](https://chromewebstore.google.com/search/page%20agent) to connect your browser.

---

## Step 8 — Auto-start on boot (macOS)

```bash
# Edit paths in both plist files first
nano launchagents/local.openviking-server.plist
nano launchagents/local.memory-backup.plist

cp launchagents/local.openviking-server.plist ~/Library/LaunchAgents/
cp launchagents/local.memory-backup.plist ~/Library/LaunchAgents/

launchctl load ~/Library/LaunchAgents/local.openviking-server.plist
launchctl load ~/Library/LaunchAgents/local.memory-backup.plist
```

For the backend, add a similar plist or use a process manager like `pm2`:

```bash
npm install -g pm2
pm2 start "uvicorn main:app --host 0.0.0.0 --port 8000" --name mission-control-backend
pm2 save && pm2 startup
```

---

## Step 9 — Verify everything

```bash
chmod +x scripts/start-mesh.sh
./scripts/start-mesh.sh
```

You should see all services reporting up.

---

## Troubleshooting

### memory_recall returns nothing

The vector index is probably broken or empty.

```bash
# 1. Wipe broken index
rm -rf ~/.openviking/data/vectordb

# 2. Restart OpenViking (LaunchAgent auto-restarts, or re-run step 2 manually)

# 3. Re-index memories from disk
OV_API_KEY=your-key OV_ACCOUNT=your-account OV_USER=$(whoami) \
  python scripts/rebuild-index.py
```

Wait ~2 minutes for background extraction, then test again.

### LLM not responding

If using LM Studio, check the context length. Extremely large contexts (262k+) can cause first-token latency of minutes. Reload the model with `context_length=32768`.

### OpenViking fails to start

Check for a stale lock:

```bash
lsof -i :1933
# kill the stale PID if present
kill <PID>
```

### Dashboard shows no data

Make sure the backend is running on port 8000:

```bash
curl http://localhost:8000/api/status
```

Check the browser console for WebSocket connection errors.
