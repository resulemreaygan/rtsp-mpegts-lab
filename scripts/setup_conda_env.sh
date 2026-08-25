#!/usr/bin/env bash
# Create conda env rtsp-mpegts-lab with PyGObject + GStreamer RTSP (one package at a time).
set -euo pipefail

ENV_NAME="${CONDA_ENV_NAME:-rtsp-mpegts-lab}"
# conda-forge gst-rtsp-server on osx-arm64 is currently Python 3.14 only.
if [[ -z "${CONDA_PYTHON_VERSION:-}" ]]; then
  if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
    PYTHON_VERSION="3.14"
  else
    PYTHON_VERSION="3.10"
  fi
else
  PYTHON_VERSION="$CONDA_PYTHON_VERSION"
fi

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
  ffmpeg
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
if ! python - <<'PY'
import gi
gi.require_version("Gst", "1.0")
gi.require_version("GstRtsp", "1.0")
gi.require_version("GstRtspServer", "1.0")
from gi.repository import Gst, GstRtspServer
Gst.init(None)
print("OK Gst", Gst.version_string())
print("OK GstRtspServer", GstRtspServer.RTSPServer)
PY
then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "==> conda-forge osx gst-rtsp-server has no GI typelib; installing linux-64 typelib"
    prefix="${CONDA_PREFIX}"
    work="$(mktemp -d)"
    curl -fsSL -o "$work/gst-rtsp-server.conda" \
      "https://conda.anaconda.org/conda-forge/linux-64/gst-rtsp-server-1.28.2-hced25a1_0.conda"
    python - <<PY
import zipfile, tarfile, io, os, subprocess
work = r"$work"
prefix = r"$prefix"
z = zipfile.ZipFile(os.path.join(work, "gst-rtsp-server.conda"))
raw = z.read("pkg-gst-rtsp-server-1.28.2-hced25a1_0.tar.zst")
zstd = os.path.join(prefix, "bin", "zstd")
proc = subprocess.run([zstd, "-d"], input=raw, check=True, capture_output=True)
tf = tarfile.open(fileobj=io.BytesIO(proc.stdout), mode="r:")
tf.extract("lib/girepository-1.0/GstRtspServer-1.0.typelib", path=work)
os.makedirs(os.path.join(prefix, "lib", "girepository-1.0"), exist_ok=True)
os.replace(
    os.path.join(work, "lib/girepository-1.0/GstRtspServer-1.0.typelib"),
    os.path.join(prefix, "lib/girepository-1.0/GstRtspServer-1.0.typelib"),
)
PY
    ln -sfn libgstrtspserver-1.0.dylib "$prefix/lib/libgstrtspserver-1.0.so.0"
    python - <<'PY'
import gi
gi.require_version("Gst", "1.0")
gi.require_version("GstRtspServer", "1.0")
from gi.repository import Gst, GstRtspServer
Gst.init(None)
print("OK Gst", Gst.version_string())
print("OK GstRtspServer", GstRtspServer.RTSPServer)
PY
    rm -rf "$work"
  else
    exit 1
  fi
fi

PY_BIN="$(command -v python)"
echo
echo "Done."
echo "  conda activate $ENV_NAME"
echo "  export SIM_PYTHON=$PY_BIN"
echo "  ./scripts/start_rtsp_loop.sh"
