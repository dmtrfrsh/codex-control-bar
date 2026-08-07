# Privacy

Codex Control Bar is a local menu-bar utility. It has no telemetry, analytics,
advertising SDKs, or application-owned network service.

## Data read

- lifecycle state written by the bundled Codex hooks under
  `~/.codex/control-bar/state.d/`;
- recent structured `token_count` records from the local rollout path supplied
  by Codex, used only to calculate context-window usage;
- rate-limit and MCP metadata returned by the locally installed
  `codex app-server` process.

The application does not read prompt or response text for display, does not
collect MCP credential values, and does not include configuration files in its
diagnostic snapshots.

## Data written

- `~/.codex/control-bar/state.d/*.json` — per-session status;
- `~/.codex/control-bar/context.json` — context usage;
- `~/.codex/control-bar/snapshot.json` — non-secret rate-limit and MCP status;
- `~/.codex/hooks.json` — only when the hook installer is explicitly run;
- `~/.codex/config.toml` — only when the optional TUI status-line installer is
  explicitly run. A permission-preserving backup is created first.

Local notifications contain only the project name and status summary. macOS
Notification Center stores them according to the user's system settings.

## Network behaviour

Codex Control Bar makes no direct HTTP requests. The installed Codex App Server
may communicate with OpenAI and configured remote MCP services as part of its
normal operation and authentication.
