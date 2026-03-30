<p align="center">
  <img src="assets/logo.svg" alt="iriseye" width="400"/>
</p>

<p align="center">
  <strong>A fully local, multi-agent AI mesh running 24/7 on Apple Silicon.</strong><br/>
  Specialized agents. Shared persistent memory. Real-time monitoring.<br/>
  Built on a <strong>$20/month Claude Code subscription</strong> — and local LLMs that handle everything else for free.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude_Code-Max_$20%2Fmo-8b5cf6?style=flat-square&logo=anthropic&logoColor=white"/>
  <img src="https://img.shields.io/badge/Hermes-NousResearch-10b981?style=flat-square"/>
  <img src="https://img.shields.io/badge/Local_LLM-Qwen3.5_35B-10b981?style=flat-square"/>
  <img src="https://img.shields.io/badge/Protocol-MCP_%7C_CLI_%7C_AMP-6366f1?style=flat-square"/>
  <img src="https://img.shields.io/badge/Platform-Apple_Silicon-000000?style=flat-square&logo=apple&logoColor=white"/>
  <img src="https://img.shields.io/badge/License-MIT-334155?style=flat-square"/>
</p>

---

> Most people use Claude for one conversation at a time.
> We built a mesh where Claude is the lead brain, local LLMs handle the volume,
> and agents coordinate on the same memory — all day, every day, on hardware you own.
> One flat subscription. No token anxiety. No API bills.

> **Active development.** We're shipping updates regularly. PRs and issues welcome.

---

## What it is

Most local AI setups are single-agent and stateless. iriseye is a mesh:

- **Claude Code ($20/mo)** as the lead agent (Atlas) — handles reasoning, architecture, code, complex decisions. The subscription that makes everything else possible.
- **Local LLM (MLX, free)** handles high-volume mesh traffic — notifications, summaries, routing, quick responses. Runs on your hardware, zero per-token cost.
- **[Hermes](https://github.com/NousResearch/hermes-agent) (@NousResearch)** — specialized agent for long-running tasks, file ops, web research, tool-chaining. Replaces all cloud-based secondary agents. Routes via AMP: `type=task` gets full agent with tools, everything else gets direct MLX (~1-2s).
- **Persistent shared memory** via [OpenViking](https://github.com/volcengine/openviking) — every agent reads and writes to the same vector store. Claude remembers everything across sessions.
- **Smart token management** — routine mesh messages never touch Claude. Only tasks that need real reasoning hit the subscription. You don't run out.
- **Self-building knowledge graph** — sessions, logs, and memories get indexed nightly into GraphRAG
- **250+ prompt patterns** via fabric wired to your local LLM — summarize, extract, analyze, with zero API calls
- **Real-time dashboard** showing every agent's status, tasks, AMP inbox, and memory activity live — [mission-control-dashboard](https://github.com/iriseye931-ai/mission-control-dashboard)
- **Full observability** — Netdata for system metrics, Glance for service health, Screenpipe for visual history
- **Auto-start on boot** — all services come up on login, restart on crash
- **30-minute memory snapshots** — git-based backup so nothing is lost
- **Config safety net** — every settings/hook change reviewed by local MLX via `config-review.sh`. Issues routed to Hermes via AMP. No Claude API tokens burned on routine checks.

### The cost model

| Layer | Cost | What it handles |
|-------|------|-----------------|
| Claude Code (Max) | $20/mo flat | Lead agent reasoning, code, architecture, complex tasks |
| MLX local inference | $0 | Mesh routing, notifications, summaries, quick responses |
| Hermes (NousResearch) | $0 | Tool-requiring tasks — browser, terminal, file ops, web research |
| OpenViking memory | $0 | Persistent memory across all agents |

One flat subscription. Everything else runs locally. The mesh is designed so Claude's context is never wasted on work the local LLM can do.

Everything runs locally. Your data stays on your machine.

---

## Architecture

The mesh runs three protocols — each doing what it's best at.

**MCP** — tools the model calls *while thinking*. Memory lookups, file ops, agent delegation — synchronous and inline. The model gets the result mid-thought.

**CLI** — direct subprocess call to an agent. Blocking, immediate, zero infrastructure. `hermes chat -q` — your script calls an agent like any other command.

**AMP** — async message passing between agents via file-based inbox, routed by AI Maestro. Fire and forget. Agents talk to each other without you in the middle.

They layer like this:

```
┌─────────────────────────────────────────────────────────┐
│                     Atlas (Claude Code)                  │
│                                                          │
│   MCP (inline, mid-thought)    AMP / CLI (delegation)   │
│   ├── memory_recall :2033      ├── amp-send → hermes     │
│   ├── memory_store  :2033      └── direct CLI if needed  │
│   └── chub_search (docs)                                 │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
  OpenViking :1933              AI Maestro :23000
  (shared memory)               (AMP routing)
                                       │
                                       ▼
                               hermes bridge
                                       │
                          ┌────────────┴───────────┐
                          ▼                        ▼
                     MLX direct            hermes chat -q
                     (~1-2s)               (tools, sessions)
                  type=notification        type=task
```

**Smart routing inside the bridge** — every AMP message is routed by type:
- `type=task` → `hermes chat -q` (full agent: browser, terminal, file ops, web research)
- everything else → MLX direct (~1-2s, local inference, **$0 cost**)
- max 2 concurrent Hermes workers — prevents MLX queue flooding
- session resumption via `-c "amp-bridge"` — warm startup, no context reload cost

Full architecture writeup: **[docs/mesh-architecture.md](docs/mesh-architecture.md)**

```
┌──────────────────────────────────────────────────────────────────┐
│                          Your Machine                            │
│                                                                  │
│  ┌───────────────┐   ┌──────────────────────────────────────┐   │
│  │  Claude Code  │   │    Hermes (NousResearch)             │   │
│  │  (Atlas)      │   │  long-running tasks · web research   │   │
│  │  lead agent   │   │  file ops · tool chaining · cron     │   │
│  └──────┬────────┘   └──────────────────────────────────────┘   │
│         │                             │                          │
│         └─────────────────────────────┘                          │
│                          │                                       │
│                ┌─────────▼──────────┐                            │
│                │    OpenViking       │                            │
│                │  shared memory      │                            │
│                │  localhost:1933     │                            │
│                └─────────┬──────────┘                            │
│                          │                                       │
│  ┌───────────────────────▼────────────────────────────────────┐  │
│  │               Mission Control Dashboard                    │  │
│  │         real-time status · memory · AMP inbox · cron jobs  │  │
│  └────────────────────────────────────────────────────────────┘  │
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
│   ├── claude-settings.json          # Claude Code settings (hooks, autoDreamEnabled: false)
│   └── ov.conf.example               # OpenViking config template
├── dashboard/
│   └── mission-control.html          # Single-file real-time dashboard (no build step)
├── docs/
│   ├── setup.md                      # Full step-by-step setup guide
│   └── mesh-architecture.md          # MCP vs CLI vs AMP — how the protocols layer
├── hooks/
│   ├── auto-store-worker.sh          # Claude Code Stop hook — auto-stores session summaries to memory
│   ├── config-review.sh              # PostToolUse hook — reviews config changes via local MLX, alerts Hermes on issues
│   └── subconscious-worker.sh        # Session summarization via MLX → OpenViking
├── launchagents/                     # macOS auto-start templates (edit paths, then load)
│   ├── local.mlx-server.plist        # MLX LLM server (Apple Silicon)
│   ├── local.openviking-server.plist
│   ├── local.openviking-mcp.plist
│   ├── local.mission-control-backend.plist
│   ├── local.graphrag-producer.plist
│   ├── local.memory-backup.plist
│   └── local.amp-hermes-bridge.plist # AMP bridge daemon for Hermes
├── mcp/
│   ├── openviking-mcp-server.py      # memory_recall / memory_store / memory_forget tools
│   └── requirements.txt
└── scripts/
    ├── mlx-server                    # MLX LLM server startup script (4GB KV cache, concurrency 2)
    ├── amp-hermes-bridge.sh          # AMP → Hermes bridge (parallel workers, session resumption)
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

# 4. Install Hermes (NousResearch)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
# Configure to use your local MLX endpoint

# 5. Start the AMP bridge (routes messages to Hermes)
cp scripts/amp-hermes-bridge.sh ~/.local/bin/amp-hermes-bridge.sh
chmod +x ~/.local/bin/amp-hermes-bridge.sh
# Load launchagents/local.amp-hermes-bridge.plist

# 6. Start the dashboard backend
cd backend && pip install -r requirements.txt
cp .env.example .env && uvicorn main:app --port 8000

# 7. Open the dashboard
open dashboard/mission-control.html

# 8. Check everything
./scripts/start-mesh.sh
```

---

## Agent ecosystem

**[Claude Code](https://claude.ai/code)** (Atlas) — the lead agent. Writes code, makes decisions, orchestrates the other agents. Gets full memory tools via MCP.

**[Hermes](https://github.com/NousResearch/hermes-agent)** (@NousResearch) — handles long-running tasks, cron-scheduled automations, web research, file ops. Purpose-built for Hermes-format tool calling, which is what Qwen and most local models use. Delivers results back via AMP. Replaced OpenClaw entirely — Hermes handles tool-call parsing correctly where OpenClaw failed on local models.

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

Key commands:
```bash
hermes chat -q "your task"              # one-shot task
hermes chat -c "session-name" -q "..."  # resume named session (warm startup)
hermes doctor --fix                     # health check + auto-fix
hermes claw migrate                     # migrate from OpenClaw
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
| Hermes Gateway | 18789 | Hermes messaging gateway (Telegram, Discord) |
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
- [x] Hermes (NousResearch) as primary local agent — full tool-call support on local models
- [x] Config safety net — MLX-reviewed hook/settings changes, zero Claude API cost
- [ ] Dashboard alerts + notification routing

---

## Contributing

Issues and PRs welcome. If you build something with this, open a discussion — we want to see it.

Built with [Hermes](https://github.com/NousResearch/hermes-agent) by @NousResearch — the agent that actually handles tool calling correctly on local models.

---

## License

MIT
