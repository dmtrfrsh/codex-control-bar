#!/usr/bin/env python3
"""Merge or remove Codex Control Bar hooks in ~/.codex/hooks.json."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
from pathlib import Path
from typing import Any


EVENTS = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"]
MARKERS = ("codex-control-bar/hooks/update.py", "CodexControlBar.app/Contents/Resources/update.py")
MARKER_ENV = "CODEX_CONTROL_BAR_HOOK=1"


def read(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def is_ours(handler: dict[str, Any]) -> bool:
    command_value = str(handler.get("command") or "")
    return MARKER_ENV in command_value or any(marker in command_value for marker in MARKERS)


def strip_ours(groups: object) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for group in groups if isinstance(groups, list) else []:
        if not isinstance(group, dict):
            continue
        handlers = [h for h in group.get("hooks", []) if isinstance(h, dict) and not is_ours(h)]
        if handlers:
            result.append({**group, "hooks": handlers})
    return result


def command(project_root: Path, event: str, hook_script: Path | None = None, app_path: Path | None = None) -> str:
    script = (hook_script or (project_root / "hooks" / "update.py")).resolve()
    prefix = f"{MARKER_ENV} "
    if app_path:
        prefix += f"CODEX_CONTROL_BAR_APP={shlex.quote(str(app_path.resolve()))} "
    return f"{prefix}/usr/bin/python3 {shlex.quote(str(script))} {event}"


def merged(
    document: dict[str, Any], project_root: Path, uninstall: bool,
    hook_script: Path | None = None, app_path: Path | None = None,
) -> dict[str, Any]:
    output = dict(document)
    hooks = dict(output.get("hooks") or {})
    for event in EVENTS:
        groups = strip_ours(hooks.get(event))
        if not uninstall:
            group: dict[str, Any] = {"hooks": [{
                "type": "command",
                "command": command(project_root, event, hook_script=hook_script, app_path=app_path),
                "timeout": 10,
            }]}
            if event in {"PreToolUse", "PostToolUse", "PermissionRequest"}:
                group["matcher"] = ".*"
            groups.append(group)
        if groups:
            hooks[event] = groups
        else:
            hooks.pop(event, None)
    if hooks:
        output["hooks"] = hooks
    else:
        output.pop("hooks", None)
    return output


def write_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = path.resolve() if path.exists() else path
    temporary = target.with_name(f"{target.name}.{os.getpid()}.tmp")
    mode = target.stat().st_mode & 0o777 if target.exists() else 0o600
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.replace(temporary, target)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--hook-script", type=Path)
    parser.add_argument("--app-path", type=Path)
    parser.add_argument("--hooks-file", type=Path, default=Path.home() / ".codex" / "hooks.json")
    parser.add_argument("--uninstall", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    source = read(args.hooks_file)
    if not args.uninstall and args.hook_script and not args.hook_script.is_file():
        parser.error(f"hook script does not exist: {args.hook_script}")
    if not args.uninstall and args.app_path and not args.app_path.is_dir():
        parser.error(f"application does not exist: {args.app_path}")
    result = merged(
        source, args.project_root.resolve(), args.uninstall,
        hook_script=args.hook_script, app_path=args.app_path,
    )
    if args.dry_run:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    if args.hooks_file.exists() and not args.uninstall:
        backup = args.hooks_file.with_suffix(args.hooks_file.suffix + ".bak-codex-control-bar")
        if not backup.exists():
            shutil.copy2(args.hooks_file, backup)
    write_atomic(args.hooks_file, result)
    verb = "Removed" if args.uninstall else "Installed"
    print(f"{verb} Codex Control Bar hooks in {args.hooks_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
