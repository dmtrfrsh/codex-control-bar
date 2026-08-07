# Troubleshooting

## The app does not appear

- Open `~/Applications/CodexControlBar.app` manually.
- Check whether a menu-bar manager or the MacBook notch has hidden the item.
- Run `pgrep -fl CodexControlBar` in Terminal.

## Sessions do not appear

- Start a new Codex session after installation.
- Open `/hooks` in Codex and approve the Control Bar hooks if prompted.
- Confirm that `~/.codex/control-bar/state.d/` contains recent JSON files.

## Limits or MCP are stale

- Choose **Refresh limits and MCP**.
- Confirm `codex app-server` starts successfully in Terminal.
- The last successful snapshot is intentionally retained during temporary
  connection failures.

## Notifications have an old or blank icon

- Use **Diagnostics → Send test notification**.
- Relaunch the app after upgrading. Notification Center can cache bundle icons
  from older local builds.

## macOS says the app cannot be verified

The beta has no Developer ID. Prefer building it locally with
`./scripts/install_local.sh`; the resulting application is ad-hoc signed on the
same Mac. Do not download prebuilt binaries from untrusted third parties.

## “Reconnecting” appears in Codex

This message comes from the Codex client connection, not from Control Bar. The
menu app reads local hook files and periodically launches the local App Server;
it does not proxy or own the Codex conversation connection.
