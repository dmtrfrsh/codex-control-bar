#!/usr/bin/env python3
"""Refresh per-session context usage from the latest structured rollout records."""

from __future__ import annotations

import importlib.util
import json
import os
import time
from pathlib import Path
from typing import Any


ROOT = Path.home() / ".codex" / "control-bar"
STATE_DIR = ROOT / "state.d"
OUTPUT = ROOT / "context.json"


def load_metrics_module():
    candidates = [
        Path(__file__).with_name("update.py"),
        Path(__file__).resolve().parents[1] / "hooks" / "update.py",
    ]
    source = next((path for path in candidates if path.is_file()), None)
    if source is None:
        raise FileNotFoundError("bundled update.py not found")
    spec = importlib.util.spec_from_file_location("control_bar_metrics", source)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def collect(state_dir: Path = STATE_DIR) -> dict[str, Any]:
    metrics_module = load_metrics_module()
    sessions: dict[str, Any] = {}
    for path in state_dir.glob("*.json"):
        state = read_json(path)
        session_id = str(state.get("sessionId") or path.stem)
        transcript = state.get("transcript")
        metrics = metrics_module.transcript_metrics(transcript)
        if metrics:
            sessions[session_id] = metrics
    return {
        "updatedAt": int(time.time()),
        "source": "local rollout token_count records",
        "sessions": sessions,
    }


def write_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.parent == ROOT or ROOT in path.parents:
        os.chmod(path.parent, 0o700)
    temporary = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
    os.replace(temporary, path)


def main() -> int:
    output = Path(os.environ.get("CODEX_CONTROL_BAR_CONTEXT", str(OUTPUT)))
    try:
        value = collect()
    except Exception as error:
        value = {"updatedAt": int(time.time()), "error": str(error)[:240], "sessions": {}}
    write_atomic(output, value)
    return 0 if "error" not in value else 1


if __name__ == "__main__":
    raise SystemExit(main())
