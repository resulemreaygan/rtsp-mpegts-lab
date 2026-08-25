# Local MP2T RTSP simulator

This repository's simulator exposes a **single MP2T** RTSP track so you can
test `rtspDemuxMpegts` without an upstream encoder.

## Architecture

```text
  video_with_klv.ts
         |
         v
  ffmpeg -re -stream_loop -1 -map 0   <- realtime pace, loop, keep KLV
         |
         v
      FIFO (mpegts)
         |
         v
  GStreamer RTSP server
  filesrc ! tsparse ! rtpmp2tpay (PT=33)
         |
         v
  rtsp://0.0.0.0:8555/mp2t
```

Why FIFO + `ffmpeg -re`?

- Plain `filesrc` dumps the file in a few wall-clock seconds -> players stall.
- `clocksync` inside GstRtspServer can deadlock DESCRIBE/PREPARE.
- `ffmpeg -re` is a reliable realtime pacer; the FIFO couples it to GStreamer.

## Dependencies

- Python 3.10+ with PyGObject
- GStreamer 1.x + `gst-rtsp-server` + `rtpmp2tpay` / `tsparse`
- `ffmpeg` on `PATH`
- Patched MediaMTX binary for demux

Conda env: `rtsp-mpegts-lab` (PyGObject + GStreamer bindings).
Full install steps: [conda-setup.md](conda-setup.md) or `./scripts/setup_conda_env.sh`.

## Quick start

```bash
# Terminal 1 - RTSP source (auto-restart supervisor)
export SIM_TS_PATH=$PWD/samples/video_with_klv.ts   # default if unset
export SIM_PYTHON=$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python
./scripts/start_rtsp_loop.sh
# -> rtsp://127.0.0.1:8555/mp2t

# Terminal 2 - MediaMTX
export MEDIAMTX_BIN=../mediamtx/mediamtx                   # patched binary
./scripts/start_mediamtx.sh
# log: MPEG-TS demux mode enabled -> ready H264 (KLV if the TS has PES)

# Terminal 3 - checks
./scripts/check.sh
```

### Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `SIM_TS_PATH` | `samples/video_with_klv.ts` | Input MPEG-TS (H264+KLV OK) |
| `SIM_RTSP_PORT` | `8555` | Simulator listen port |
| `SIM_RTSP_MOUNT` | `/mp2t` | RTSP mount path |
| `SIM_PYTHON` | `python3` | Interpreter with GI |
| `MEDIAMTX_BIN` | `../mediamtx/mediamtx` | Patched MTX binary |
| `MEDIAMTX_CONFIG` | `./mediamtx.yml` | Config for `start_mediamtx.sh` |

## Dual-node lab layout (optional)

Scripts `start_mtx_node1.sh` / `start_mtx_node2.sh` start two MediaMTX
processes with non-overlapping ports (see `mediamtx-node1.yml` /
`mediamtx-node2.yml`). Useful when exercising a multi-node lab setup.

| | Node 1 | Node 2 |
|--|--------|--------|
| API | `:9997` | `:19997` |
| RTSP | `:8554` | `:18554` |
| HLS | `:8888` | `:18888` |

Both should set `pathDefaults.rtspDemuxMpegts: true` (or per-path) when testing
MP2T pull.

## Input TS tips

- Prefer a real H264+KLV sample (~1080p25) similar to production.
- Duration of tens of seconds is enough; the sim loops forever.
- Do **not** re-encode through a pipeline that splits elementary RTSP tracks if
  you need the MP2T-over-RTSP profile.
- Sample files are **not** in git - see [create-dummy-ts.md](create-dummy-ts.md)
  or run `./scripts/create_dummy_ts.sh /path/to/input.mp4`.

## Troubleshooting the sim

| Symptom | Fix |
|---------|-----|
| DESCRIBE hangs | Avoid `clocksync` in the RTSP factory pipeline |
| Plays ~5-6 s then stops | Source not paced - ensure `ffmpeg -re` loop is running |
| MTX `ready=false` | Recreate path after sim restart; confirm URL/port |
| Port 8555 in use | Stop old `mpegts_rtsp_server.py` / supervisor |
