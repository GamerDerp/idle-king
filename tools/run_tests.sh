#!/usr/bin/env bash
# Runs all tests headless. Exit code 0 = green.
# Usage: tools/run_tests.sh [--filter=<substring>]
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d .godot/imported ]; then
  godot --headless --path . --import >/dev/null 2>&1 || true
fi
exec godot --headless --path . --audio-driver Dummy -s res://tests/run_tests.gd -- "$@"
