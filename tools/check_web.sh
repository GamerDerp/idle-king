#!/usr/bin/env bash
# Exports the web build, serves it locally and boots it in headless Chrome.
# Usage: tools/check_web.sh [out.png]   (default shots/web.png). Exit 0 = game booted.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-shots/web.png}"
mkdir -p "$(dirname "$OUT")"; [ -d shots ] && touch shots/.gdignore
tools/export_web.sh
PORT=$((8800 + RANDOM % 100))
python3 -m http.server -d build/web "$PORT" >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
sleep 1
timeout 180 node tools/web_check.mjs "http://localhost:$PORT/index.html" "$OUT" 120
