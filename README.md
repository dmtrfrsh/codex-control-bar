# Codex Control Bar

A native macOS menu-bar dashboard for local Codex sessions. It tracks active
work, context usage, account limits, MCP tools, and notifications without
shipping session content to another service.

> [!IMPORTANT]
> This is an unofficial community project. It is not affiliated with, endorsed
> by, or supported by OpenAI. Codex and OpenAI are trademarks of their
> respective owners.

Current release: **0.7.0-beta.3**.

## Features

- local Codex sessions with project, branch, model, permission mode, surface,
  tool state, and elapsed turn time;
- context-window usage based on the latest structured `token_count` record;
- every rate-limit bucket returned by the installed Codex App Server, including
  reset countdowns and explicit source information;
- MCP servers, authentication state, tool descriptions, resources, templates,
  stale-data monitoring, and health notifications;
- completion, permission, context, limit, and MCP notifications;
- selectable **GPT Knot**, **Codex Spark**, and **Pixel Pet** animations;
- original-style thinking words with animated `.`, `..`, `...` progress;
- clear context and limit progress bars;
- optional native Codex terminal status line with model, project, Git, context,
  limits, permissions, and plan progress.

## Requirements

- macOS 13 or newer;
- Codex CLI 0.147 or newer, authenticated normally;
- Xcode Command Line Tools (`xcode-select --install`);
- Python 3 available as `/usr/bin/python3` for runtime hooks.

No Apple Developer ID is required when the app is built locally. The generated
bundle is ad-hoc signed on the same Mac.

## Install from source

```bash
git clone <repository-url>
cd codex-control-bar
./scripts/install_local.sh
```

The installer runs the tests, builds the application, installs it into
`~/Applications/CodexControlBar.app`, installs lifecycle hooks, and launches the
menu-bar app.

Open `/hooks` in a new Codex session and approve the hooks if Codex asks. Then
send a prompt; the session should appear in the menu.

To also install the optional terminal status line:

```bash
./scripts/install_local.sh --with-statusline
```

Restart terminal Codex sessions after changing the TUI status line.

## Quick verification

1. Open **Diagnostics → Send test notification** and verify the blue app icon.
2. Start a fresh Codex task and send a prompt.
3. Confirm the menu-bar status word cycles its dots.
4. Open **Preferences → Animation style** and try all three styles.
5. Open the menu and verify session context, limits, and MCP rows.
6. Use **Refresh limits and MCP** and confirm the monitor stays healthy.

If anything fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Uninstall

```bash
./scripts/uninstall_local.sh
```

This removes the hooks and moves the application to Trash. Local snapshots are
kept by default. To move those to Trash as well:

```bash
./scripts/uninstall_local.sh --purge-state
```

The optional terminal status-line configuration is intentionally left alone so
uninstall cannot overwrite later user changes in `~/.codex/config.toml`.

## Development

```bash
./scripts/test.sh
./build.sh
open build/CodexControlBar.app
```

CI runs the same tests and native build on macOS. The test suite covers hook
lifecycle, atomic state, corrupt and large rollout files, context calculations,
App Server timeouts and buffered messages, snapshot recovery, status-line config
preservation, every animation style/state/frame, the application icon, bundle
signing, and Info.plist validation.

## Data and security

- [PRIVACY.md](PRIVACY.md) lists every local file and network boundary.
- [SECURITY.md](SECURITY.md) explains how to report sensitive issues.
- Never attach `~/.codex/config.toml` or unredacted rollout files to an issue.

## Beta limitations

- no Developer ID signing or notarization;
- no DMG, Homebrew formula, or automatic updater yet;
- no safe MCP enable/disable controls because Codex does not expose a stable
  public mutation interface for them;
- terminal status-line fields for MCP and active subagents are not available in
  Codex CLI 0.147.

## Acknowledgement

The product concept and parts of the menu-bar interaction model are inspired by
[InfinityScripter/claude-control-bar](https://github.com/InfinityScripter/claude-control-bar),
which is MIT licensed. This implementation uses Codex-specific hooks and App
Server APIs and does not include Claude branding or assets.

Released under the [MIT License](LICENSE). See [CHANGELOG.md](CHANGELOG.md).
