#!/usr/bin/env bash
# Runs the headless test suite. Pass a filter to run matching tests only: scripts/test.sh determinism
# MYAIPLANET_LIVE_AI=1 scripts/test.sh live_ai   calls real AI providers (costs money).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_PATH:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
# Importing builds the class_name cache that a fresh checkout doesn't have yet.
"$GODOT" --headless --path Godot --import >/dev/null 2>&1 || true
"$GODOT" --headless --path Godot -s res://tests/run_tests.gd -- "${1:-}"
