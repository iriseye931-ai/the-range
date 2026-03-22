#!/usr/bin/env python3
"""
OpenClaw Agent MCP Server
Thin wrapper that lets Claude Code delegate tasks to the OpenClaw main agent.
Exposes an `ask_openclaw` tool via MCP (HTTP transport).

Usage:
  python openclaw-mcp-server.py
  python openclaw-mcp-server.py --port 2034 --host 127.0.0.1

Connect from Claude Code:
  claude mcp add --transport http openclaw-agent http://127.0.0.1:2034/mcp
"""

import argparse
import asyncio
import json
import os
import subprocess
from mcp.server.fastmcp import FastMCP

OPENCLAW_BIN  = os.getenv("OPENCLAW_BIN",  "openclaw")
DEFAULT_AGENT = os.getenv("OPENCLAW_AGENT", "main")
TIMEOUT       = int(os.getenv("OPENCLAW_TIMEOUT", "120"))


def create_server(host: str = "127.0.0.1", port: int = 2034) -> FastMCP:
    mcp = FastMCP(
        name="openclaw-agent",
        instructions=(
            "OpenClaw agent tool. Use ask_openclaw to delegate tasks to the local "
            "OpenClaw main agent (iriseye). It runs on the local LLM, has file/web/memory "
            "tools, and shares the same OpenViking memory store. Good for: background research, "
            "file operations, web searches, parallel workstreams."
        ),
        host=host,
        port=port,
        stateless_http=True,
        json_response=True,
    )

    @mcp.tool()
    async def ask_openclaw(
        message: str,
        agent: str = "",
        session_id: str = "",
    ) -> str:
        """
        Send a message to the OpenClaw agent and return its response.
        Use this to delegate tasks, research, file work, or web searches
        to the local OpenClaw agent running on the local LLM.

        Args:
            message: The task or question to send to the agent.
            agent: Agent ID override (default: main).
            session_id: Optional session ID to continue an existing session.
        """
        cmd = [
            OPENCLAW_BIN, "agent",
            "--agent", agent or DEFAULT_AGENT,
            "--message", message,
            "--json",
            "--timeout", str(TIMEOUT),
        ]
        if session_id:
            cmd += ["--session-id", session_id]

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=TIMEOUT + 10
            )
        except asyncio.TimeoutError:
            return f"OpenClaw agent timed out after {TIMEOUT}s."
        except Exception as e:
            return f"Failed to run openclaw: {e}"

        raw = stdout.decode("utf-8", errors="replace").strip()

        # Strip any plugin log lines before the JSON
        lines = raw.splitlines()
        json_start = next(
            (i for i, l in enumerate(lines) if l.lstrip().startswith("{")), None
        )
        if json_start is not None:
            raw = "\n".join(lines[json_start:])

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            # Return raw output if JSON parse fails
            return raw or stderr.decode("utf-8", errors="replace")[:500]

        status = data.get("status", "")
        if status != "ok":
            summary = data.get("summary", "")
            return f"OpenClaw error (status={status}): {summary}\n{raw[:500]}"

        payloads = data.get("result", {}).get("payloads", [])
        texts = [p.get("text", "") for p in payloads if p.get("text")]
        if not texts:
            return "OpenClaw returned no text response."

        # Include session ID so caller can continue the conversation
        session = data.get("result", {}).get("meta", {}).get("agentMeta", {}).get("sessionId", "")
        response = "\n\n".join(texts)
        if session:
            response += f"\n\n[session_id: {session}]"
        return response

    return mcp


def main():
    parser = argparse.ArgumentParser(description="OpenClaw Agent MCP Server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.getenv("OPENCLAW_MCP_PORT", "2034")))
    args = parser.parse_args()

    mcp = create_server(host=args.host, port=args.port)
    print(f"OpenClaw Agent MCP Server starting")
    print(f"  Agent: {DEFAULT_AGENT}  bin: {OPENCLAW_BIN}")
    print(f"  MCP endpoint: http://{args.host}:{args.port}/mcp")
    print(f"  Register: claude mcp add --transport http openclaw-agent http://{args.host}:{args.port}/mcp")
    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
