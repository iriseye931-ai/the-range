# The Range

**A fully local, two-agent AI mesh running 24/7 on Apple Silicon — watched from its own launch-control room.**

In rocketry, *the range* is the whole installation: pads, tracking, telemetry, crew. The hardened building where launch control sits is the *blockhouse*. This repo is the range; **[Blockhouse](https://github.com/iriseye931-ai/blockhouse)** is the control room.

![Claude](https://img.shields.io/badge/Claude-Claude_Code_lead-8f5cff?style=flat-square) ![Hermes](https://img.shields.io/badge/Hermes-NousResearch-f0a821?style=flat-square) ![Local LLM](https://img.shields.io/badge/MLX-Qwen3.6_35B_%2B_Qwen3.5_9B-10b981?style=flat-square) ![Protocol](https://img.shields.io/badge/Protocol-MCP_%7C_CLI_%7C_AMP-6366f1?style=flat-square) ![Platform](https://img.shields.io/badge/Platform-Apple_Silicon-000000?style=flat-square&logo=apple&logoColor=white) ![License](https://img.shields.io/badge/License-MIT-334155?style=flat-square)

> Most local AI setups are either one smart premium model or one isolated local model.
> The Range is both: a local-first mesh where Hermes absorbs the volume, Blockhouse
> tells the truth about the system, and premium reasoning is reserved for the hard edge cases.

---

## The crew

Two agents. That's deliberate — every agent added to a mesh multiplies coordination overhead, and two well-equipped agents with clear lanes beat five vague ones.

**Claude** — the premium lead, served by [Claude Code](https://claude.ai/code). Planning, architecture, high-stakes debugging, final review. Full memory tools over MCP, a code knowledge graph, and hooks that stream every action to the dashboard.

**[Hermes](https://github.com/NousResearch/hermes-agent)** (@NousResearch) — the local runner. Cron jobs, summaries, memory consolidation, repo scans, background tasks, and a kanban board that Claude (or the dashboard) can queue real work onto. Backed by two MLX profiles:

- `workhorse` — `Qwen3.6-35B-A3B-OptiQ-4bit` (MoE) on `:8081`
- `sidecar` — `Qwen3.5-9B-OptiQ-4bit` on `:8083` for summaries, routing, compression

**Routing policy — local first, premium by exception:**

```
routine  -> hermes            (cron, summaries, scans, execution volume)
premium  -> claude             (planning, ambiguous debugging, review)
fallback -> claude ⇄ hermes    (each covers the other)
```

The constraint that matters isn't "use the smartest model first." It's **use the cheapest model that does the job correctly, and make premium usage explicit and justified.**

---

## Architecture

Three protocols, one shared memory, one source of operational truth:

```
┌─────────────────────────────────────────────────────────────┐
│                Claude (premium lead — Claude Code)           │
│                                                             │
│  MCP (inline tools)              AMP / CLI (delegation)     │
│  ├── memory_recall/store :2033   ├── amp-send → hermes      │
│  ├── codebase-memory (graph)     ├── hermes kanban create   │
│  └── context-hub (API docs)      └── hermes chat -q (sync)  │
└──────────────┬───────────────────────────────┬──────────────┘
               │                               │
               ▼                               ▼
     OpenViking :1933                Hermes (local runner)
     shared vector memory            gateway + cron + kanban
               │                     MLX :8081 / :8083
               │                               │
               └──────────────┬────────────────┘
                              ▼
                  Blockhouse :8000 / :3000
                  the control room — crew stage, GO/NO-GO
                  board, CAPCOM console, live event pipeline
```

- **MCP** — tools the model calls *while thinking*. Synchronous, inline, mid-thought results.
- **CLI** — direct subprocess call to an agent. Blocking, immediate, zero infrastructure.
- **AMP** — async file-based message passing between agents, Ed25519-signed, peer-to-peer. No central broker.

**The observability pipeline** (what makes this mesh feel alive): Claude Code's hooks API POSTs every tool call to Blockhouse; Hermes's agent log is tailed for sessions and token counts; AMP inboxes are watched for inter-agent speech. The dashboard renders the crew as block minifigs acting out real events — nothing simulated.

Full writeup: **[docs/mesh-architecture.md](docs/mesh-architecture.md)**

---

## Memory: three layers, three jobs

| Layer | Tool | Job |
|-------|------|-----|
| Shared long-term | [OpenViking](https://github.com/volcengine/openviking) `:1933` + MCP `:2033` | Decisions, preferences, failures — recalled at session start by every agent |
| Code structure | [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | Tree-sitter knowledge graph per repo — "who calls this / what breaks if I change it" in ~10ms |
| Session recovery | Hermes session search + Claude transcripts | Prior-conversation lookup |

Memory snapshots are git-committed every 30 minutes. The rule that keeps it useful: **store decisions and failures, not activity logs.**

---

## What's in this repo

```
the-range/
├── agents/            # local agent demos (pydantic-ai, swarm wiring)
├── backend/           # lightweight FastAPI status backend (legacy — Blockhouse supersedes it)
├── config/
│   ├── claude-settings.json   # Claude Code settings incl. the Blockhouse crew hooks
│   └── ov.conf.example        # OpenViking config template
├── dashboard/         # legacy single-file dashboard snapshot (history)
├── docs/              # setup guide + architecture narrative
├── hooks/
│   ├── auto-store-worker.sh   # Stop hook — session summaries → shared memory
│   ├── config-review.sh       # PostToolUse hook — local MLX reviews config changes
│   └── subconscious-worker.sh # session summarization via MLX → OpenViking
├── launchagents/      # macOS auto-start templates (MLX, OpenViking, backend, backups…)
├── mcp/               # OpenViking MCP server (memory_recall / store / forget)
└── scripts/           # start-mesh, AMP bridge, backups, GraphRAG producer, LLM proxy
```

---

## Quick start

See **[docs/setup.md](docs/setup.md)** for the full walkthrough. Short version:

```bash
# 1. OpenViking (shared memory) on :1933, MCP bridge on :2033
python3 -m venv ~/.openviking/venv && source ~/.openviking/venv/bin/activate
pip install openviking
cp config/ov.conf.example ~/.openviking/ov.conf   # set key, LLM endpoint, embedding dim
OV_API_KEY=your-key python mcp/openviking-mcp-server.py &
claude mcp add --transport http --scope user openviking-memory http://127.0.0.1:2033/mcp

# 2. Hermes (the local runner)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
# point it at your MLX endpoint (:8081)

# 3. The control room
git clone https://github.com/iriseye931-ai/blockhouse && cd blockhouse
pip install -r backend/requirements.txt
uvicorn backend.main:app --port 8000 &
cd frontend && npm install && npm run dev    # :3000

# 4. Stream your lead agent into it
# copy the crew hooks from config/claude-settings.json into ~/.claude/settings.json

# 5. Health-check the mesh
./scripts/start-mesh.sh
```

---

## Services & ports (verified live)

| Service | Port | Purpose |
|---------|------|---------|
| OpenViking | 1933 | Vector memory server |
| Memory MCP | 2033 | memory_recall / memory_store / memory_forget |
| Blockhouse backend | 8000 | Crew event pipeline, WebSocket, REST |
| Blockhouse frontend | 3000 | The control room UI |
| MLX workhorse | 8081 | Qwen3.6-35B-A3B (MoE, 4-bit) |
| Whisper STT | 8082 | Local voice transcription |
| MLX sidecar | 8083 | Qwen3.5-9B (4-bit) |
| Glance | 8080 | Service health dashboard |
| Ollama | 11434 | Embeddings only (nomic-embed-text) |
| Screenpipe | 3030 | Screen history + OCR |
| Page Agent hub | 38401 | Browser automation bridge (optional) |
| GitHub webhook | 9876 | PR activity → Hermes via AMP |

Hermes's gateway runs as a launchd service (no HTTP port in cron-only mode — health is judged from its runtime state file, which is what Blockhouse does).

---

## The data pipeline

Sessions, logs, and memories are collected nightly and indexed into a knowledge graph:

```
Claude sessions ───┐
Hermes logs ──────┼──► graphrag-producer.py (2am) ──► GraphRAG index (rate-limited via llm-proxy)
OpenViking memory ┘
```

For *code* structure the mesh uses codebase-memory-mcp instead — deterministic, sub-second, per-repo. GraphRAG covers the narrative layer; the code graph covers the structural one.

---

## Hard-won rules (what makes a mesh actually work)

1. **Two agents, clear lanes.** Every extra agent is coordination tax. We removed three before we noticed we'd never missed them.
2. **No simulated state, anywhere.** If the dashboard shows it, a hook, log, or health check produced it. A NO-GO you can trust beats a green wall you can't.
3. **The LLM proposes, deterministic code disposes.** Local models queue actions; validators execute them. Kanban with retry limits, not free-form tool calls for anything destructive.
4. **Premium by exception, and visibly so.** Routing decisions leave a paper trail on the operator surface.
5. **Docs must match `lsof`.** Every port in this README was verified listening before commit. If a service dies, the doc is wrong — fix one or the other.

---

## Roadmap

- [x] Agent-to-agent messaging with signatures (AMP)
- [x] Hermes as primary local runner with full tool-call support
- [x] Config safety net — MLX-reviewed settings changes, zero premium tokens
- [x] Live crew observability (Blockhouse: hooks pipeline, GO/NO-GO board, CAPCOM, /task)
- [x] Code knowledge graph (codebase-memory-mcp, all active repos indexed)
- [ ] Linux systemd unit files
- [ ] Docker compose for the full mesh
- [ ] Multi-machine range (agents on different hosts, shared memory store)
- [ ] Memory browser UI

---

## Contributing

Issues and PRs welcome. If you build a range of your own, open a discussion — we want to see it.

Built with [Hermes](https://github.com/NousResearch/hermes-agent) by @NousResearch — the agent that actually handles tool calling correctly on local models.

## License

MIT
