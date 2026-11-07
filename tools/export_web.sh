#!/usr/bin/env bash
# Web export (no threads -> works without COOP/COEP headers) to build/web/index.html.
# Serve: python3 -m http.server -d build/web 8000   then open http://localhost:8000
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web && touch build/.gdignore
LOG=build/export_web.log
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --export-release "Web" build/web/index.html >"$LOG" 2>&1 || { cat "$LOG"; exit 1; }
grep -E "ERROR|WARNING" "$LOG" || true
test -f build/web/index.html && test -f build/web/index.pck
echo "web build: build/web/ (log: $LOG)"
