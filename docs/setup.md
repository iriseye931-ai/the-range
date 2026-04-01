# Setup Guide

This is the current local-first iriseye setup:

- `Hermes` is the workhorse
- `Atlas` is the premium lead role
- `Mission Control` is the operational truth
- `OpenViking` is shared memory
- `AI Maestro` is optional registry / AMP routing

The stack below matches the mesh we are actually running now.

---

## Prerequisites

- macOS on Apple Silicon
- Python 3.12+ recommended
- Node.js 18+
- [Claude Code](https://claude.ai/code) and/or Codex available for the premium path
- local MLX environment at `~/.mlx/venv`
- enough disk space for multiple local models
  - `Qwen3.5-35B-A3B-4bit`
  - `Qwen2.5-7B-Instruct-4bit`
  - optional but recommended:
    - `Qwen2.5-Coder-32B-Instruct-4bit`
    - `DeepSeek-R1-Distill-Qwen-32B-4bit`

---

## Target layout

After setup, the important paths should look like this:

```text
~/.mlx/
├── venv/
├── models/
│   ├── Qwen3.5-35B-A3B-4bit
│   ├── Qwen2.5-7B-Instruct-4bit
│   ├── Qwen2.5-Coder-32B-Instruct-4bit
│   └── DeepSeek-R1-Distill-Qwen-32B-4bit
└── logs/

~/.openviking/
├── venv/
├── ov.conf
├── data/
└── logs/

~/iriseye/
├── backend/
├── docs/
├── launchagents/
├── mcp/
├── scripts/
└── assets/
```

---

## Step 1 — Clone the repo

```bash
git clone https://github.com/iriseye931-ai/iriseye ~/iriseye
cd ~/iriseye
```

---

## Step 2 — Install OpenViking

```bash
python3 -m venv ~/.openviking/venv
source ~/.openviking/venv/bin/activate
pip install openviking mcp[server] fastmcp httpx

mkdir -p ~/.openviking/data ~/.openviking/logs
cp config/ov.conf.example ~/.openviking/ov.conf
```

Edit `~/.openviking/ov.conf`:

- set your API key
- set your account/user values
- point it at your local embedding endpoint
- make sure embedding dimension matches your embedding model

Initialize the memory store:

```bash
cd ~/.openviking/data
git init
git config user.email "you@example.com"
git config user.name "your-name"
```

---

## Step 3 — Install Mission Control backend

```bash
cd ~/iriseye/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
```

Edit `.env` for your local services.

The backend launcher is:

```bash
~/iriseye/backend/run_mission_control.sh
```

Use that instead of raw `uvicorn main:app` so the working directory is always correct.

---

## Step 4 — Install memory MCP tools

```bash
claude mcp add --transport http --scope user openviking-memory http://127.0.0.1:2033/mcp
```

This gives Atlas memory tools:

- `memory_recall`
- `memory_store`
- `memory_forget`

---

## Step 5 — Install Hermes

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

Point Hermes at your local MLX endpoints.

Hermes is expected to own most local task volume:

- cron
- summaries
- routing
- repo scans
- memory consolidation
- local execution

---

## Step 6 — Install the local Hermes profile stack

Always-on profiles:

- `Qwen3.5-35B-A3B-4bit` on `8081`
- `Qwen2.5-7B-Instruct-4bit` on `8083`

Recommended on-demand specialists:

- `Qwen2.5-Coder-32B-Instruct-4bit` on `8084`
- `DeepSeek-R1-Distill-Qwen-32B-4bit` on `8085`

Mission Control will detect these from `~/.mlx/models` and expose them as Hermes profiles.

---

## Step 7 — Start core services

OpenViking:

```bash
OPENVIKING_CONFIG_FILE=~/.openviking/ov.conf \
  ~/.openviking/venv/bin/python -c "
import uvicorn; from openviking.server import create_app
uvicorn.run(create_app(), host='0.0.0.0', port=1933)
" &
```

Mission Control backend:

```bash
cd ~/iriseye/backend
./run_mission_control.sh
```

Then start your local MLX servers and the dedicated Mission Control frontend repo using your preferred launcher or LaunchAgents.

---

## Step 8 — Open Mission Control

```bash
open http://127.0.0.1:3000
```

The current frontend lives in the separate `mission-control-dashboard` repo.
The `dashboard/mission-control.html` file inside `iriseye` is a legacy snapshot, not the primary live UI.

Backend API:

```text
http://127.0.0.1:8000
```

---

## Step 9 — Verify the mesh

Use the backend doctor:

```bash
cd ~/iriseye/backend
./venv/bin/python mesh_doctor.py
```

What you want to see:

- backend responding
- frontend responding
- OpenViking up
- premium pool available
- no stale registered agents
- routing healthy

Warnings that can still be expected:

- Hermes shown as `cron-only`
- one premium agent marked `rate_limited` if a provider is currently capped

---

## Routing policy

Mission Control enforces this:

```text
routine      -> hermes
specialized  -> iriseye
premium      -> atlas (fallback: claude)
```

Within Hermes:

```text
summary / routing / compression  -> sidecar
default local execution          -> workhorse
code-heavy local work            -> code-specialist
harder local analysis            -> reasoning-specialist
```

---

## Ports

| Port | Service | Required |
|------|---------|----------|
| 1933 | OpenViking | Yes |
| 2033 | Memory MCP | Yes |
| 23000 | AI Maestro | Optional |
| 3000 | Mission Control frontend | Yes |
| 8000 | Mission Control backend | Yes |
| 8081 | Hermes workhorse | Yes |
| 8083 | Hermes sidecar | Recommended |
| 8084 | Hermes code-specialist | Recommended |
| 8085 | Hermes reasoning-specialist | Recommended |
| 11434 | Ollama embeddings | Optional |
| 19999 | Netdata | Optional |
| 3030 | Screenpipe | Optional |
| 38401 | Page Agent | Optional |

---

## Troubleshooting

### Mission Control backend fails to start

Use the launcher from the backend directory:

```bash
cd ~/iriseye/backend
./run_mission_control.sh
```

Do not rely on `uvicorn main:app` from an arbitrary working directory.

### A Hermes specialist shows as missing

That means the model directory does not exist yet under `~/.mlx/models/`.

### A Hermes specialist shows installed but not running

Start it from Mission Control or call the profile action endpoint:

```bash
curl -s -X POST http://127.0.0.1:8000/api/local-profiles/action \
  -H "Content-Type: application/json" \
  -d '{"agent":"hermes","profile":"code-specialist","action":"start"}'
```

### OpenViking memory search returns nothing

Rebuild the index:

```bash
rm -rf ~/.openviking/data/vectordb
OV_API_KEY=your-key OV_ACCOUNT=your-account OV_USER=$(whoami) \
  python ~/iriseye/scripts/rebuild-index.py
```

### Premium path is capped

That is expected sometimes. Mission Control should mark the capped provider as `rate_limited` and fail over to the other premium path.
