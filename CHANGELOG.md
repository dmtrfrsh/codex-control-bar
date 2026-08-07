# Changelog

## 0.7.0-beta.3

- Retain the AppKit delegate for the complete process lifetime.
- Register accessory mode before AppKit starts its run loop.
- Use the stable `io.github.dmtrfrsh.codex-control-bar` bundle identifier.
- Fix status items being placed behind system menu extras after moving the app.

## 0.7.0-beta.2

- Create and explicitly reveal the status item after AppKit finishes launching.
- Improve GPT Knot contrast on dark and light menu bars.
- Restart the running application after local updates so the new binary is used.

## 0.7.0-beta.1

- Native macOS menu-bar dashboard for local Codex sessions.
- Context-window and multi-bucket rate-limit gauges.
- Detailed MCP status, tools, resources, and authentication state.
- Completion, permission, context, limit, and MCP notifications.
- GPT Knot, Codex Spark, and Pixel Pet animation styles.
- Original-style thinking words and animated status dots.
- Optional native Codex terminal status line.
- Local installer, uninstaller, privacy documentation, and macOS CI.

This beta is built and ad-hoc signed locally. It is not notarized and does not
require an Apple Developer ID when built from source.
