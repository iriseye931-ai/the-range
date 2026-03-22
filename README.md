# Iriseye

A local AI mesh — multiple agents sharing persistent memory, a real-time mission control dashboard, and browser automation. Runs entirely on your hardware.

> **Active development.** We're building more. PRs and issues welcome.

---

## What it is

Most local AI setups are single-agent and stateless. iriseye is a mesh:

- **Multiple agents** (Claude Code, Hermes, custom) coordinating on the same tasks
- **Persistent shared memory** via [OpenViking](https://github.com/volcengine/openviking) — a local vector database that stores what your agents learn and remember across sessions
- **Real-time dashboard** showing every agent's status, tasks, and memory activity live
- **Browser automation** via [Page Agent](https://github.com/alibaba/page-agent) — agents can control your browser
- **Auto-start on boot** — all services come up on login, restart on crash
- **30-minute memory snapshots** — git-based backup so crashes don't lose anything

Everything runs locally. No cloud. Your data stays on your machine.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Your Machine                        │
│                                                         │
│  ┌──────────────┐   ┌──────────────┐                   │
│  │  Claude Code │   │    Hermes    │   agents          │
│  │  (Atlas)     │   │  (NousRes.)  │                   │
│  └──────┬───────┘   └──────┬───────┘                   │
│         │                  │                            │
│         └──────────────────┘                            │
│                    │                                    │
│           ┌────────▼────────┐                           │
│           │   OpenViking    │  shared memory            │
│           │  localhost:1933 │  (vector DB)              │
│           └────────┬────────┘                           │
│                    │                                    │
│  ┌─────────────────▼─────────────────────────────────┐  │
│  │          Mission Control Dashboard                │  │
│  │       real-time agent status + memory             │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌────────────┐   ┌─────────────┐   ┌───────────────┐  │
│  │ FastAPI    │   │  Page Agent │   │  Local LLM    │  │
│  │ backend   │   │   :38401    │   │ (LM Studio /  │  │
│  │  :8000    │   │             │   │  Ollama / etc) │  │
│  └────────────┘   └─────────────┘   └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## What's in this repo

```
iriseye/
├── backend/
│   ├── main.py                       # FastAPI server — polls mesh, broadcasts via WebSocket
│   ├── requirements.txt
│   └── .env.example
├── dashboard/
│   └── mission-control.html          # Single-file real-time dashboard (no build step)
├── mcp/
│   ├── openviking-mcp-server.py      # memory_recall / memory_store / memory_forget tools
│   ├── openclaw-mcp-server.py        # ask_openclaw tool (optional, requires OpenClaw)
│   └── requirements.txt
├── scripts/
│   ├── start-mesh.sh                 # Start + health-check all services
│   ├── backup-memories.sh            # Git-commit memory snapshots every 30 min
│   └── rebuild-index.py              # Rebuild vector index after crash or config change
├── launchagents/                     # macOS auto-start templates (edit paths, then load)
│   ├── local.openviking-server.plist
│   ├── local.openviking-mcp.plist
│   ├── local.openclaw-mcp.plist
│   ├── local.mission-control-backend.plist
│   └── local.memory-backup.plist
├── config/
│   └── ov.conf.example               # OpenViking config template
└── docs/
    └── setup.md                      # Full step-by-step setup guide
```

---

## Quick Start

See **[docs/setup.md](docs/setup.md)** for the full walkthrough.

Short version:

```bash
# 1. Install OpenViking (the memory store)
python3 -m venv ~/.openviking/venv
source ~/.openviking/venv/bin/activate
pip install openviking

cp config/ov.conf.example ~/.openviking/ov.conf
# Edit: set API key, LLM endpoint, embedding dimension

# 2. Start OpenViking
OPENVIKING_CONFIG_FILE=~/.openviking/ov.conf \
  ~/.openviking/venv/bin/python -c "
import uvicorn; from openviking.server import create_app
uvicorn.run(create_app(), host='0.0.0.0', port=1933)
" &

# 3. Start the memory MCP server (gives Claude Code memory tools)
OV_API_KEY=your-key python mcp/openviking-mcp-server.py &
claude mcp add --transport http --scope user openviking-memory http://127.0.0.1:2033/mcp

# 4. Start the dashboard backend
cd backend && pip install -r requirements.txt
cp .env.example .env && uvicorn main:app --port 8000

# 5. Open the dashboard
open dashboard/mission-control.html

# 6. Check everything
./scripts/start-mesh.sh
```

---

## Agent ecosystem

This mesh works with any Claude Code session as the primary agent. We also run:

**[Hermes](https://github.com/NousResearch/hermes-agent)** — a self-improving AI agent by Nous Research. It handles long-running tasks, cron-scheduled automations, and delivers results to Telegram/Discord/Slack. Its cron job state (`~/.hermes/cron/jobs.json`) feeds directly into the dashboard.

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

**[Page Agent](https://github.com/alibaba/page-agent)** — browser automation. Agents can navigate pages, extract data, fill forms.

```bash
claude mcp add --scope user page-agent \
  -e LLM_BASE_URL=http://YOUR_LLM_HOST:PORT/v1 \
  -e LLM_MODEL_NAME=your-model \
  -e LLM_API_KEY=local \
  -- npx @page-agent/mcp
# Then install the Chrome extension
```

---

## Services & Ports

| Service | Port | Purpose |
|---------|------|---------|
| OpenViking | 1933 | Vector memory server |
| Memory MCP | 2033 | MCP wrapper — gives Claude Code memory tools |
| FastAPI backend | 8000 | Dashboard data + WebSocket broadcasts |
| Page Agent hub | 38401 | Chrome extension bridge |

---

## If memory search breaks

```bash
# Wipe broken index
rm -rf ~/.openviking/data/vectordb

# Restart OpenViking, then rebuild
OV_API_KEY=your-key OV_ACCOUNT=your-account OV_USER=$(whoami) \
  python scripts/rebuild-index.py
```

---

## Roadmap

- [ ] Linux systemd unit files
- [ ] Docker compose for full mesh
- [ ] Web UI for memory browser / management
- [ ] Multi-machine mesh (agents on different hosts, shared memory store)
- [ ] OpenViking memory auto-tagging improvements
- [ ] Dashboard themes

---

## Contributing

Issues and PRs welcome. If you build something with this, open a discussion.

---

## License

MIT
