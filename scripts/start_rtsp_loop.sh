#!/usr/bin/env bash
# Never-ending RTSP source: restart Python server if it exits.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export SIM_TS_PATH="${SIM_TS_PATH:-$HOME/dummy-ts-work/video_with_klv.ts}"
export SIM_RTSP_PORT="${SIM_RTSP_PORT:-8555}"
export SIM_RTSP_MOUNT="${SIM_RTSP_MOUNT:-/mp2t}"
export PYTHONUNBUFFERED=1

PY="${SIM_PYTHON:-}"
if [[ -z "$PY" && -x "$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python" ]]; then
  PY="$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python"
else
  PY="${PY:-python3}"
fi

echo "RTSP loop supervisor starting (Ctrl+C to stop)"
echo "  URL: rtsp://0.0.0.0:${SIM_RTSP_PORT}${SIM_RTSP_MOUNT}"
while true; do
  "$PY" "$ROOT/mpegts_rtsp_server.py" || true
  echo "[supervisor] RTSP server exited - restarting in 1s..."
  sleep 1
done
