"""
Mission Control Dashboard — FastAPI Backend
Polls all mesh services and broadcasts live data via WebSocket.

Configure via environment variables (see .env.example).
Run: uvicorn main:app --host 0.0.0.0 --port 8000
"""

import asyncio
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Config — override via environment variables
# ---------------------------------------------------------------------------

OPENVIKING_URL   = os.getenv("OPENVIKING_URL",   "http://127.0.0.1:1933")
OPENVIKING_KEY   = os.getenv("OPENVIKING_KEY",   "your-api-key")
MEMORY_MCP_URL   = os.getenv("MEMORY_MCP_URL",   "http://127.0.0.1:2033/mcp")
OPENCLAW_MCP_URL = os.getenv("OPENCLAW_MCP_URL", "http://127.0.0.1:2034/mcp")
AIMAESTRO_URL    = os.getenv("AIMAESTRO_URL",    "http://localhost:23000")
LLM_URL          = os.getenv("LLM_URL",          "http://localhost:6698/v1")

CRON_JOBS_PATH = Path(os.getenv("CRON_JOBS_PATH", str(Path.home() / ".hermes/cron/jobs.json")))

HTTP_TIMEOUT  = float(os.getenv("HTTP_TIMEOUT", "3.0"))
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "10"))

AGENT_NAME    = os.getenv("AGENT_NAME",    "Atlas")
AGENT_SYSTEM  = os.getenv("AGENT_SYSTEM",  (
    f"You are {os.getenv('AGENT_NAME', 'Atlas')} — the lead AI agent in this local mesh. "
    "Be direct, concise, and technical. Current mesh status:\n{{mesh_status}}"
))

MCP_PING    = {"jsonrpc": "2.0", "id": 0, "method": "ping"}
MCP_HEADERS = {"Content-Type": "application/json", "Accept": "application/json"}

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Mission Control Dashboard API",
    description="Real-time data from the local AI mesh",
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Shared state
# ---------------------------------------------------------------------------

_state: dict[str, Any] = {
    "services": {},
    "agents": [],
    "cron_jobs": [],
    "memories": [],
    "llm_models": [],
    "last_updated": None,
}

_ws_clients: set[WebSocket] = set()
_ws_lock = asyncio.Lock()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _seconds_until(iso_str: str | None) -> int | None:
    if not iso_str:
        return None
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return max(0, int((dt - datetime.now(timezone.utc)).total_seconds()))
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Data fetchers
# ---------------------------------------------------------------------------

async def _fetch_service_health(client: httpx.AsyncClient) -> dict[str, Any]:
    services: dict[str, Any] = {}

    # OpenViking
    try:
        r = await client.get(
            f"{OPENVIKING_URL}/health",
            headers={"Authorization": f"Bearer {OPENVIKING_KEY}"},
            timeout=HTTP_TIMEOUT,
        )
        body = r.json()
        services["openviking"] = {
            "name": "OpenViking",
            "status": "up" if body.get("healthy") else "degraded",
            "detail": body,
        }
    except Exception as exc:
        services["openviking"] = {"name": "OpenViking", "status": "down", "error": str(exc)}

    # Memory MCP
    try:
        r = await client.post(MEMORY_MCP_URL, json=MCP_PING, headers=MCP_HEADERS, timeout=HTTP_TIMEOUT)
        body = r.json()
        services["memory_mcp"] = {
            "name": "Memory MCP",
            "status": "up" if "result" in body else "degraded",
        }
    except Exception as exc:
        services["memory_mcp"] = {"name": "Memory MCP", "status": "down", "error": str(exc)}

    # OpenClaw MCP (optional)
    if OPENCLAW_MCP_URL:
        try:
            r = await client.post(OPENCLAW_MCP_URL, json=MCP_PING, headers=MCP_HEADERS, timeout=HTTP_TIMEOUT)
            body = r.json()
            services["openclaw_mcp"] = {
                "name": "OpenClaw MCP",
                "status": "up" if "result" in body else "degraded",
            }
        except Exception as exc:
            services["openclaw_mcp"] = {"name": "OpenClaw MCP", "status": "down", "error": str(exc)}

    # AI Maestro (optional)
    try:
        r = await client.get(f"{AIMAESTRO_URL}/api/hosts/identity", timeout=HTTP_TIMEOUT)
        services["aimaestro"] = {"name": "AI Maestro", "status": "up", "detail": r.json()}
    except Exception as exc:
        services["aimaestro"] = {"name": "AI Maestro", "status": "down", "error": str(exc)}

    # LLM server
    try:
        r = await client.get(f"{LLM_URL}/models", timeout=HTTP_TIMEOUT)
        model_ids = [m["id"] for m in r.json().get("data", [])]
        services["llm_server"] = {"name": "LLM Server", "status": "up", "models": model_ids}
        _state["llm_models"] = model_ids
    except Exception as exc:
        services["llm_server"] = {"name": "LLM Server", "status": "down", "error": str(exc)}
        _state["llm_models"] = []

    return services


async def _fetch_agents(client: httpx.AsyncClient) -> list[dict[str, Any]]:
    for url in (f"{AIMAESTRO_URL}/api/agents", f"{AIMAESTRO_URL}/api/hosts/agents"):
        try:
            r = await client.get(url, timeout=HTTP_TIMEOUT)
            if r.status_code == 404:
                continue
            data = r.json()
            raw = data.get("agents", data) if isinstance(data, dict) else data
            agents = []
            for a in raw:
                sessions = a.get("sessions", [])
                status = sessions[0].get("status", "unknown") if sessions else "offline"
                agents.append({
                    "id":          a.get("id"),
                    "name":        a.get("name"),
                    "status":      status,
                    "last_active": sessions[0].get("lastActive") if sessions else None,
                    "model":       a.get("model"),
                    "host":        a.get("hostName"),
                    "address":     a.get("metadata", {}).get("amp", {}).get("address"),
                    "task":        a.get("taskDescription"),
                })
            return agents
        except Exception:
            continue
    return []


def _read_cron_jobs() -> list[dict[str, Any]]:
    if not CRON_JOBS_PATH.exists():
        return []
    try:
        raw = json.loads(CRON_JOBS_PATH.read_text())
        jobs_raw = raw.get("jobs", raw) if isinstance(raw, dict) else raw
        jobs = []
        for j in jobs_raw:
            next_run = j.get("next_run_at")
            jobs.append({
                "id":               j.get("id"),
                "name":             j.get("name"),
                "schedule_display": j.get("schedule_display") or j.get("schedule", {}).get("display"),
                "last_run_at":      j.get("last_run_at"),
                "next_run_at":      next_run,
                "next_run_in_seconds": _seconds_until(next_run),
                "last_status":      j.get("last_status"),
                "enabled":          j.get("enabled", True),
                "state":            j.get("state"),
            })
        return jobs
    except Exception:
        return []


async def _fetch_memories(client: httpx.AsyncClient) -> list[dict[str, Any]]:
    payload = {
        "jsonrpc": "2.0", "id": 1,
        "method": "tools/call",
        "params": {
            "name": "memory_recall",
            "arguments": {"query": "recent session activity", "limit": 5, "score_threshold": 0.01},
        },
    }
    try:
        r = await client.post(MEMORY_MCP_URL, json=payload, headers=MCP_HEADERS, timeout=HTTP_TIMEOUT)
        result = r.json().get("result", {})
        content = result if isinstance(result, list) else result.get("content", [])
        memories = []
        for item in content:
            if isinstance(item, dict):
                memories.append({"text": item.get("text", str(item)), "score": item.get("score")})
            elif isinstance(item, str):
                memories.append({"text": item})
        return memories
    except Exception:
        return []


# ---------------------------------------------------------------------------
# Background polling
# ---------------------------------------------------------------------------

async def _poll_loop():
    async with httpx.AsyncClient() as client:
        while True:
            try:
                services, agents, memories = await asyncio.gather(
                    _fetch_service_health(client),
                    _fetch_agents(client),
                    _fetch_memories(client),
                )
                _state["services"]     = services
                _state["agents"]       = agents
                _state["cron_jobs"]    = _read_cron_jobs()
                _state["memories"]     = memories
                _state["last_updated"] = _now_iso()
                await _broadcast_status()
            except Exception as exc:
                print(f"[poll] error: {exc}")
            await asyncio.sleep(POLL_INTERVAL)


async def _broadcast_status():
    payload = json.dumps({
        "type":      "status_update",
        "timestamp": _now_iso(),
        "services":  _state["services"],
        "agents":    _state["agents"],
        "cron_jobs": _state["cron_jobs"],
        "memories":  _state["memories"],
    })
    async with _ws_lock:
        dead: set[WebSocket] = set()
        for ws in _ws_clients:
            try:
                await ws.send_text(payload)
            except Exception:
                dead.add(ws)
        _ws_clients.difference_update(dead)


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

@app.on_event("startup")
async def _startup():
    asyncio.create_task(_poll_loop())
    print(f"[startup] Mission Control backend on :8000 — polling every {POLL_INTERVAL}s")


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------

@app.get("/api/health")
async def api_health():
    return {"services": _state["services"], "last_updated": _state["last_updated"]}


@app.get("/api/agents")
async def api_agents():
    return {"agents": _state["agents"]}


@app.get("/api/cron")
async def api_cron():
    return {"jobs": [{**j, "next_run_in_seconds": _seconds_until(j.get("next_run_at"))}
                     for j in _state["cron_jobs"]]}


@app.get("/api/memories")
async def api_memories():
    return {"memories": _state["memories"]}


@app.get("/api/status")
async def api_status():
    return {
        "timestamp":    _now_iso(),
        "last_updated": _state["last_updated"],
        "services":     _state["services"],
        "agents":       _state["agents"],
        "cron_jobs":    [{**j, "next_run_in_seconds": _seconds_until(j.get("next_run_at"))}
                         for j in _state["cron_jobs"]],
        "memories":     _state["memories"],
        "llm_models":   _state["llm_models"],
    }


# ---------------------------------------------------------------------------
# Chat — pipes message through local `claude` CLI
# ---------------------------------------------------------------------------

class ChatRequest(BaseModel):
    message: str
    history: list[dict] = []


@app.post("/api/chat")
async def api_chat(req: ChatRequest):
    claude_bin = shutil.which("claude")
    if not claude_bin:
        return {"error": "claude CLI not found in PATH — install Claude Code"}

    mesh_status = json.dumps({
        "services": {k: v.get("status") for k, v in _state["services"].items()},
        "agents":   [{"name": a["name"], "status": a["status"]} for a in _state["agents"]],
    }, indent=2)

    system = AGENT_SYSTEM.replace("{mesh_status}", mesh_status)
    parts  = [system, ""]
    for m in req.history:
        parts.append(f"{'User' if m['role']=='user' else AGENT_NAME}: {m['content']}")
    parts.append(f"User: {req.message}")
    parts.append(f"{AGENT_NAME}:")

    try:
        proc = await asyncio.wait_for(
            asyncio.get_event_loop().run_in_executor(
                None,
                lambda: subprocess.run(
                    [claude_bin, "-p", "\n".join(parts)],
                    capture_output=True, text=True, timeout=60,
                ),
            ),
            timeout=65,
        )
        if proc.returncode != 0:
            return {"error": f"claude CLI error: {proc.stderr.strip()}"}
        return {"response": proc.stdout.strip() or "No response generated"}
    except asyncio.TimeoutError:
        return {"error": "Agent timed out"}
    except Exception as exc:
        return {"error": f"Chat failed: {exc}"}


# ---------------------------------------------------------------------------
# WebSocket
# ---------------------------------------------------------------------------

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    async with _ws_lock:
        _ws_clients.add(ws)

    # Send current state immediately
    try:
        await ws.send_text(json.dumps({
            "type":      "status_update",
            "timestamp": _now_iso(),
            "services":  _state["services"],
            "agents":    _state["agents"],
            "cron_jobs": _state["cron_jobs"],
            "memories":  _state["memories"],
        }))
    except Exception:
        pass

    try:
        while True:
            await ws.receive_text()
    except (WebSocketDisconnect, Exception):
        pass
    finally:
        async with _ws_lock:
            _ws_clients.discard(ws)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=False)
