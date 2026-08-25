#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${MEDIAMTX_BIN:-$ROOT/../mediamtx/mediamtx}"
exec "$BIN" "$ROOT/mediamtx-node2.yml"
