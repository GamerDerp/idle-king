#!/usr/bin/env bash
# Headless balance simulation (bot plays the core logic, writes timeline to sim_out/).
# Usage: tools/simulate.sh [minutes] [extra args]
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim_out && touch sim_out/.gdignore
MIN="${1:-60}"; [ $# -gt 0 ] && shift
exec godot --headless --path . --audio-driver Dummy -s res://tools/sim/sim_main.gd -- --minutes="$MIN" "$@"
