# Mesh Architecture: MCP, CLI, and AMP

This is not theory. This is the exact architecture running in this repo — three protocols,
each doing what it's best at, none replacing the others.

---

## The Cost Model First

This mesh runs on a **$20/month Claude Code (Max) subscription** plus local hardware.
That's it. No per-token API bills, no usage spikes, no surprise charges.

Here's how that works in practice:

| What | Cost | Why |
|------|------|-----|
| Claude Code (Max) | $20/mo | Lead agent — reasoning, code, architecture, complex decisions |
| MLX inference (Qwen3.5 35B) | $0 | Handles ~90% of mesh traffic locally |
| Hermes agent | $0 | Runs locally, uses local model config |
| iriseye / OpenClaw | $0 | Local agent, no external calls |
| OpenViking memory | $0 | Self-hosted vector store |

The key insight: **Claude's context is never wasted on work the local LLM can handle.**
Routine mesh messages — notifications, status updates, quick routing decisions — go
to MLX direct at ~1-2s with zero subscription cost. Only tasks that genuinely need
Claude's reasoning quality hit the $20/mo subscription.

This is why the smart routing pattern matters: it's not just about latency, it's about
preserving Claude's context and subscription capacity for the work that actually needs it.
With this setup, you don't run out of tokens. The local LLM absorbs the volume.

---

## The Three Protocols

### MCP — Model Context Protocol
Tools the model calls *while thinking*. Synchronous, inline, zero-latency to the
reasoning loop.

- Memory lookup mid-conversation → `memory_recall` at `:2033`
- Delegating a background task to iriseye → `ask_openclaw` at `:2034`
- File search, web fetch — anything the model needs *right now* to answer

The key property: the model waits for the result and uses it in the same response.
No round trip to another agent, no message queue — the answer comes back inline.

### CLI — Command Line Interface
Direct subprocess call to an agent. Blocking, immediate, no infrastructure required.

- `hermes chat -q "prompt"` → full Hermes agent with tools
- `openclaw agent -m "prompt"` → iriseye with browser, file ops, terminal
- `claude -p "prompt"` → Claude Code headless (one-shot, returns output)

Simple rule: if your script needs a response and can wait for it, use CLI.
No message format, no routing layer, no daemon — just a command.

### AMP — Agent Messaging Protocol
File-based async message passing between agents, routed by AI Maestro.

- Drop a `.json` envelope in `~/.agent-messaging/agents/{name}/messages/inbox/`
- AI Maestro routes it, the bridge picks it up, processes it, replies
- The sender doesn't wait — it fires and continues

AMP is how agents talk to each other without you in the middle. It scales across
the whole mesh without blocking anything.

---

## How They Layer in This Mesh

```
┌─────────────────────────────────────────────────────────┐
│                        Atlas (Claude Code)               │
│                                                          │
│  MCP (inline tools)          AMP / CLI (agent calls)    │
│  ├── memory_recall :2033     ├── amp-send → hermes       │
│  ├── memory_store :2033      ├── amp-send → iriseye      │
│  └── ask_openclaw :2034      └── direct CLI if blocking  │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐          ┌──────────────────────────┐
│  OpenViking     │          │     AI Maestro :23000     │
│  Memory Store   │          │  (AMP routing backbone)   │
│  :1933          │          └──────────────────────────┘
└─────────────────┘                    │
                              ┌────────┴────────┐
                              ▼                 ▼
                    ┌──────────────┐   ┌──────────────┐
                    │ hermes       │   │  iriseye     │
                    │ bridge       │   │  bridge      │
                    └──────┬───────┘   └──────┬───────┘
                           │                  │
              ┌────────────┴──┐    ┌──────────┴──────────┐
              ▼               ▼    ▼                      ▼
         MLX direct    hermes CLI  MLX direct     openclaw CLI
         (~1-2s)       (tools)     (~1-2s)        (tools)
```

---

## The Smart Routing Pattern

The bridges are the key piece. Every incoming AMP message is routed by type:

```
type=task        → full agent CLI (browser, terminal, file ops, memory)
everything else  → MLX direct    (~1-2s, no tool overhead, no token cost)
```

Implementation in `scripts/amp-hermes-bridge.sh`:

```bash
local route="mlx"
[ "$msg_type" = "task" ] && route="hermes"

if [ "$route" = "hermes" ]; then
    response=$(hermes chat -q "$prompt")
else
    response=$(mlx_direct "$prompt")   # calls MLX API directly
fi
```

Same pattern in `scripts/amp-iriseye-bridge.sh` with `openclaw agent -m` for the tool path.

Both bridges:
- Atomic claim (mv to processed first — no double-processing on restart)
- Background subshell for the inference call (non-blocking poll loop)
- Reply via `amp-send` back to the sender

---

## Why MLX Direct Instead of `claude -p`

This is the most important architectural decision in the mesh.

`claude -p` (Claude Code headless) would work — it spawns a full Claude instance as a
subprocess, returns output, exits. But:

| Path | Latency | Cost |
|------|---------|------|
| MLX direct (Qwen3.5 35B local) | ~1-2s | $0 — local inference |
| Claude Code (Atlas, lead agent) | interactive | $20/mo flat — Max subscription |
| `claude -p` headless subprocess | 5-15s + API latency | counts against Max subscription |
| hermes/openclaw CLI (tool tasks) | ~7s | $0 — local model config |

**Atlas (Claude Code) is the lead agent and is worth every dollar of the $20/mo.**
Complex reasoning, architecture decisions, code generation, nuanced judgment —
Claude handles this better than any local model available today. The subscription
pays for itself in the quality gap on tasks that actually need it.

The smart routing pattern exists specifically to *protect* that subscription:
route the high-volume, simple traffic to MLX so Claude's capacity is never
wasted on work a local model can do just as well.

`claude -p` as a subprocess would work but defeats the purpose — it spawns
a full Claude instance for every delegated task, consuming subscription capacity
on things MLX handles fine. Don't use it as a default mesh route.

---

## Why Not MCP for Agent-to-Agent?

MCP is synchronous. The model call blocks until the tool returns. This is fine for
a memory lookup (milliseconds) but wrong for delegating a 30-second task to another
agent — it would freeze the current conversation.

AMP solves this: the sender fires and forgets, the bridge handles it independently,
the reply arrives whenever it's ready. No blocked model calls, no timeout risk.

The pattern people are converging on — using CLI subprocesses instead of MCP for
agent delegation — is exactly what the bridges implement. Any agent (Claude, Gemini,
local LLM) can shell out to another agent via subprocess. No protocol lock-in,
no MCP server required for the delegation layer.

---

## Protocol Selection Guide

| Situation | Use |
|-----------|-----|
| Need a result inline while the model is thinking | MCP |
| Short blocking call, script needs the output | CLI |
| Fire-and-forget to another agent | AMP |
| Agent-to-agent delegation, don't want to block | AMP → bridge → CLI |
| Memory read/write mid-conversation | MCP |
| Browser, terminal, file ops in another agent | AMP (type=task) → CLI |
| Fast response, no tools needed | AMP → MLX direct |

---

## Services and Ports

| Service | Port | Protocol |
|---------|------|----------|
| OpenViking memory store | 1933 | HTTP REST |
| Memory MCP server | 2033 | MCP (JSON-RPC over HTTP) |
| OpenClaw MCP server | 2034 | MCP (JSON-RPC over HTTP) |
| OpenClaw gateway | 18789 | HTTP |
| AI Maestro (AMP routing) | 23000 | HTTP REST |
| MLX inference server | 8081 | OpenAI-compatible HTTP |
| Mission Control dashboard | 3005 (frontend) / 8000 (backend) | HTTP |

---

## LaunchAgents (Auto-start on login)

All bridges and services run as macOS LaunchAgents:

```
local.amp-hermes-bridge     — AMP inbox watcher for Hermes
local.amp-iriseye-bridge    — AMP inbox watcher for iriseye
local.mlx-server            — MLX inference server
local.openviking-server     — OpenViking memory store
local.openviking-mcp        — Memory MCP server
local.openclaw-mcp          — OpenClaw MCP server
local.mission-control-backend — FastAPI dashboard backend
```

Plists are in `launchagents/`. Copy to `~/Library/LaunchAgents/` and load with:

```bash
launchctl load ~/Library/LaunchAgents/local.amp-hermes-bridge.plist
```

---

## The Full Flow: A Message Arrives

1. External agent calls `amp-send hermes "subject" "body" --type notification`
2. AI Maestro delivers it to `~/.agent-messaging/agents/hermes/messages/inbox/`
3. `amp-hermes-bridge.sh` polls every 5s, picks it up
4. Atomically moves to `processed/` (prevents double-handling)
5. Parses envelope: `from`, `subject`, `thread_id`, `type`, `body`
6. Routes: `type != task` → calls MLX API directly, gets response in ~1-2s
7. Calls `amp-send {sender}` with the response + thread context
8. Logs the exchange to `~/.agent-messaging/agents/hermes/bridge.log`

Total round-trip for a notification message: **~2-3 seconds**.
For a task message routed to the full agent: **~7-10 seconds**.
