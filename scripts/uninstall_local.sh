#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DESTINATION=${CODEX_CONTROL_BAR_DESTINATION:-"$HOME/Applications/CodexControlBar.app"}
PURGE_STATE=0

for argument in "$@"; do
  case "$argument" in
    --purge-state) PURGE_STATE=1 ;;
    --help)
      echo "usage: ./scripts/uninstall_local.sh [--purge-state]"
      exit 0
      ;;
    *) echo "Unknown argument: $argument" >&2; exit 2 ;;
  esac
done

./scripts/install_hooks.py --project-root "$PROJECT_ROOT" --uninstall
pkill -x CodexControlBar >/dev/null 2>&1 || true

TRASH_ROOT="$HOME/.Trash"
mkdir -p "$TRASH_ROOT"
STAMP=$(date +%Y%m%d-%H%M%S)
if [ -d "$DESTINATION" ]; then
  mv "$DESTINATION" "$TRASH_ROOT/CodexControlBar-$STAMP.app"
  echo "Moved the application to Trash."
fi
if [ "$PURGE_STATE" -eq 1 ] && [ -d "$HOME/.codex/control-bar" ]; then
  mv "$HOME/.codex/control-bar" "$TRASH_ROOT/codex-control-bar-state-$STAMP"
  echo "Moved local state to Trash."
fi
echo "Uninstalled Codex Control Bar hooks."
echo "The optional Codex TUI status-line configuration is left unchanged."
