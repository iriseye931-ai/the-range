# Agent Examples

These are working examples of agent frameworks wired to a local LLM.
All use environment variables for config — no hardcoded endpoints.

## pydantic_agent.py

Single agent using [pydantic-ai](https://github.com/pydantic/pydantic-ai).
Type-safe, async, straightforward.

```bash
pip install pydantic-ai
python3 pydantic_agent.py "your task here"
```

Environment variables:
- `LLM_BASE_URL` — default: `http://localhost:1234/v1`
- `LLM_MODEL` — default: see script
- `LLM_API_KEY` — default: `local`

## swarm_mesh.py

Three-agent mesh using [Swarm](https://github.com/openai/swarm):
- **Atlas** — lead, routes tasks
- **Researcher** — analysis and research
- **Coder** — code tasks

Agents hand off to each other. Atlas synthesizes the final answer.

```bash
pip install Swarm  # capital S
python3 swarm_mesh.py "your task here"
```

Same environment variables as above.

## Building your own

Both examples are starting points. The pattern is:

1. Point the LLM client at your local server (`LLM_BASE_URL`)
2. Use the model name your server expects (`LLM_MODEL`)
3. Pass `api_key="local"` (or any string — local servers don't validate)
4. Add `memory_recall` / `memory_store` calls via the OpenViking MCP tools to give your agent persistent memory

For memory integration, see the [MCP servers](../mcp/) and [docs/setup.md](../docs/setup.md#step-5--register-memory-tools-with-claude-code).
