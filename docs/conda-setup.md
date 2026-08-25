# Conda environment setup

The RTSP MP2T simulator (`mpegts_rtsp_server.py`) needs **Python + PyGObject +
GStreamer RTSP server** bindings. That stack is easiest via **conda-forge**, not
plain `pip`.

Recommended env name: `rtsp-mpegts-lab`.

---

## Prerequisites

- Miniconda or Anaconda (`conda` on `PATH`)
- `ffmpeg` on the system `PATH` (used by the sim for realtime pacing)

```bash
conda --version
ffmpeg -version | head -1
```

---

## Create the env

Install packages **one at a time**. A single multi-package `conda install …`
solve often fails or hangs on older conda solvers.

```bash
conda create -y -n rtsp-mpegts-lab python=3.10
conda activate rtsp-mpegts-lab

conda install -y -c conda-forge pygobject
conda install -y -c conda-forge gstreamer
conda install -y -c conda-forge gst-plugins-base
conda install -y -c conda-forge gst-plugins-good
conda install -y -c conda-forge gst-plugins-bad
conda install -y -c conda-forge gst-rtsp-server
```

Optional (handy for debugging pipelines):

```bash
conda install -y -c conda-forge gst-plugins-ugly
```

Or run the helper script from the repo root:

```bash
./scripts/setup_conda_env.sh
conda activate rtsp-mpegts-lab
```

---

## Verify

```bash
conda activate rtsp-mpegts-lab
python - <<'PY'
import gi
gi.require_version("Gst", "1.0")
gi.require_version("GstRtsp", "1.0")
gi.require_version("GstRtspServer", "1.0")
from gi.repository import Gst, GstRtsp, GstRtspServer
Gst.init(None)
print("Gst:", Gst.version_string())
print("GstRtspServer: OK")
PY
```

Check plugins used by the sim:

```bash
gst-inspect-1.0 rtpmp2tpay | head -5
gst-inspect-1.0 tsparse | head -5
```

Both should print element details (not “No such element”).

---

## Point the simulator at this Python

Scripts auto-detect
`$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python` when present.
Otherwise set explicitly:

```bash
export SIM_PYTHON=$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python
# or, if you use Anaconda:
# export SIM_PYTHON=$HOME/anaconda3/envs/rtsp-mpegts-lab/bin/python

./scripts/start_rtsp_loop.sh
```

---

## Why not pip-only?

| Approach | Notes |
|----------|--------|
| `pip install PyGObject` | Needs matching system GStreamer / GI typelibs; fragile across distros |
| **conda-forge** | Ships Python, GI, and GStreamer plugins together |

`requirements.txt` in this repo is intentionally minimal — the real deps are
conda packages above.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `gi` / `GstRtspServer` import error | Re-activate env; reinstall `pygobject` + `gst-rtsp-server` |
| `No such element: rtpmp2tpay` | Install `gst-plugins-bad` |
| `No such element: tsparse` | Install `gst-plugins-bad` (mpegtsparse / tsparse) |
| Solver hangs on one big install | Install packages **sequentially** as above |
| Wrong Python used by scripts | `export SIM_PYTHON=…/envs/rtsp-mpegts-lab/bin/python` |
| Conda in a non-default prefix | Set `SIM_PYTHON` to that env’s `bin/python` |
