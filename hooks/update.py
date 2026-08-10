#!/usr/bin/env python3
"""Translate Codex hook events into one small atomic state file per session."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


STATE_ROOT = Path.home() / ".codex" / "control-bar"
STATE_DIR = STATE_ROOT / "state.d"
SAFE_ID = re.compile(r"[^A-Za-z0-9_.-]")

TOOL_LABELS = {
    "Bash": "Running command",
    "apply_patch": "Editing files",
    "Edit": "Editing files",
    "Write": "Writing files",
    "WebSearch": "Searching web",
    "WebFetch": "Browsing web",
    "Agent": "Running subagent",
    "spawn_agent": "Running subagent",
    "update_plan": "Updating plan",
}


def git_branch(cwd: str) -> str:
    """Read a branch without spawning git; supports normal repos and worktrees."""
    current = Path(cwd) if cwd else None
    if not current:
        return ""
    for directory in [current, *list(current.parents)[:7]]:
        marker = directory / ".git"
        head = marker / "HEAD"
        try:
            if marker.is_file():
                line = marker.read_text(encoding="utf-8").strip()
                if line.startswith("gitdir:"):
                    git_dir = Path(line.split(":", 1)[1].strip())
                    head = (directory / git_dir if not git_dir.is_absolute() else git_dir) / "HEAD"
            value = head.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        if value.startswith("ref: refs/heads/"):
            return value.removeprefix("ref: refs/heads/")
        return value[:8] if value else ""
    return ""


def transcript_session_meta(path_value: object) -> dict[str, Any]:
    """Read the small session_meta record at the beginning of a rollout."""
    path = Path(str(path_value or ""))
    if not path.is_file():
        return {}
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            consumed = 0
            for line in handle:
                consumed += len(line)
                if consumed > 262_144:
                    break
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                payload = record.get("payload") if isinstance(record, dict) else None
                if isinstance(payload, dict) and (
                    payload.get("type") == "session_meta" or record.get("type") == "session_meta"
                ):
                    return payload
    except OSError:
        pass
    return {}


def transcript_surface(path_value: object) -> str:
    meta = transcript_session_meta(path_value)
    originator = str(meta.get("originator") or "").lower()
    source = str(meta.get("source") or "").lower()
    if "desktop" in originator:
        return "APP"
    if source == "cli" or "tui" in originator:
        return "CLI"
    if source in {"vscode", "cursor", "windsurf"}:
        return "IDE"
    return ""


def session_surface(transcript: object = None) -> str:
    bundle = os.environ.get("__CFBundleIdentifier", "").lower()
    terminal = os.environ.get("TERM_PROGRAM", "").lower()
    if bundle in {"com.openai.codex", "com.openai.chat"}:
        return "APP"
    if any(name in bundle or name in terminal for name in ("cursor", "vscode", "windsurf")):
        return "IDE"
    inferred = transcript_surface(transcript)
    if inferred:
        return inferred
    return "CLI"


def context_timestamp(value: object) -> int | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return int(dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return None


def safe_id(value: object) -> str:
    cleaned = SAFE_ID.sub("", str(value or ""))[:96]
    return cleaned or "unknown"


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    temporary = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
    except Exception:
        try:
            temporary.unlink()
        except OSError:
            pass
        raise
    os.replace(temporary, path)


def read_hook_input() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def transcript_metrics(path_value: object) -> dict[str, Any]:
    """Read only recent structured usage records from a Codex rollout.

    Transcript JSONL is explicitly not a stable hook API, so every field is
    optional and failure returns an empty fallback rather than breaking hooks.
    """
    path = Path(str(path_value or ""))
    if not path.is_file():
        return {}
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            handle.seek(max(0, size - 1_500_000))
            data = handle.read().decode("utf-8", errors="ignore")
    except OSError:
        return {}
    if size > 1_500_000 and "\n" in data:
        data = data.split("\n", 1)[1]

    result: dict[str, Any] = {}
    for line in reversed(data.splitlines()):
        try:
            record = json.loads(line)
        except ValueError:
            continue
        payload = record.get("payload") if isinstance(record, dict) else None
        if not isinstance(payload, dict):
            continue
        if not result.get("window") and isinstance(payload.get("model_context_window"), int):
            result["window"] = payload["model_context_window"]
        if payload.get("type") != "token_count":
            continue
        info = payload.get("info")
        if isinstance(info, dict):
            window = info.get("model_context_window")
            usage = info.get("last_token_usage")
            if isinstance(window, int) and window > 0:
                result["window"] = window
            if isinstance(usage, dict):
                tokens = usage.get("total_tokens")
                if isinstance(tokens, int) and tokens >= 0:
                    result["tokens"] = tokens
                    result["contextSource"] = "rollout token_count · last usage"
                    measured = context_timestamp(record.get("timestamp"))
                    if measured:
                        result["contextUpdatedAt"] = measured
        limits = payload.get("rate_limits")
        if isinstance(limits, dict):
            result["rateLimits"] = limits
        if result.get("window") and "tokens" in result:
            break

    window = result.get("window")
    tokens = result.get("tokens")
    if isinstance(window, int) and window > 0 and isinstance(tokens, int):
        result["contextPercent"] = max(0, min(100, round(tokens / window * 100)))
    return result


def event_state(event: str, payload: dict[str, Any], previous: dict[str, Any], now: int) -> dict[str, Any] | None:
    started_at = int(previous.get("startedAt") or 0)
    tool = str(payload.get("tool_name") or "")
    if event == "SessionStart":
        return {"state": "idle", "label": "Ready", "started": False, "startedAt": 0}
    if event == "UserPromptSubmit":
        return {"state": "thinking", "label": "Thinking…", "started": True, "startedAt": now}
    if event == "PreToolUse":
        label = TOOL_LABELS.get(tool, f"Using {tool}" if tool else "Using tool")
        return {"state": "tool", "label": label, "started": True, "startedAt": started_at or now}
    if event == "PostToolUse":
        return {"state": "thinking", "label": "Thinking…", "started": True, "startedAt": started_at or now}
    if event == "PermissionRequest":
        return {"state": "permission", "label": "Awaiting permission", "started": True, "startedAt": started_at}
    if event == "Stop":
        return {"state": "done", "label": "Done", "started": True, "startedAt": 0}
    return None


def process_event(event: str, payload: dict[str, Any], state_dir: Path = STATE_DIR) -> Path | None:
    session_id = safe_id(payload.get("session_id"))
    path = state_dir / f"{session_id}.json"
    if event == "SessionEnd":
        try:
            path.unlink()
        except FileNotFoundError:
            pass
        return None

    previous = read_json(path)
    now = int(time.time())
    transition = event_state(event, payload, previous, now)
    if transition is None:
        return path if path.exists() else None

    cwd = str(payload.get("cwd") or previous.get("cwd") or "")
    transcript = str(payload.get("transcript_path") or previous.get("transcript") or "")
    metrics = transcript_metrics(transcript)
    output = {
        **previous,
        **transition,
        **metrics,
        "sessionId": str(payload.get("session_id") or previous.get("sessionId") or ""),
        "turnId": str(payload.get("turn_id") or previous.get("turnId") or ""),
        "project": Path(cwd).name if cwd else str(previous.get("project") or ""),
        "branch": git_branch(cwd) or str(previous.get("branch") or ""),
        "surface": session_surface(transcript) or str(previous.get("surface") or ""),
        "hostBundle": os.environ.get("__CFBundleIdentifier", "") or str(previous.get("hostBundle") or ""),
        "cwd": cwd,
        "transcript": transcript,
        "model": str(payload.get("model") or previous.get("model") or ""),
        "permissionMode": str(payload.get("permission_mode") or previous.get("permissionMode") or ""),
        "tool": str(payload.get("tool_name") or ""),
        "pid": os.getppid(),
        "updatedAt": now,
    }
    write_atomic(path, output)
    if event == "SessionStart" and state_dir == STATE_DIR:
        configured = os.environ.get("CODEX_CONTROL_BAR_APP")
        inferred = Path(__file__).resolve().parents[1] / "build" / "CodexControlBar.app"
        application = Path(configured).expanduser() if configured else inferred
        if application.is_dir() and sys.platform == "darwin":
            try:
                subprocess.Popen(
                    ["/usr/bin/open", "-g", str(application)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except OSError:
                pass
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("event")
    parser.add_argument("--state-dir", type=Path, default=STATE_DIR)
    args = parser.parse_args()
    process_event(args.event, read_hook_input(), args.state_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
