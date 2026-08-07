#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DESTINATION=${CODEX_CONTROL_BAR_DESTINATION:-"$HOME/Applications/CodexControlBar.app"}
WITH_STATUSLINE=0
RUN_TESTS=1
LAUNCH_APP=1

for argument in "$@"; do
  case "$argument" in
    --with-statusline) WITH_STATUSLINE=1 ;;
    --skip-tests) RUN_TESTS=0 ;;
    --no-launch) LAUNCH_APP=0 ;;
    --help)
      echo "usage: ./scripts/install_local.sh [--with-statusline] [--skip-tests] [--no-launch]"
      exit 0
      ;;
    *) echo "Unknown argument: $argument" >&2; exit 2 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Codex Control Bar requires macOS." >&2
  exit 1
fi

for dependency in swiftc python3 codex codesign tiff2icns ditto open; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Missing dependency: $dependency" >&2
    exit 1
  fi
done

case "$DESTINATION" in
  */CodexControlBar.app) ;;
  *) echo "Installation destination must end with CodexControlBar.app" >&2; exit 1 ;;
esac

cd "$PROJECT_ROOT"
if [ "$RUN_TESTS" -eq 1 ]; then
  ./scripts/test.sh
fi
./build.sh
codesign --verify --deep --strict build/CodexControlBar.app

INSTALL_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/codex-control-bar-install.XXXXXX")
trap 'rm -rf "$INSTALL_TEMP"' EXIT HUP INT TERM
STAGED_APP="$INSTALL_TEMP/CodexControlBar.app"
ditto build/CodexControlBar.app "$STAGED_APP"
mkdir -p "$(dirname -- "$DESTINATION")"
if [ -d "$DESTINATION" ]; then
  mv "$DESTINATION" "$INSTALL_TEMP/previous.app"
fi
mv "$STAGED_APP" "$DESTINATION"

./scripts/install_hooks.py \
  --project-root "$PROJECT_ROOT" \
  --hook-script "$DESTINATION/Contents/Resources/update.py" \
  --app-path "$DESTINATION"

if [ "$WITH_STATUSLINE" -eq 1 ]; then
  ./scripts/install_statusline.py
fi

if [ "$LAUNCH_APP" -eq 1 ]; then
  open "$DESTINATION"
fi
echo "Installed Codex Control Bar in $DESTINATION"
echo "Open /hooks in Codex and approve the newly installed hooks if prompted."
if [ "$WITH_STATUSLINE" -eq 1 ]; then
  echo "Restart terminal Codex sessions to apply the optional TUI status line."
fi
