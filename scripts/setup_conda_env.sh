#!/usr/bin/env bash
# Create conda env rtsp-mpegts-lab with PyGObject + GStreamer RTSP (one package at a time).
set -euo pipefail

ENV_NAME="${CONDA_ENV_NAME:-rtsp-mpegts-lab}"
PYTHON_VERSION="${CONDA_PYTHON_VERSION:-3.10}"

if ! command -v conda >/dev/null 2>&1; then
  echo "conda not found on PATH" >&2
  exit 1
fi

# shellcheck disable=SC1091
eval "$(conda shell.bash hook)"

if conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  echo "==> env exists: $ENV_NAME (will install/update packages)"
else
  echo "==> creating env: $ENV_NAME (python=$PYTHON_VERSION)"
  conda create -y -n "$ENV_NAME" "python=$PYTHON_VERSION"
fi

conda activate "$ENV_NAME"

pkgs=(
  pygobject
  gstreamer
  gst-plugins-base
  gst-plugins-good
  gst-plugins-bad
  gst-rtsp-server
)

for pkg in "${pkgs[@]}"; do
  echo "==> conda install -c conda-forge $pkg"
  conda install -y -c conda-forge "$pkg"
done

echo "==> verify imports"
python - <<'PY'
import gi
gi.require_version("Gst", "1.0")
gi.require_version("GstRtsp", "1.0")
gi.require_version("GstRtspServer", "1.0")
from gi.repository import Gst, GstRtspServer
Gst.init(None)
print("OK Gst", Gst.version_string())
print("OK GstRtspServer")
PY

PY_BIN="$(command -v python)"
echo
echo "Done."
echo "  conda activate $ENV_NAME"
echo "  export SIM_PYTHON=$PY_BIN"
echo "  ./scripts/start_rtsp_loop.sh"
