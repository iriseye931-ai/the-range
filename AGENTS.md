# Project Context

`the-range` (formerly `iriseye`) is the local-first AI mesh repo. It defines the architecture, startup scripts, hooks, LaunchAgents, and the OpenViking MCP bridge for the mesh itself. The live operator UI is the separate [blockhouse](https://github.com/iriseye931-ai/blockhouse) repo.

## Architecture

- Premium-by-exception routing is the core rule.
- The mesh is exactly **two agents**: `Atlas` (premium lead, Claude Code) and `Hermes` (local runner on MLX). Retired agents (iriseye, claude-backup, AI Maestro registry) must not reappear in docs.
- `OpenViking` is the shared long-term memory layer; `codebase-memory-mcp` is the per-repo code graph; Hermes session search covers conversation recovery. Keep the three distinct.
- `Blockhouse` is the operator surface and the source of operational truth. Its crew stage renders only real events (Claude Code hooks, Hermes log tail, AMP messages).

## Repo Layout

- `agents/` — local agent demos and wiring examples.
- `backend/` — legacy lightweight FastAPI backend (superseded by Blockhouse; kept for history).
- `docs/` — architecture and setup narrative.
- `hooks/` — Claude/Hermes automation hooks. These are vendored copies of `~/.claude/hooks/` — sync from live before committing, never edit only here.
- `launchagents/` — macOS service definitions.
- `mcp/` — the OpenViking MCP server.
- `scripts/` — mesh startup, AMP bridge, backup, and indexing scripts.

## Conventions

- Prefer local-first solutions; keep premium usage explicit and justified.
- Do not claim the mesh is healthy unless the relevant services are actually reachable. Every port listed in README.md must be verified listening (`lsof -iTCP:<port> -sTCP:LISTEN`) at commit time.
- Keep documentation operationally honest: if a file, port, or command does not exist, fix the docs or add the missing artifact.
- Avoid storing secrets in prompt-facing files, built-in memory, or committed docs. The settings template genericizes `$HOME` paths.

## Important Notes

- `docs/setup.md` and `README.md` are high-impact operator documents; keep them aligned with the real repo state.
- The mesh uses MCP (inline tools), CLI (blocking calls), and AMP (async signed messages) for different jobs; do not collapse them into one vague delegation model.
- Model lineup as of 2026-07: workhorse `Qwen3.6-35B-A3B-OptiQ-4bit` on :8081, sidecar `Qwen3.5-9B-OptiQ-4bit` on :8083. The code-specialist and reasoning-specialist profiles were planned but never deployed — do not document them as running.
- Hermes gateway runs cron-only without an HTTP health port; health is judged from `~/.hermes/gateway_state.json`.

## Editing Guidance

- Keep changes pragmatic and operator-facing; prefer small verifiable improvements over broad rewrites.
- If you touch ports, endpoints, LaunchAgents, or startup commands, verify every affected reference in docs and scripts.
- When delegating work in this repo, pass concrete files, commands, and the current service state.
