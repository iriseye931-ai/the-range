<p align="center">
  <img src="assets/logo.svg" alt="iriseye" width="400"/>
</p>

<p align="center">
  <strong>A fully local, multi-agent AI mesh running 24/7 on Apple Silicon.</strong><br/>
  Specialized agents. Shared persistent memory. Real-time monitoring.<br/>
  Local-first routing. Premium reasoning by exception. Real observability.<br/>
  Premium pool: Claude Code plus Codex when needed. Local stack handles the volume.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Atlas-Premium_Role-06b6d4?style=flat-square"/>
  <img src="https://img.shields.io/badge/Hermes-NousResearch-10b981?style=flat-square"/>
  <img src="https://img.shields.io/badge/Local_LLM-Qwen3.5_35B_%7C_Qwen2.5_Coder_%7C_DeepSeek_R1-10b981?style=flat-square"/>
  <img src="https://img.shields.io/badge/Protocol-MCP_%7C_CLI_%7C_AMP-6366f1?style=flat-square"/>
  <img src="https://img.shields.io/badge/Platform-Apple_Silicon-000000?style=flat-square&logo=apple&logoColor=white"/>
  <img src="https://img.shields.io/badge/License-MIT-334155?style=flat-square"/>
</p>

---

> Most local AI setups are either one smart premium model or one isolated local model.
> iriseye is both: a local-first mesh where Hermes absorbs the volume, Mission Control
> tells the truth about the system, and premium reasoning is reserved for the hard edge cases.

> **Active development.** We're shipping updates regularly. PRs and issues welcome.

---

## What it is

Most local AI setups are single-agent and stateless. iriseye is a mesh:

- **Atlas is a role, not a model** — the lead path can be served by Claude Code or Codex. Premium reasoning is reserved for planning, ambiguous debugging, tricky refactors, and final review.
- **[Hermes](https://github.com/NousResearch/hermes-agent) (@NousResearch)** is the workhorse — cron, summaries, routing, memory consolidation, repo scans, and routine execution stay local by default.
- **Hermes runs as a profile stack, not one monolith**:
  - `workhorse` — `Qwen3.5-35B-A3B-4bit`
  - `sidecar` — `Qwen2.5-7B-Instruct-4bit`
  - `code-specialist` — `Qwen2.5-Coder-32B-Instruct-4bit`
  - `reasoning-specialist` — `DeepSeek-R1-Distill-Qwen-32B-4bit`
- **Persistent shared memory** via [OpenViking](https://github.com/volcengine/openviking) — every agent reads and writes to the same vector store.
- **Mission Control is the operational source of truth** — health, routing, heartbeats, premium availability, cron freshness, and local profile state are visible live.
- **AI Maestro is the registry/orchestration layer** — useful for addresses and AMP routing, but not treated as the primary liveness authority.
- **Smart token management** — routine mesh messages never touch the premium pool. Most work stays local.
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
| Premium pool (Claude Code / Codex) | scarce | Lead-agent judgment, planning, review, high-stakes work |
| MLX local inference | $0 | Hermes workhorse, sidecar, coding specialist, reasoning specialist |
| Hermes (NousResearch) | $0 | Local execution, cron, tooling, summaries, routing, file/web tasks |
| OpenViking memory | $0 | Persistent memory across all agents |

The important constraint is not "use the smartest model first." It is "use the cheapest model that can do the job correctly, and reserve premium reasoning for the tasks that actually justify it."

In practice:

- Hermes should handle most mesh traffic.
- Codex and Claude Code should be used as scarce premium paths.
- If one premium path is capped or unavailable, the other takes over the Atlas role.

Everything runs locally. Your data stays on your machine.

---

## Architecture

The mesh runs three protocols and one control-plane policy.

**MCP** — tools the model calls *while thinking*. Memory lookups, file ops, agent delegation — synchronous and inline. The model gets the result mid-thought.

**CLI** — direct subprocess call to an agent. Blocking, immediate, zero infrastructure. `hermes chat -q` — your script calls an agent like any other command.

**AMP** — async message passing between agents via file-based inbox, routed by AI Maestro. Fire and forget. Agents talk to each other without you in the middle.

**Routing policy** — local first, premium by exception:

- `routine -> hermes`
- `specialized -> iriseye`
- `premium -> atlas`, fallback `claude`

They layer like this:

```
┌────────────────────────────────────────────────────────────┐
│                 Atlas (premium lead role)                 │
│            served by Codex or Claude Code                 │
│                                                            │
│   MCP (inline tools)          AMP / CLI (delegation)      │
│   ├── memory_recall :2033     ├── amp-send → hermes       │
│   ├── memory_store  :2033     ├── amp-send → iriseye      │
│   └── docs / file tools       └── direct CLI if blocking  │
└────────────────────────────────────────────────────────────┘
         │                                 │
         ▼                                 ▼
  OpenViking :1933                 AI Maestro :23000
  shared memory                    registry + AMP routing
         │                                 │
         └──────────────┬──────────────────┘
                        ▼
               Mission Control :8000 / :3000
               operational truth + routing
                        │
          ┌─────────────┴────────────────────────┐
          ▼                                      ▼
    Hermes local stack                         iriseye
    workhorse / sidecar /                      specialized file/web
    code-specialist / reasoning-specialist
```

**Hermes profile stack**

- `workhorse` handles default local execution
- `sidecar` handles summaries, routing, compression, and cheap helper work
- `code-specialist` is loaded on demand for implementation-heavy tasks
- `reasoning-specialist` is loaded on demand for harder local analysis before premium escalation

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
│   └── mission-control.html          # legacy single-file dashboard snapshot
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

# 3. Start the memory MCP server (gives Atlas memory tools)
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
cp .env.example .env && ./run_mission_control.sh

# 7. Run the live Mission Control frontend
# Use the dedicated mission-control-dashboard repo for the current UI on :3000
open http://127.0.0.1:3000

# 8. Check everything
./scripts/start-mesh.sh
```

The `dashboard/mission-control.html` file in this repo is retained as a lightweight legacy snapshot.
The live operational UI is the separate [mission-control-dashboard](https://github.com/iriseye931-ai/mission-control-dashboard) repo.

---

## Agent ecosystem

**Atlas** — the lead role in the mesh. In practice this can be served by **[Claude Code](https://claude.ai/code)** or **Codex** depending on availability. Atlas handles planning, architecture, high-stakes debugging, and final review. It gets full memory tools via MCP.

**[Hermes](https://github.com/NousResearch/hermes-agent)** (@NousResearch) — handles long-running tasks, cron-scheduled automations, web research, file ops, and most routine execution. Hermes is backed by a local profile stack:

- `workhorse` — `Qwen3.5-35B-A3B-4bit`
- `sidecar` — `Qwen2.5-7B-Instruct-4bit`
- `code-specialist` — `Qwen2.5-Coder-32B-Instruct-4bit`
- `reasoning-specialist` — `DeepSeek-R1-Distill-Qwen-32B-4bit`

That means Hermes is not just "the local model." It is the local execution layer.

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
Atlas sessions ───┐
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
| Memory MCP | 2033 | MCP tools for Atlas (memory_recall, memory_store, memory_forget) |
| Hermes Gateway | 18789 | Hermes messaging gateway (Telegram, Discord) |
| AI Maestro | 23000 | Multi-agent orchestration (optional) |
| Mission Control backend | 8000 | Dashboard WebSocket + REST API |
| Mission Control frontend | 3000 | Dashboard UI |
| Page Agent hub | 38401 | Chrome extension bridge (optional) |
| Screenpipe | 3030 | Screen history API |
| Netdata | 19999 | System metrics |
| MLX Server | 8081 | Local LLM — Qwen3.5-35B-A3B-4bit via mlx_lm (chat + completions) |
| Hermes sidecar | 8083 | Qwen2.5-7B-Instruct-4bit |
| Hermes code-specialist | 8084 | Qwen2.5-Coder-32B-Instruct-4bit |
| Hermes reasoning-specialist | 8085 | DeepSeek-R1-Distill-Qwen-32B-4bit |
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
