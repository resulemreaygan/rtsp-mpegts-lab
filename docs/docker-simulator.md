# Docker (optional) — RTSP simulator only

Use this if you do not want the conda GStreamer stack on the host
(especially Apple Silicon, where conda-forge `gst-rtsp-server` lacks a GI
typelib). **MediaMTX still runs on the host**; only `mpegts_rtsp_server.py`
is containerized.

The published URL is the same as conda:

```text
rtsp://127.0.0.1:8555/mp2t
```

Host `mediamtx.yml` already pulls that address — no config change.

---

## Prerequisites

- Docker Engine or Docker Desktop
- `samples/video_with_klv.ts` on the host (rebuild: [create-dummy-ts.md](create-dummy-ts.md))

---

## Run

From the repo root:

```bash
./scripts/start_rtsp_docker.sh
# or: docker compose up --build
```

Then start MediaMTX as usual (`./scripts/start_mediamtx.sh`; `main` after #6181) and
`./scripts/check.sh`.

Stop: `Ctrl+C` in the compose terminal, or `docker compose down`.

Foreground logs match the native sim (`RTSP MP2T sim - ffmpeg -re + FIFO`).

---

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `SIM_RTSP_PORT` | `8555` | **Host** port mapped to container `8555` |
| `SIM_RTSP_MOUNT` | `/mp2t` | RTSP mount path inside the container |

`samples/` is mounted read-only at `/app/samples`. Change the TS file on the
host and restart the container; you do not need to rebuild the image.

---

## vs conda

| | Conda | Docker |
|--|--------|--------|
| Where GstRtspServer runs | host Python env | Debian `bookworm` image |
| Apple Silicon typelib hack | [conda-setup.md](conda-setup.md) | not needed |
| MediaMTX | host | host |
| Lab URL | `rtsp://127.0.0.1:8555/mp2t` | same |

Pick one sim at a time — both want port `8555`.
