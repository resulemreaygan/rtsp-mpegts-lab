#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${MEDIAMTX_BIN:-$ROOT/../mediamtx/mediamtx}"
CFG="${MEDIAMTX_CONFIG:-$ROOT/mediamtx.yml}"

if [[ ! -x "$BIN" ]]; then
  echo "ERROR: MediaMTX binary not found/executable: $BIN" >&2
  echo "Build MediaMTX main (after #6181) or set MEDIAMTX_BIN." >&2
  exit 1
fi

echo "Starting MediaMTX: $BIN"
echo "Config          : $CFG"
exec "$BIN" "$CFG"
