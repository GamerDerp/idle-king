#!/usr/bin/env bash
# Takes a screenshot of the running game under xvfb.
# Usage: tools/screenshot.sh <game-seconds> <out.png> [extra game args, e.g. --timescale=10 --lang=en]
# The game itself saves the frame after <game-seconds> of GAME time and quits.
set -euo pipefail
if [ $# -lt 2 ]; then
  echo "usage: $0 <seconds> <out.png> [extra args]" >&2
  exit 2
fi
SECS="$1"; OUT="$2"; shift 2
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
cd "$(dirname "$0")/.."
mkdir -p "$(dirname "$OUT")"
# keep Godot from importing screenshots stored inside the project
[ -d shots ] && [ ! -f shots/.gdignore ] && touch shots/.gdignore
if [ ! -d .godot/imported ]; then
  godot --headless --path . --import >/dev/null 2>&1 || true
fi
# real-time safety timeout so a hung game never blocks the caller
LIMIT=$(python3 -c "print(int(float('$SECS'))+60)")
timeout "$LIMIT" xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -- --shot="$OUT" --shot-time="$SECS" "$@"
test -f "$OUT" && echo "screenshot: $OUT"
