#!/usr/bin/env python3
"""
OpenViking Memory MCP Server
Thin HTTP wrapper around the OpenViking server.
Exposes memory_recall, memory_store, memory_forget tools via MCP.

Usage:
  python openviking-mcp-server.py
  python openviking-mcp-server.py --port 2033 --host 127.0.0.1

Connect from Claude Code:
  claude mcp add --transport http --scope user openviking-memory http://127.0.0.1:2033/mcp

Environment variables:
  OV_BASE_URL   — OpenViking server URL  (default: http://127.0.0.1:1933)
  OV_API_KEY    — API key                (default: your-api-key)
  OV_ACCOUNT    — Account name           (default: default)
  OV_USER       — Username               (default: current unix user)
  OV_AGENT_ID   — Agent namespace        (default: claude)
  OV_MCP_PORT   — MCP server port        (default: 2033)
"""

import argparse
import asyncio
import os
import threading
import httpx
from mcp.server.fastmcp import FastMCP

BASE_URL  = os.getenv("OV_BASE_URL",  "http://127.0.0.1:1933")
API_KEY   = os.getenv("OV_API_KEY",   "your-api-key")
ACCOUNT   = os.getenv("OV_ACCOUNT",   "default")
USER      = os.getenv("OV_USER",      os.getenv("USER", "user"))
AGENT_ID  = os.getenv("OV_AGENT_ID",  "claude")
TIMEOUT   = float(os.getenv("OV_TIMEOUT", "30"))
EXTRACT_TIMEOUT = float(os.getenv("OV_EXTRACT_TIMEOUT", "900"))


def _headers(agent_id: str | None = None) -> dict:
    return {
        "Authorization":        f"Bearer {API_KEY}",
        "X-OpenViking-Account": ACCOUNT,
        "X-OpenViking-User":    USER,
        "X-OpenViking-Agent":   agent_id or AGENT_ID,
        "Content-Type":         "application/json",
    }


def create_server(host: str = "127.0.0.1", port: int = 2033) -> FastMCP:
    mcp = FastMCP(
        name="openviking-memory",
        instructions=(
            "OpenViking memory tools. Use memory_recall to search long-term memories, "
            "memory_store to persist new information, and memory_forget to delete by URI or query."
        ),
        host=host,
        port=port,
        stateless_http=True,
        json_response=True,
    )

    @mcp.tool()
    async def memory_recall(
        query: str,
        limit: int = 6,
        score_threshold: float = 0.01,
        agent_id: str = "",
    ) -> str:
        """
        Search long-term memories from OpenViking.

        Args:
            query: Search query describing what you're looking for.
            limit: Maximum number of memories to return (default: 6).
            score_threshold: Minimum relevance score 0-1 (default: 0.01).
            agent_id: Optional agent namespace override.
        """
        aid = agent_id or AGENT_ID
        request_limit = max(limit * 4, 20)
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            user_r, agent_r = None, None
            try:
                resp = await client.post(
                    f"{BASE_URL}/api/v1/search/find",
                    headers=_headers(aid),
                    json={"query": query,
                          "target_uri": f"viking://user/{USER}/memories",
                          "limit": request_limit, "score_threshold": 0},
                )
                user_r = resp.json().get("result", {})
            except Exception:
                pass
            try:
                resp = await client.post(
                    f"{BASE_URL}/api/v1/search/find",
                    headers=_headers(aid),
                    json={"query": query,
                          "target_uri": "viking://agent/memories",
                          "limit": request_limit, "score_threshold": 0},
                )
                agent_r = resp.json().get("result", {})
            except Exception:
                pass

        all_mems = []
        for r in [user_r, agent_r]:
            if r:
                all_mems.extend(r.get("memories", []))

        seen = set()
        filtered = []
        for m in all_mems:
            uri = m.get("uri", "")
            if uri in seen:
                continue
            seen.add(uri)
            if m.get("level") == 2 and m.get("score", 0) >= score_threshold:
                filtered.append(m)

        filtered.sort(key=lambda x: x.get("score", 0), reverse=True)
        filtered = filtered[:limit]

        if not filtered:
            return "No relevant memories found."

        lines = [f"- [{m.get('score',0):.3f}] {m.get('abstract') or m.get('uri','')}  (uri: {m.get('uri','')})"
                 for m in filtered]
        return f"Found {len(filtered)} memories:\n\n" + "\n".join(lines)

    @mcp.tool()
    async def memory_store(text: str, agent_id: str = "") -> str:
        """
        Store text as a long-term memory in OpenViking.
        Creates a session, adds the text, runs extraction, then cleans up.
        Extraction runs in the background (~60-120s).

        Args:
            text: Information to store as memory.
            agent_id: Optional agent namespace override.
        """
        aid = agent_id or AGENT_ID
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            resp = await client.post(
                f"{BASE_URL}/api/v1/sessions",
                headers=_headers(aid),
                json={"metadata": {}},
            )
            session_id = resp.json()["result"]["session_id"]

            await client.post(
                f"{BASE_URL}/api/v1/sessions/{session_id}/messages",
                headers=_headers(aid),
                json={"role": "user", "content": text},
            )
            await client.post(
                f"{BASE_URL}/api/v1/sessions/{session_id}/messages",
                headers=_headers(aid),
                json={"role": "assistant", "content": "Understood. I have noted this information."},
            )

        # Fire-and-forget extract + cleanup in a background thread.
        # asyncio.ensure_future is unreliable with stateless_http FastMCP —
        # tasks get cancelled when the HTTP handler returns. A daemon thread
        # with its own event loop is immune to that problem.
        def _extract_thread(sid: str, agent: str) -> None:
            async def _run() -> None:
                try:
                    async with httpx.AsyncClient(timeout=EXTRACT_TIMEOUT) as bg:
                        await bg.post(f"{BASE_URL}/api/v1/sessions/{sid}/extract",
                                      headers=_headers(agent), json={})
                except Exception:
                    pass
                try:
                    async with httpx.AsyncClient(timeout=TIMEOUT) as bg:
                        await bg.delete(f"{BASE_URL}/api/v1/sessions/{sid}",
                                        headers=_headers(agent))
                except Exception:
                    pass

            loop = asyncio.new_event_loop()
            try:
                loop.run_until_complete(_run())
            finally:
                loop.close()

        threading.Thread(target=_extract_thread, args=(session_id, aid), daemon=True).start()
        return f"Stored (session {session_id}). Extraction running in background (~60-120s)."

    @mcp.tool()
    async def memory_forget(uri: str = "", query: str = "", agent_id: str = "") -> str:
        """
        Forget a memory by URI, or search and delete the best match.

        Args:
            uri: Exact memory URI to delete (preferred if known).
            query: Search query to find the memory to delete.
            agent_id: Optional agent namespace override.
        """
        aid = agent_id or AGENT_ID
        if not uri and not query:
            return "Provide either uri or query."

        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            if uri:
                resp = await client.delete(
                    f"{BASE_URL}/api/v1/fs",
                    headers=_headers(aid),
                    params={"uri": uri},
                )
                if resp.status_code == 200:
                    return f"Forgotten: {uri}"
                return f"Failed to delete {uri}: {resp.text[:200]}"

            resp = await client.post(
                f"{BASE_URL}/api/v1/search/find",
                headers=_headers(aid),
                json={"query": query, "target_uri": f"viking://user/{USER}/memories",
                      "limit": 20, "score_threshold": 0},
            )
            mems = resp.json().get("result", {}).get("memories", [])
            candidates = [m for m in mems if m.get("level") == 2 and
                          m.get("uri", "").startswith("viking://")]
            if not candidates:
                return "No matching memories found."

            top = candidates[0]
            if len(candidates) == 1 or top.get("score", 0) >= 0.85:
                del_resp = await client.delete(
                    f"{BASE_URL}/api/v1/fs",
                    headers=_headers(aid),
                    params={"uri": top["uri"]},
                )
                if del_resp.status_code == 200:
                    return f"Forgotten: {top['uri']}"
                return f"Failed: {del_resp.text[:200]}"

            lines = [f"- {m['uri']} ({m.get('score',0):.2f})" for m in candidates[:5]]
            return "Multiple matches found — specify uri:\n" + "\n".join(lines)

    return mcp


def main():
    parser = argparse.ArgumentParser(description="OpenViking Memory MCP Server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.getenv("OV_MCP_PORT", "2033")))
    args = parser.parse_args()

    mcp = create_server(host=args.host, port=args.port)
    print(f"OpenViking Memory MCP Server starting")
    print(f"  OpenViking: {BASE_URL}  account={ACCOUNT} user={USER}")
    print(f"  MCP endpoint: http://{args.host}:{args.port}/mcp")
    print(f"  Register: claude mcp add --transport http --scope user openviking-memory "
          f"http://{args.host}:{args.port}/mcp")
    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
