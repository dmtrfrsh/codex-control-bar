#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
python3 -m unittest discover -s tests -v
python3 -m py_compile hooks/update.py scripts/appserver_snapshot.py scripts/context_snapshot.py scripts/install_hooks.py scripts/install_statusline.py
sh -n build.sh scripts/test.sh scripts/install_local.sh scripts/uninstall_local.sh
mkdir -p build
swiftc Sources/StatusIcon.swift Sources/StatusPresentation.swift tests/icon_smoke/main.swift -o build/IconSmokeTest
build/IconSmokeTest
