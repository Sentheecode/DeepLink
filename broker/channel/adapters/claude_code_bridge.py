#!/usr/bin/env python3
"""
Claude Code Bridge - exposes Claude Code CLI as a local HTTP API.
Run this alongside the Hermes agent so the Channel can route to it.

Usage:
  python3 claude_code_bridge.py [--port 8643] [--cli-path /usr/local/bin/claude]

This listens on http://localhost:8643 and provides:
  GET  /health         -> {"status":"ok","version":"..."}
  POST /v1/capabilities -> ["chat"]
  POST /chat            -> {"events":[{"type":"text","content":"..."}]}
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
from typing import Any
from urllib.parse import urlparse

import httpx


BRIDGE_PORT = int(os.environ.get("CLAUDE_CODE_BRIDGE_PORT", "8643"))
CLI_PATH = os.environ.get("CLAUDE_CODE_PATH", "/usr/local/bin/claude")

# Simple HTTP server using asyncio + httpx
async def handle_request(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        request_line = await asyncio.wait_for(reader.readline(), timeout=10)
        if not request_line:
            writer.close()
            return
        method, path, _ = request_line.decode().strip().split(" ", 2)

        # Read headers
        headers = {}
        while True:
            line = await asyncio.wait_for(reader.readline(), timeout=10)
            if line == b"\r\n" or not line:
                break
            key, _, value = line.decode().strip().partition(":")
            headers[key.strip().lower()] = value.strip()

        # Read body if Content-Length is present
        content_length = int(headers.get("content-length", 0))
        body = b""
        if content_length > 0:
            body = await asyncio.wait_for(reader.readexactly(content_length), timeout=10)

        if method == "GET" and path == "/health":
            await send_json(writer, 200, {"status": "ok", "version": await get_version()})
        elif method == "GET" and path == "/v1/capabilities":
            await send_json(writer, 200, {"features": {"chat": True}})
        elif method == "POST" and path == "/chat":
            data = json.loads(body) if body else {}
            result = await run_claude(data.get("message", ""))
            await send_json(writer, 200, {"events": [{"type": "text", "content": result}]})
        else:
            await send_json(writer, 404, {"error": "not found"})
    except Exception as e:
        try:
            await send_json(writer, 500, {"error": str(e)})
        except Exception:
            pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def send_json(writer: asyncio.StreamWriter, status: int, data: dict[str, Any]) -> None:
    body = json.dumps(data).encode()
    status_text = {200: "OK", 404: "Not Found", 500: "Internal Server Error"}.get(status, "OK")
    response = f"HTTP/1.1 {status} {status_text}\r\nContent-Type: application/json\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode() + body
    writer.write(response)
    await writer.drain()


async def get_version() -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            CLI_PATH, "--version",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
        if proc.returncode == 0:
            return stdout.decode().strip()
    except Exception:
        pass
    return "unknown"


async def run_claude(message: str) -> str:
    if not message:
        return "Error: empty message"
    proc = await asyncio.create_subprocess_exec(
        CLI_PATH, "-p", message,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=300)
        if proc.returncode == 0:
            return stdout.decode().strip()
        else:
            error = stderr.decode().strip() or f"exit code {proc.returncode}"
            return f"Error: {error}"
    except asyncio.TimeoutError:
        proc.kill()
        return "Error: Claude Code command timed out"


async def main() -> None:
    server = await asyncio.start_server(handle_request, "127.0.0.1", BRIDGE_PORT)
    print(f"Claude Code Bridge listening on http://127.0.0.1:{BRIDGE_PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
