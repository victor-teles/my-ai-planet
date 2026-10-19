#!/usr/bin/env bash
# Frames per second with a fixed crowd (default 300 villagers), in a real window with vsync off.
# Usage: scripts/fps_bench.sh [--villagers=300] [--seconds=20] [--settle=5] [--seed=42] [--years=30]
#        [--yaw=..] [--pitch=..] [--distance=..] [--focus] [--probe=noanim|nosettle]
# Prints FPS_BENCH (avg, slowest second, 1% low) and FPS_BENCH_MS (where the frame time goes).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --path src --resolution 1600x1000 -s res://tools/fps_bench.gd -- "$@" 2>&1 | grep -E "^FPS_BENCH|SCRIPT ERROR|Parse Error"
