#!/usr/bin/env python3
"""Fetch a small, non-secret Codex limits/MCP snapshot through App Server."""

from __future__ import annotations

import json
import os
import select
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path.home() / ".codex" / "control-bar"
OUTPUT = ROOT / "snapshot.json"
_READ_BUFFERS: dict[int, bytes] = {}


def codex_binary() -> str:
    candidates = [
        shutil.which("codex"),
        str(Path.home() / ".local" / "bin" / "codex"),
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return candidate
    raise FileNotFoundError("codex executable not found")


def send(process: subprocess.Popen[str], message: dict[str, Any]) -> None:
    assert process.stdin is not None
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def response(process: subprocess.Popen[str], request_id: int, timeout: float = 25) -> dict[str, Any]:
    assert process.stdout is not None
    deadline = time.monotonic() + timeout
    buffer = _READ_BUFFERS.pop(process.pid, b"")
    while time.monotonic() < deadline:
        while b"\n" in buffer:
            raw_line, buffer = buffer.split(b"\n", 1)
            try:
                message = json.loads(raw_line.decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                continue
            if message.get("id") == request_id:
                _READ_BUFFERS[process.pid] = buffer
                if "error" in message:
                    raise RuntimeError(str(message["error"].get("message") or "app-server error"))
                result = message.get("result")
                return result if isinstance(result, dict) else {}
        remaining = max(0, deadline - time.monotonic())
        readable, _, _ = select.select([process.stdout], [], [], remaining)
        if not readable:
            break
        chunk = os.read(process.stdout.fileno(), 65_536)
        if not chunk:
            break
        buffer += chunk
    _READ_BUFFERS[process.pid] = buffer
    raise TimeoutError(f"no response for request {request_id}")


def collect() -> dict[str, Any]:
    process = subprocess.Popen(
        [codex_binary(), "app-server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )
    try:
        send(process, {
            "method": "initialize",
            "id": 1,
            "params": {
                "clientInfo": {"name": "codex-control-bar", "title": "Codex Control Bar", "version": "0.1.0"},
                "capabilities": {"experimentalApi": False},
            },
        })
        response(process, 1)
        send(process, {"method": "initialized", "params": {}})

        send(process, {"method": "account/rateLimits/read", "id": 2})
        limits = response(process, 2)
        servers: list[dict[str, Any]] = []
        cursor: str | None = None
        request_id = 3
        for _ in range(20):
            params: dict[str, Any] = {"limit": 100, "detail": "full"}
            if cursor:
                params["cursor"] = cursor
            send(process, {"method": "mcpServerStatus/list", "id": request_id, "params": params})
            page = response(process, request_id)
            servers.extend(row for row in page.get("data", []) if isinstance(row, dict))
            cursor = page.get("nextCursor") if isinstance(page.get("nextCursor"), str) else None
            if not cursor:
                break
            request_id += 1
        return {
            "schemaVersion": 2,
            "updatedAt": int(time.time()),
            "sources": {
                "rateLimits": "Codex App Server account/rateLimits/read",
                "mcp": "Codex App Server mcpServerStatus/list (full)",
            },
            "rateLimits": limits,
            "mcp": {"data": servers, "nextCursor": None},
        }
    finally:
        _READ_BUFFERS.pop(process.pid, None)
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()


def write_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Only tighten permissions on the application's own state tree. A caller
    # may deliberately point the snapshot at /tmp for an integration test;
    # changing a shared parent directory there would be both wrong and denied.
    if path.parent == ROOT or ROOT in path.parents:
        os.chmod(path.parent, 0o700)
    temporary = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
    os.replace(temporary, path)


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def main() -> int:
    output = Path(os.environ.get("CODEX_CONTROL_BAR_SNAPSHOT", str(OUTPUT)))
    try:
        value = collect()
    except Exception as error:
        previous = read_json(output)
        if previous and "rateLimits" in previous:
            value = {**previous, "failedAt": int(time.time()), "error": str(error)[:300]}
        else:
            value = {"failedAt": int(time.time()), "error": str(error)[:300]}
    write_atomic(output, value)
    return 0 if "error" not in value else 1


if __name__ == "__main__":
    raise SystemExit(main())
