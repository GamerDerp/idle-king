#!/usr/bin/env bash
# Headless balance simulation: SimBot plays the real core (scripts/core), writes
# sim_out/timeline.csv (+ timeline_idle.csv) and sim_out/report.md.
# Usage: tools/simulate.sh [minutes=20] [--idle | --active] [--dt=0.05] [--seed=N] [--strict]
# Default runs both modes (active cursor player, idle player).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim_out && touch sim_out/.gdignore
MIN="${1:-20}"; [ $# -gt 0 ] && shift
if [ ! -d .godot/imported ]; then
  godot --headless --path . --import >/dev/null 2>&1 || true
fi
exec godot --headless --path . --audio-driver Dummy -s res://tools/sim/sim_main.gd -- --minutes="$MIN" "$@"
