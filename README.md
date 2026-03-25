# iriseye

A local AI mesh — multiple specialized agents sharing persistent memory, a self-building knowledge graph, and real-time monitoring. Runs entirely on your hardware. No cloud. No API bills.

> **Active development.** We're shipping updates regularly. PRs and issues welcome.

---

## What it is

Most local AI setups are single-agent and stateless. iriseye is a mesh:

- **Three agents** coordinating on the same tasks — Atlas (Claude Code), Hermes, iriseye (OpenClaw)
- **Persistent shared memory** via [OpenViking](https://github.com/volcengine/openviking) — every agent reads and writes to the same vector store
- **Self-building knowledge graph** — sessions, logs, and memories get indexed nightly into GraphRAG
- **250+ prompt patterns** via fabric wired to your local LLM — summarize, extract, analyze, with zero API calls
- **Real-time dashboard** showing every agent's status, tasks, and memory activity live
- **Full observability** — Netdata for system metrics, Glance for service health, Screenpipe for visual history
- **Auto-start on boot** — all services come up on login, restart on crash
- **30-minute memory snapshots** — git-based backup so nothing is lost

Everything runs locally. Your data stays on your machine.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                          Your Machine                            │
│                                                                  │
│  ┌───────────────┐   ┌──────────────┐   ┌──────────────────┐   │
│  │  Claude Code  │   │    Hermes    │   │  iriseye         │   │
│  │  (Atlas)      │   │  (NousRes.)  │   │  (OpenClaw)      │   │
│  │  lead agent   │   │  long tasks  │   │  file/web ops    │   │
│  └──────┬────────┘   └──────┬───────┘   └────────┬─────────┘   │
│         │                   │                     │             │
│         └───────────────────┴─────────────────────┘             │
│                                    │                             │
│                          ┌─────────▼──────────┐                 │
│                          │    OpenViking       │                 │
│                          │  shared memory      │                 │
│                          │  localhost:1933     │                 │
│                          └─────────┬──────────┘                 │
│                                    │                             │
│  ┌─────────────────────────────────▼──────────────────────────┐ │
│  │               Mission Control Dashboard                    │ │
│  │         real-time status · memory · cron jobs              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────┐  ┌─────────────┐  ┌──────────┐  ┌───────────┐  │
│  │  FastAPI   │  │  Page Agent │  │ Netdata  │  │  Glance   │  │
│  │  :8000     │  │   :38401    │  │  :19999  │  │  :8080    │  │
│  └────────────┘  └─────────────┘  └──────────┘  └───────────┘  │
│                                                                  │
│  ┌───────────────────────────────┐  ┌──────────────────────┐   │
│  │  MLX Server (mlx_lm) :8081   │  │  Ollama :11434       │   │
│  │  Qwen3.5-35B-A3B — chat/LLM  │  │  nomic-embed-text    │   │
│  │  Apple Silicon MoE 4-bit     │  │  embeddings only     │   │
│  └───────────────────────────────┘  └──────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

## What's in this repo

```
iriseye/
├── agents/
│   ├── pydantic_agent.py             # pydantic-ai agent wired to local LLM
│   └── swarm_mesh.py                 # 3-agent Swarm mesh (Atlas / Researcher / Coder)
├── backend/
│   ├── main.py                       # FastAPI server — polls mesh, broadcasts via WebSocket
│   ├── requirements.txt
│   └── .env.example
├── config/
│   └── ov.conf.example               # OpenViking config template
├── dashboard/
│   └── mission-control.html          # Single-file real-time dashboard (no build step)
├── docs/
│   └── setup.md                      # Full step-by-step setup guide
├── hooks/
│   └── auto-store-worker.sh          # Claude Code Stop hook — auto-stores session summaries to memory
├── launchagents/                     # macOS auto-start templates (edit paths, then load)
│   ├── local.mlx-server.plist        # MLX LLM server (Apple Silicon)
│   ├── local.openviking-server.plist
│   ├── local.openviking-mcp.plist
│   ├── local.openclaw-mcp.plist
│   ├── local.mission-control-backend.plist
│   ├── local.graphrag-producer.plist
│   └── local.memory-backup.plist
├── mcp/
│   ├── openviking-mcp-server.py      # memory_recall / memory_store / memory_forget tools
│   ├── openclaw-mcp-server.py        # ask_openclaw tool (optional, requires OpenClaw)
│   └── requirements.txt
└── scripts/
    ├── mlx-server                    # MLX LLM server startup script (Apple Silicon)
    ├── start-mesh.sh                 # Start + health-check all services
    ├── backup-memories.sh            # Git-commit memory snapshots every 30 min
    ├── rebuild-index.py              # Rebuild vector index after crash or config change
    ├── graphrag-producer.py          # Collect sessions/logs/memories for nightly indexing
    └── llm-proxy.py                  # Rate-limiting proxy — prevents LLM queue flooding
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

**[Claude Code](https://claude.ai/code)** (Atlas) — the lead agent. Writes code, makes decisions, orchestrates the other agents. Gets full memory tools via MCP.

**[Hermes](https://github.com/NousResearch/hermes-agent)** — handles long-running tasks and cron-scheduled automations. Delivers results to Telegram/Discord/Slack. Its job state feeds directly into the dashboard.

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

**[OpenClaw](https://openclaw.dev)** (iriseye) — a local agent with file, web, and shell tools. Handles research and file ops in the background while Atlas focuses on reasoning.

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

## The tool stack

Beyond the core agents, we run these on top:

| Tool | What it does | Install |
|------|-------------|---------|
| **[fabric](https://github.com/danielmiessler/fabric)** | 250+ prompt patterns (summarize, extract wisdom, analyze, etc.) | `brew install fabric-ai` |
| **[pydantic-ai](https://github.com/pydantic/pydantic-ai)** | Type-safe agent framework | `pip install pydantic-ai` |
| **[Swarm](https://github.com/openai/swarm)** | Multi-agent orchestration with handoffs | `pip install Swarm` |
| **[mem0](https://github.com/mem0ai/mem0)** | In-code agent memory layer | `pip install mem0ai` |
| **[browser-use](https://github.com/browser-use/browser-use)** | Python browser automation for agents | `pip install browser-use` |
| **[screenpipe](https://github.com/mediar-ai/screenpipe)** | Screen recording + OCR + searchable history | `brew install screenpipe` |
| **[GraphRAG](https://github.com/microsoft/graphrag)** | Knowledge graph from your documents | `pip install graphrag` |
| **[netdata](https://github.com/netdata/netdata)** | Real-time system metrics | `brew install netdata` |
| **[glance](https://github.com/glanceapp/glance)** | Self-hosted status dashboard | `brew install glance` |
| **[context-hub](https://github.com/andrewyng/context-hub)** | Curated API docs for agents | `pip install context-hub` |

All tools are configured to use your local LLM — no external API calls.

---

## The data pipeline

The mesh gets smarter every day automatically:

```
Claude sessions ──┐
Hermes logs ──────┤──► graphrag-producer.py (2am) ──► ~/.graphrag/workspace/input/
OpenViking memory ┤                                           │
Shell history ────┘                                          ▼
                                                    graphrag index (via llm-proxy)
                                                           │
                                                           ▼
                                              Knowledge graph you can query
```

Every session you have, every command you run, every memory stored — captured nightly and indexed into a graph that reasons across all of it.

Run the producer manually any time:

```bash
python3 scripts/graphrag-producer.py
```

Run GraphRAG indexing overnight (use the proxy to avoid flooding your LLM):

```bash
# Terminal 1 — rate-limiting proxy (4 req/min)
python3 scripts/llm-proxy.py --port 6699 --rpm 4

# Terminal 2 — indexer
cd ~/.graphrag/workspace
GRAPHRAG_API_KEY=local GRAPHRAG_API_BASE=http://localhost:6699/v1 \
  ~/.graphrag/venv/bin/graphrag index --root .
```

---

## Services & Ports

| Service | Port | Purpose |
|---------|------|---------|
| OpenViking | 1933 | Vector memory server |
| Memory MCP | 2033 | MCP tools for Claude Code (memory_recall, memory_store, memory_forget) |
| OpenClaw MCP | 2034 | ask_openclaw tool (optional) |
| OpenClaw Gateway | 18789 | OpenClaw agent gateway (optional) |
| AI Maestro | 23000 | Multi-agent orchestration (optional) |
| Mission Control backend | 8000 | Dashboard WebSocket + REST API |
| Page Agent hub | 38401 | Chrome extension bridge (optional) |
| Screenpipe | 3030 | Screen history API |
| Netdata | 19999 | System metrics |
| MLX Server | 8081 | Local LLM — Qwen3.5-35B-A3B-4bit via mlx_lm (chat + completions) |
| Glance | 8080 | Service health dashboard |
| Ollama | 11434 | Embeddings only — nomic-embed-text |

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
- [ ] GraphRAG query interface in the dashboard
- [x] Agent-to-agent messaging with signatures (AMP protocol)
- [ ] Dashboard alerts + notification routing

---

## Contributing

Issues and PRs welcome. If you build something with this, open a discussion — we want to see it.

---

## License

MIT
