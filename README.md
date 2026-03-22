# Iriseye

A local AI mesh — multiple agents sharing persistent memory, a real-time mission control dashboard, and browser automation. Runs entirely on your hardware.

> **Active development.** We're building more. PRs and issues welcome.

---

## What it is

Most local AI setups are single-agent and stateless. iriseye is a mesh:

- **Multiple agents** (Claude Code, OpenClaw, Hermes, custom) coordinating on the same tasks
- **Persistent shared memory** via [OpenViking](https://github.com/OpenViking/openviking) — a local vector database that stores what your agents learn and remember across sessions
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
│  ┌──────────┐   ┌──────────┐   ┌──────────┐           │
│  │  Atlas   │   │ iriseye  │   │  Hermes  │  agents   │
│  │ (Claude) │   │(OpenClaw)│   │          │           │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘           │
│       │              │              │                   │
│       └──────────────┴──────────────┘                   │
│                       │                                 │
│              ┌────────▼────────┐                        │
│              │   OpenViking    │  shared memory         │
│              │  localhost:1933 │  (vector DB)           │
│              └────────┬────────┘                        │
│                       │                                 │
│  ┌────────────────────▼──────────────────────────────┐  │
│  │            Mission Control Dashboard              │  │
│  │         real-time agent status + memory           │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌────────────┐   ┌─────────────┐   ┌───────────────┐  │
│  │ AI Maestro │   │  Page Agent │   │  Local LLM    │  │
│  │  :23000    │   │   :38401    │   │ (LM Studio /  │  │
│  │            │   │             │   │  Ollama / etc) │  │
│  └────────────┘   └─────────────┘   └───────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- macOS (LaunchAgents) or Linux (adapt plists to systemd units)
- [OpenViking](https://github.com/OpenViking/openviking) installed in a Python venv
- [AI Maestro](https://github.com/ai-maestro/ai-maestro) for agent orchestration
- [Claude Code](https://claude.ai/code) as the primary agent
- A local LLM server exposing an OpenAI-compatible API (LM Studio, Ollama, vLLM, etc.)
- Node.js 18+ for Page Agent

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/iriseye/iriseye
cd iriseye
```

### 2. Configure OpenViking

Copy and edit the config:

```bash
cp config/ov.conf.example ~/.openviking/ov.conf
# Edit: set your LLM host/port, API key, account name
```

**Critical:** Set `"dimension"` in the embedding config to match your embedding model's output dimension (768 for nomic-embed-text-v1.5, 1536 for text-embedding-ada-002, etc.). A mismatch will cause memory search to silently return nothing.

### 3. Start the mesh

```bash
chmod +x scripts/start-mesh.sh
./scripts/start-mesh.sh
```

Or install as LaunchAgents so they start on boot:

```bash
# Edit paths in the plist files first
cp launchagents/local.openviking-server.plist ~/Library/LaunchAgents/
cp launchagents/local.memory-backup.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/local.openviking-server.plist
launchctl load ~/Library/LaunchAgents/local.memory-backup.plist
```

### 4. Set up memory backups

```bash
chmod +x scripts/backup-memories.sh
# Test it
./scripts/backup-memories.sh
```

### 5. Open the dashboard

Open `dashboard/mission-control.html` in your browser. It connects to the backend at `localhost:4000` (see backend config). You'll see all agents, their tasks, memory activity, and service health live.

### 6. Wire Claude Code memory (optional)

Add OpenViking as an MCP server in Claude Code:

```bash
# Install the MCP wrapper (included with OpenViking)
claude mcp add --scope user openviking-memory \
  --transport http \
  http://127.0.0.1:2033/mcp
```

Now Claude Code has `memory_recall`, `memory_store`, and `memory_forget` tools across all sessions.

### 7. Add Page Agent (optional)

Browser automation for your agents:

```bash
claude mcp add --scope user page-agent \
  -e LLM_BASE_URL=http://YOUR_LLM_HOST:PORT/v1 \
  -e LLM_MODEL_NAME=your-model-name \
  -e LLM_API_KEY=local \
  -- npx @page-agent/mcp
```

Then install the [Page Agent Chrome extension](https://chromewebstore.google.com/search/page%20agent).

---

## If memory search breaks

If `memory_recall` returns nothing after a crash or config change:

```bash
# 1. Wipe the broken vector index
rm -rf ~/.openviking/data/vectordb

# 2. Restart OpenViking
# (LaunchAgent will auto-restart, or run start-mesh.sh)

# 3. Rebuild the index from disk files
OV_API_KEY=your-key OV_ACCOUNT=your-account OV_USER=your-user \
  python scripts/rebuild-index.py
```

---

## Services & Ports

| Service | Port | Purpose |
|---------|------|---------|
| OpenViking | 1933 | Vector memory server |
| Memory MCP | 2033 | MCP wrapper for Claude Code |
| OpenClaw MCP | 2034 | iriseye agent MCP wrapper |
| OpenClaw Gateway | 18789 | Agent gateway |
| AI Maestro | 23000 | Agent orchestration |
| Page Agent hub | 38401 | Chrome extension bridge |

---

## Roadmap

- [ ] Linux systemd unit files
- [ ] Docker compose for full mesh
- [ ] Web UI for memory browser / management
- [ ] Multi-machine mesh (agents on different hosts sharing one memory store)
- [ ] OpenViking memory auto-tagging improvements
- [ ] Dashboard themes

---

## Contributing

Issues and PRs welcome. If you build something cool with this, open a discussion — would love to see what people do with it.

---

## License

MIT
