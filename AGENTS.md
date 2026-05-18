# Project Context

`iriseye` is the local-first AI mesh repo. It defines the architecture, startup scripts, hooks, LaunchAgents, OpenViking MCP bridge, and the lightweight Mission Control backend/docs for the mesh itself.

## Architecture

- Premium-by-exception routing is the core rule.
- `Hermes` is the local workhorse for routine execution, cron, summaries, and background tasks.
- `Atlas` is the premium lead role.
- `iriseye` handles specialized file/web tasks.
- `OpenViking` is the shared memory layer.
- `Mission Control` is the operator surface, but the current primary frontend lives in the separate `mission-control-dashboard` repo.

## Repo Layout

- `agents/` contains local agent demos and wiring examples.
- `backend/` contains the lightweight FastAPI status/chat backend in this repo.
- `docs/` contains the architecture and setup narrative.
- `hooks/` contains Claude/Hermes automation and memory-related hooks.
- `launchagents/` contains macOS service definitions.
- `mcp/` contains the OpenViking MCP server.
- `scripts/` contains mesh startup, bridge, backup, and indexing scripts.
- `dashboard/mission-control.html` is a legacy snapshot, not the main live UI.

## Conventions

- Prefer local-first solutions and keep premium usage explicit and justified.
- Do not claim the mesh is healthy unless the relevant services are actually reachable.
- Keep documentation operationally honest: if a file or command does not exist, fix the docs or add the missing artifact.
- Treat OpenViking, Hermes, MLX, and Mission Control as separate moving parts; avoid blurring control-plane claims with aspirational architecture.
- Avoid storing secrets in prompt-facing files, built-in memory, or committed docs.

## Important Notes

- `docs/setup.md` and `README.md` are high-impact operator documents; keep them aligned with the real repo state.
- Startup scripts should match their names. If a script only verifies services instead of launching them all, say so explicitly.
- The mesh uses MCP, CLI, and AMP for different jobs; do not collapse them into one vague delegation model.
- When editing memory-related pieces, keep the split clear:
  - built-in Hermes memory = compact stable facts
  - OpenViking = shared long-term memory
  - session history/search = prior conversation recovery

## Editing Guidance

- Keep changes pragmatic and operator-facing.
- Prefer small, verifiable improvements over broad architectural rewrites.
- If you touch ports, endpoints, LaunchAgents, or startup commands, verify every affected reference in docs and scripts.
- If delegating work in this repo, pass concrete files, commands, and the current service state. Do not ask a child agent to infer the mesh from vague context.
