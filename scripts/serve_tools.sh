#!/usr/bin/env bash
# Serve tools/*.html over HTTP so the browser has a real origin (not file://).
# file:// pages cannot call MediaMTX API/HLS (blocked by the browser).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${LAB_TOOLS_PORT:-8765}"
cd "$ROOT/tools"
echo "Lab tools: http://127.0.0.1:${PORT}/"
echo "  add path : http://127.0.0.1:${PORT}/add-path.html"
echo "  watch    : http://127.0.0.1:${PORT}/watch.html"
echo
echo "MediaMTX API/HLS must allow this origin (see apiAllowOrigin / hlsAllowOrigin)."
exec python3 -m http.server "$PORT" --bind 127.0.0.1
