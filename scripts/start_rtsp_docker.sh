#!/usr/bin/env bash
# Optional Docker path for the MP2T RTSP simulator (same URL as conda).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH" >&2
  exit 1
fi

if [[ ! -f "$ROOT/samples/video_with_klv.ts" ]]; then
  echo "missing samples/video_with_klv.ts — rebuild with ./scripts/create_dummy_ts.sh" >&2
  exit 1
fi

exec docker compose up --build "$@"
