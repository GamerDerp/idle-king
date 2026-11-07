#!/usr/bin/env bash
# Windows export (single exe with embedded pck) to build/windows/IdleKing.exe.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/windows && touch build/.gdignore
LOG=build/export_windows.log
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --export-release "Windows Desktop" build/windows/IdleKing.exe >"$LOG" 2>&1 || { cat "$LOG"; exit 1; }
grep -E "ERROR|WARNING" "$LOG" || true
test -f build/windows/IdleKing.exe
echo "windows build: build/windows/IdleKing.exe (log: $LOG)"
