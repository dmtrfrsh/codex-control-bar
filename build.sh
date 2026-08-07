#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP="$PROJECT_ROOT/build/CodexControlBar.app"
CONTENTS="$APP/Contents"
ICONSET="$PROJECT_ROOT/build/AppIcon.iconset"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$ICONSET"
swiftc \
  "$PROJECT_ROOT/Sources/StatusIcon.swift" \
  "$PROJECT_ROOT/scripts/render_app_icon/main.swift" \
  -o "$PROJECT_ROOT/build/RenderAppIcon"
"$PROJECT_ROOT/build/RenderAppIcon" "$ICONSET"
tiff2icns "$ICONSET/AppIcon.tiff" "$CONTENTS/Resources/AppIcon.icns" >/dev/null
swiftc \
  -parse-as-library \
  -O \
  -framework AppKit \
  -framework UserNotifications \
  "$PROJECT_ROOT/Sources/StatusIcon.swift" \
  "$PROJECT_ROOT/Sources/StatusPresentation.swift" \
  "$PROJECT_ROOT/Sources/MenuViews.swift" \
  "$PROJECT_ROOT/Sources/main.swift" \
  -o "$CONTENTS/MacOS/CodexControlBar"
cp "$PROJECT_ROOT/assets/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJECT_ROOT/scripts/appserver_snapshot.py" "$CONTENTS/Resources/appserver_snapshot.py"
cp "$PROJECT_ROOT/scripts/context_snapshot.py" "$CONTENTS/Resources/context_snapshot.py"
cp "$PROJECT_ROOT/hooks/update.py" "$CONTENTS/Resources/update.py"
chmod 755 "$CONTENTS/MacOS/CodexControlBar"
codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
