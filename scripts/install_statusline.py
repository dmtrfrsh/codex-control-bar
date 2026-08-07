#!/usr/bin/env python3
"""Install a compact, information-rich native Codex TUI status line.

The updater edits only two keys in the [tui] section and never prints the
configuration contents, which may contain MCP credentials.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
from pathlib import Path


STATUS_ITEMS = [
    "status",
    "model-with-reasoning",
    "project-root",
    "git-branch",
    "context-used",
    "five-hour-limit",
    "weekly-limit",
    "permissions",
    "task-progress",
]

SECTION_RE = re.compile(r"^\s*\[([^\]]+)]\s*(?:#.*)?$")
KEY_RE = re.compile(r"^\s*(status_line|status_line_use_colors)\s*=")


def value_lines() -> list[str]:
    quoted = ", ".join(f'"{item}"' for item in STATUS_ITEMS)
    return [f"status_line = [{quoted}]\n", "status_line_use_colors = true\n"]


def assignment_end(lines: list[str], start: int) -> int:
    """Return the exclusive end of a possibly multiline TOML array."""
    if "[" not in lines[start]:
        return start + 1
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(lines)):
        for char in lines[index].split("#", 1)[0]:
            if escaped:
                escaped = False
                continue
            if char == "\\" and in_string:
                escaped = True
            elif char == '"':
                in_string = not in_string
            elif not in_string and char == "[":
                depth += 1
            elif not in_string and char == "]":
                depth -= 1
        if depth <= 0:
            return index + 1
    return len(lines)


def update_document(text: str) -> str:
    lines = text.splitlines(keepends=True)
    section_start: int | None = None
    section_end = len(lines)
    for index, line in enumerate(lines):
        match = SECTION_RE.match(line)
        if not match:
            continue
        if section_start is not None:
            section_end = index
            break
        if match.group(1).strip() == "tui":
            section_start = index

    replacements = value_lines()
    if section_start is None:
        prefix = "" if not lines or lines[-1].endswith("\n") else "\n"
        spacer = "" if not text or text.endswith("\n\n") else "\n"
        return text + prefix + spacer + "[tui]\n" + "".join(replacements)

    cursor = section_start + 1
    kept: list[str] = []
    while cursor < section_end:
        if KEY_RE.match(lines[cursor]):
            cursor = assignment_end(lines, cursor)
        else:
            kept.append(lines[cursor])
            cursor += 1

    while kept and not kept[-1].strip():
        kept.pop()
    body = kept + replacements
    if section_end < len(lines):
        body.append("\n")
    return "".join(lines[: section_start + 1] + body + lines[section_end:])


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = path.resolve() if path.exists() else path
    temporary = target.with_name(f"{target.name}.{os.getpid()}.tmp")
    mode = target.stat().st_mode & 0o777 if target.exists() else 0o600
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(temporary, target)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=Path.home() / ".codex" / "config.toml")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    source = args.config.read_text(encoding="utf-8") if args.config.exists() else ""
    result = update_document(source)
    if result == source:
        print("Codex TUI status line is already configured")
        return 0
    if args.dry_run:
        print("Codex TUI status line would be updated")
        return 0

    if args.config.exists():
        backup = args.config.with_suffix(args.config.suffix + ".bak-codex-control-bar")
        if not backup.exists():
            shutil.copy2(args.config, backup)
    write_atomic(args.config, result)
    print("Configured native Codex TUI status line; restart Codex to apply")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
