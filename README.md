# rtsp-mpegts-lab

Lab harness for **RTSP sources that publish a single MPEG-TS mux track**
(H.264 + optional KLV / data) into MediaMTX -> HLS.

### Purpose

| | |
|--|--|
| **Primary** | Test / demonstrate **`rtspDemuxMpegts` on RTSP pull**, merged to [bluenviron/mediamtx](https://github.com/bluenviron/mediamtx) `main` in [#6181](https://github.com/bluenviron/mediamtx/pull/6181). See **[docs/mediamtx-feature.md](docs/mediamtx-feature.md)**. |
| **Also fine** | Generic MP2T RTSP simulator + example configs against any MediaMTX that implements the flag (`main` after 2026-09-05, or a later release). |

Without a MediaMTX build that implements the flag, you can still reproduce the
**pre-fix** behaviour (pull works, HLS 404 / `tracks: ["MPEG-TS"]`).

This repository contains:

1. **Documentation** - how the demux works, how to enable it, how to verify it
2. **Local RTSP MP2T simulator** - GStreamer RTSP server exposing `MP2T/90000`
3. **Example MediaMTX configs** - paths with `rtspDemuxMpegts: true`
4. **Lab HTML tools** - add a path and watch HLS when the stream becomes ready

---

## Problem (short)

| Before | After (`rtspDemuxMpegts: true`) |
|--------|----------------------------------|
| RTSP pull -> tracks `["MPEG-TS"]` | RTSP pull -> tracks `["H264", ...]` |
| HLS muxer missing -> `index.m3u8` **404** | HLS muxer runs -> playlist **200** |
| Extra remux/transcode path required | Same path serves HLS after demux |

`ffprobe` can show h264+klv even when MediaMTX still has `MPEG-TS` - **always
trust the MediaMTX API `tracks` field**.

---

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/mediamtx-feature.md](docs/mediamtx-feature.md) | **Feature under test** - flag, branch, PR links |
| [docs/how-it-works.md](docs/how-it-works.md) | Source profile, root cause, demux pipeline |
| [docs/mediamtx-config.md](docs/mediamtx-config.md) | YAML / API flag |
| [docs/verification.md](docs/verification.md) | Curl checklist and result matrix |
| [docs/local-simulator.md](docs/local-simulator.md) | Lab RTSP server (ffmpeg -re + FIFO) |
| [docs/create-dummy-ts.md](docs/create-dummy-ts.md) | Rebuild `samples/video_with_klv.ts` if needed |
| [docs/conda-setup.md](docs/conda-setup.md) | Conda env for PyGObject / GStreamer RTSP |
| [docs/docker-simulator.md](docs/docker-simulator.md) | Optional Docker image for the RTSP sim only |

---

## Related components

| Component | Role |
|-----------|------|
| **MediaMTX** (feature under test) | `rtspDemuxMpegts` on RTSP pull - see [docs/mediamtx-feature.md](docs/mediamtx-feature.md) |
| **This repo** | Docs + MP2T RTSP simulator + examples to validate that feature |

MediaMTX log line that confirms demux:

```text
[RTSP source] MPEG-TS demux mode enabled
```

Upstream pointers (issue, PR, commits): [docs/mediamtx-feature.md](docs/mediamtx-feature.md).

---

## Quick start (local lab)

### Prerequisites

- MediaMTX built from `main` on or after [#6181](https://github.com/bluenviron/mediamtx/pull/6181) (`c64b687`), or a release newer than `v1.20.1`
- Python 3 + PyGObject + GStreamer RTSP server plugins
  -> [docs/conda-setup.md](docs/conda-setup.md) or `./scripts/setup_conda_env.sh`
  -> or Docker for the sim only: [docs/docker-simulator.md](docs/docker-simulator.md)
- `ffmpeg` on `PATH` (conda sim; Docker image already includes it)
- Dummy MPEG-TS in `samples/video_with_klv.ts` (H264 + dummy KLV; rebuild via
  [docs/create-dummy-ts.md](docs/create-dummy-ts.md))

### Run

```bash
# 1) MP2T RTSP source (defaults to samples/video_with_klv.ts)
#    conda:
export SIM_PYTHON=/path/to/python   # with gi / GstRtspServer
./scripts/start_rtsp_loop.sh
#    or Docker (no conda):
# ./scripts/start_rtsp_docker.sh
# listens on rtsp://127.0.0.1:8555/mp2t

# 2) MediaMTX (example config pulls the sim and demuxes)
export MEDIAMTX_BIN=/path/to/mediamtx   # main after #6181, not v1.20.1
./scripts/start_mediamtx.sh

# 3) Verify
./scripts/check.sh
```

Success looks like:

```text
tracks: ["H264"]
http://127.0.0.1:8888/mpegts_sim/index.m3u8  ->  200
```

Minimal path shape:

```yaml
paths:
  mpegts_sim:
    source: rtsp://127.0.0.1:8555/mp2t
    rtspTransport: tcp
    rtspDemuxMpegts: true
```

More examples: [examples/](examples/).
Lab UI (must be served over HTTP - `file://` is blocked by the browser):

```bash
./scripts/serve_tools.sh
# -> http://127.0.0.1:8765/add-path.html
# -> http://127.0.0.1:8765/watch.html
```

MediaMTX lab configs set `apiAllowOrigin` / `hlsAllowOrigin` to `*` so these pages can call the API and HLS.

---

## Production usage (summary)

1. Deploy MediaMTX from `main` after [#6181](https://github.com/bluenviron/mediamtx/pull/6181), or a release newer than `v1.20.1`.
2. Set `rtspDemuxMpegts: true` on MP2T RTSP pull paths (YAML or API).
3. **Recreate** the path if it was created with an older config/binary.
4. Confirm API `tracks` includes `H264` and HLS returns 200.

Full checklist: [docs/verification.md](docs/verification.md).

---

## Repository layout

```text
.
|-- LICENSE
|-- README.md
|-- samples/
|   |-- README.md
|   |-- source.mp4             # 10s dummy clip (CC BY 3.0)
|   |-- video_with_klv.ts      # H264 + dummy KLV MPEG-TS
|   `-- dummy.klv
|-- docs/
|   |-- README.md
|   |-- mediamtx-feature.md    # flag / branch / PR pointers
|   |-- how-it-works.md
|   |-- mediamtx-config.md
|   |-- verification.md
|   |-- local-simulator.md
|   |-- create-dummy-ts.md     # rebuild samples/video_with_klv.ts
|   |-- conda-setup.md         # conda env for the RTSP simulator
|   `-- docker-simulator.md    # optional Docker for the RTSP sim only
|-- examples/
|   |-- mediamtx-path.yml
|   `-- path-config.json
|-- tools/
|   |-- add-path.html          # add path via MediaMTX API
|   `-- watch.html             # wait until ready, play HLS
|-- mpegts_rtsp_server.py      # RTSP MP2T simulator
|-- Dockerfile                 # optional sim image (Debian + GstRtspServer)
|-- compose.yaml
|-- mediamtx.yml               # single-node lab config
|-- mediamtx-node1.yml         # optional dual-node lab
|-- mediamtx-node2.yml
|-- requirements.txt
`-- scripts/
    |-- start_rtsp_loop.sh
    |-- start_rtsp_server.sh
    |-- start_mediamtx.sh
    |-- start_mtx_node1.sh
    |-- start_mtx_node2.sh
    |-- serve_tools.sh         # http://127.0.0.1:8765 for HTML tools
    |-- create_dummy_ts.sh     # build video_with_klv.ts from an MP4
    |-- setup_conda_env.sh     # create conda env + GStreamer deps
    |-- start_rtsp_docker.sh   # docker compose up for the sim
    `-- check.sh
```

---

## License

[MIT](LICENSE). Dual-node YAML files use open auth for **local lab only** -
do not reuse that auth model in production.
