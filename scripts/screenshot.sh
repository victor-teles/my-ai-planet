#!/usr/bin/env bash
# Renders a frame of the game to a PNG using Godot's Movie Maker (opens a window briefly).
# Usage: scripts/screenshot.sh out.png [frames] -- --seed=42 --warmup-years=140 --distance=20
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_PATH:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
out="$1"; frames="${2:-40}"; shift 2 || shift $#
[ "${1:-}" = "--" ] && shift
tmp="$(mktemp -d)"
MYAIPLANET_AI="${MYAIPLANET_AI:-offline}" "$GODOT" --path Godot --write-movie "$tmp/f.png" --fixed-fps 30 \
	--quit-after "$frames" -- "$@" >/dev/null 2>"$tmp/stderr.txt" || true
grep -iE "error" "$tmp/stderr.txt" | head -5 || true
cp "$(ls "$tmp"/f*.png | tail -1)" "$out"
rm -rf "$tmp"
