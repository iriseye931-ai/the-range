# Mesh Architecture: Local-First, Premium by Exception

This is not theory. This is the exact architecture running in this repo — three protocols,
each doing what it's best at, none replacing the others.

---

## The Operating Model

The mesh is designed around one rule:

**Hermes absorbs the volume. Premium reasoning is reserved for the hard edge cases.**

That means:

| Path | Role |
|------|------|
| Hermes workhorse | routine local execution |
| Hermes sidecar | summaries, routing, compression, cheap helper work |
| Hermes code-specialist | code-heavy implementation and local review |
| Hermes reasoning-specialist | harder local reasoning and second-pass debugging |
| Atlas premium pool | planning, ambiguous debugging, tricky refactors, final review |

The premium path is a role, not a single provider:

- `atlas` = active premium lead role
- `claude` = premium backup when available

Mission Control enforces the policy:

```text
routine      -> hermes
specialized  -> iriseye
premium      -> atlas (fallback: claude)
```

This is why the routing pattern matters. It is not just about speed. It is what stops
premium capacity from being wasted on summaries, repo scans, cron digests, and other
high-volume work your local stack can already handle.

---

## The Three Protocols

### MCP — Model Context Protocol
Tools the model calls *while thinking*. Synchronous, inline, zero-latency to the
reasoning loop.

- Memory lookup mid-conversation → `memory_recall` at `:2033`
- Delegating memory or file-aware subtasks inline when the current turn needs the result
- File search, web fetch — anything the model needs *right now* to answer

The key property: the model waits for the result and uses it in the same response.
No round trip to another agent, no message queue — the answer comes back inline.

### CLI — Command Line Interface
Direct subprocess call to an agent. Blocking, immediate, no infrastructure required.

- `hermes chat -q "prompt"` → full Hermes agent with tools
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

## Control Plane vs Execution Plane

This mesh is intentionally split:

- **Mission Control** is the operational truth.
  It tracks health, heartbeats, routing, premium availability, cron freshness, and local model profiles.
- **AI Maestro** is the registry and AMP router.
  It knows about agent identity and addresses, but it is not treated as the primary liveness authority.
- **Hermes** is the execution engine.
  It owns most task volume and local specialist escalation.
- **OpenViking** is shared memory and archive.

That separation matters because it removes duplicate control planes. When something breaks, you know where truth lives.

## How They Layer in This Mesh

```
┌────────────────────────────────────────────────────────────┐
│                 Atlas (premium lead role)                 │
│            served by Codex or Claude Code                 │
│                                                            │
│  MCP (inline tools)          AMP / CLI (agent calls)      │
│  ├── memory_recall :2033     ├── amp-send → hermes        │
│  ├── memory_store  :2033     ├── amp-send → iriseye       │
│  └── docs / file tools       └── direct CLI if blocking   │
└────────────────────────────────────────────────────────────┘
         │                                 │
         ▼                                 ▼
┌─────────────────┐             ┌──────────────────────────┐
│  OpenViking     │             │     AI Maestro :23000    │
│  Memory Store   │             │ registry + AMP routing   │
│  :1933          │             └──────────────────────────┘
└─────────────────┘                         │
                   ┌────────────────────────┘
                   ▼
        ┌──────────────────────────────────────┐
        │ Mission Control :8000 / :3000        │
        │ operational truth + routing policy   │
        └──────────────────────────────────────┘
                   │
        ┌──────────┴───────────────────────┐
        ▼                                  ▼
   Hermes local stack                    iriseye
   workhorse                             specialized file/web
   sidecar
   code-specialist
   reasoning-specialist
```

---

## Hermes Profile Stack

Hermes is no longer just "the local model." It is a stack of local profiles with different costs and jobs:

| Profile | Model | Purpose |
|---------|-------|---------|
| workhorse | Qwen3.5-35B-A3B-4bit | default local execution |
| sidecar | Qwen2.5-7B-Instruct-4bit | summaries, routing, compression, helper work |
| code-specialist | Qwen2.5-Coder-32B-Instruct-4bit | code-heavy implementation, patching, local review |
| reasoning-specialist | DeepSeek-R1-Distill-Qwen-32B-4bit | harder local reasoning, debugging analysis, second-pass review |

The important design constraint is that the heavier specialists do **not** have to stay resident all the time.
They can be loaded on demand when the task justifies it.

---

## Why Not Route Everything to Premium

This is the most important policy decision in the mesh.

If premium reasoning becomes the default path, the mesh loses the whole point of being local-first.

The right question is not:

> what is the smartest model available?

It is:

> what is the cheapest model that can do this task correctly?

That is why the mesh uses layered escalation:

1. Hermes sidecar or workhorse
2. Hermes specialist profile if justified
3. Atlas premium pool only when the task genuinely needs it

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
| Browser, terminal, file ops in another agent | AMP / CLI |
| Fast local execution, no premium needed | Hermes workhorse / sidecar |
| Code-heavy local task | Hermes code-specialist |
| Harder local reasoning before premium | Hermes reasoning-specialist |

---

## Services and Ports

| Service | Port | Protocol |
|---------|------|----------|
| OpenViking memory store | 1933 | HTTP REST |
| Memory MCP server | 2033 | MCP (JSON-RPC over HTTP) |
| Hermes code-specialist | 8084 | OpenAI-compatible HTTP |
| Hermes reasoning-specialist | 8085 | OpenAI-compatible HTTP |
| AI Maestro (AMP routing) | 23000 | HTTP REST |
| Mission Control dashboard | 3000 (frontend) / 8000 (backend) | HTTP |

---

## LaunchAgents (Auto-start on login)

All bridges and services run as macOS LaunchAgents:

```
local.amp-hermes-bridge     — AMP inbox watcher for Hermes
local.mlx-server            — MLX inference server
local.openviking-server     — OpenViking memory store
local.openviking-mcp        — Memory MCP server
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
6. Routes according to mesh policy and the local profile stack
7. Calls `amp-send {sender}` with the response + thread context
8. Logs the exchange to `~/.agent-messaging/agents/hermes/bridge.log`

Total round-trip for a lightweight local message is typically **~2-3 seconds**.
Heavier local specialist work depends on model load state and task size.
