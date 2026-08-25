#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export SIM_TS_PATH="${SIM_TS_PATH:-$HOME/dummy-ts-work/video_with_klv.ts}"
export SIM_RTSP_PORT="${SIM_RTSP_PORT:-8555}"
export SIM_RTSP_MOUNT="${SIM_RTSP_MOUNT:-/mp2t}"
export PYTHONUNBUFFERED=1

PY="${SIM_PYTHON:-}"
if [[ -z "$PY" && -x "$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python" ]]; then
  PY="$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python"
elif [[ -z "$PY" ]]; then
  PY="python3"
fi

exec "$PY" "$ROOT/mpegts_rtsp_server.py" "$@"
