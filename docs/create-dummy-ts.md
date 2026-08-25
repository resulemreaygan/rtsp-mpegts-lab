# Create a dummy MPEG-TS (H264 + dummy KLV)

The lab ships a small dummy under [`samples/`](../samples/README.md)
(`source.mp4`, `video_with_klv.ts`, `dummy.klv`). Rebuild it with the steps
below if you change the source clip.

Target profile for demux / HLS lab work:

| Track | Codec | Notes |
|-------|-------|-------|
| video | H.264 | Main, 25 fps, **no audio** |
| data | KLV | Real PES packets on PID `0x101` (dummy payload, not MISB telemetry) |

`ffprobe` success check:

```text
h264,video
klv,data
```

That is not enough. PID `0x101` must also have packets (a PMT-only KLV
entry is dropped by `ffmpeg -c copy` and never reaches MediaMTX).

---

## Tools

| Tool | Role |
|------|------|
| **FFmpeg** | Encode video to MPEG-TS |
| **Python 3** | Dummy `.klv` blob + PES mux (`scripts/mux_dummy_klv.py`) |

Verified with FFmpeg 4.x / 7.x. Docker / TSDuck is not required.

The mux writes asynchronous KLV the way MediaMTX's MPEG-TS reader
expects it:

| Field | Value |
|-------|-------|
| PID | `0x101` |
| Stream type | `0x06` (private data) |
| Registration | `KLVA` (`0x4B4C5641`) |
| PES stream id | `0xBD` |
| Payload | contents of `dummy.klv` |

---

## Quick path (H264 only)

If you only need video inside MPEG-TS (enough for `rtspDemuxMpegts` -> HLS):

```bash
cd samples
ffmpeg -y -i source.mp4 \
  -c:v libx264 -profile:v main -pix_fmt yuv420p \
  -r 25 -g 50 -an \
  -f mpegts video_with_klv.ts

ffprobe -v error -show_entries stream=codec_type,codec_name -of csv=p=0 video_with_klv.ts
```

Then:

```bash
export SIM_TS_PATH=$PWD/samples/video_with_klv.ts
```

---

## Full path (H264 + dummy KLV PES)

### 1) Video-only MPEG-TS

```bash
cd samples
ffmpeg -y -i source.mp4 \
  -c:v libx264 -profile:v main -pix_fmt yuv420p \
  -r 25 -g 50 -an \
  -f mpegts video_only.ts
```

Already H.264 and acceptable?

```bash
ffmpeg -y -i source.mp4 -c:v copy -an -f mpegts video_only.ts
```

### 2) Dummy KLV blob

```bash
python3 <<'PY'
ul = bytes([
    0x06, 0x0E, 0x2B, 0x34, 0x02, 0x0B, 0x01, 0x01,
    0x0E, 0x01, 0x03, 0x01, 0x01, 0x00, 0x00, 0x00,
])
payload = b"DUMMY-KLV-TEST"
open("dummy.klv", "wb").write(ul + bytes([len(payload)]) + payload)
print("dummy.klv OK", len(open("dummy.klv", "rb").read()), "bytes")
PY
```

### 3) Mux KLV PES into the TS

A PMT `--add-pid` with no PES is not a KLV stream. Use the lab muxer:

```bash
python3 ../scripts/mux_dummy_klv.py video_only.ts dummy.klv video_with_klv.ts --count 50
```

### 4) Verify packets, not only PMT

```bash
ffprobe -v error -show_entries stream=index,codec_type,codec_name \
  -of csv=p=0 video_with_klv.ts

python3 - <<'PY'
from pathlib import Path
data = Path("video_with_klv.ts").read_bytes()
n = sum(
    1 for i in range(len(data)//188)
    if (((data[i*188+1] & 0x1F) << 8) | data[i*188+2]) == 0x101
)
print("pid 0x101 packets", n)
assert n > 0
PY
```

Expected:

```text
0,h264,video
1,klv,data
pid 0x101 packets 50
```

`ffmpeg -map 0 -c copy` must still list `klv` after remux. The lab RTSP
simulator maps all input streams (`-map 0`) for that reason.

### 5) Use with this repo's RTSP simulator

```bash
export SIM_TS_PATH=$PWD/samples/video_with_klv.ts
./scripts/start_rtsp_loop.sh
# -> rtsp://127.0.0.1:8555/mp2t
```

See [local-simulator.md](local-simulator.md).

---

## One-shot script

```bash
./scripts/create_dummy_ts.sh
# or: ./scripts/create_dummy_ts.sh /path/to/your.mp4
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Only `h264` in ffprobe | Muxer did not run; check `video_only.ts` exists |
| `klv` in ffprobe, PID `0x101` packet count 0 | PMT-only file; re-run `mux_dummy_klv.py` |
| Live RTSP ffprobe has no KLV | Simulator must use `-map 0` (this repo does) |
| MediaMTX tracks has H264 but not KLV | Confirm live TS still has PID `0x101` packets |
| Huge file / slow encode | Use `-c:v copy -an` when source is already H.264 |
| Rebuild intermediates | `samples/video_only.ts` is gitignored |

---

## What not to put in git

- Real camera or field recordings
- Real telemetry KLV captures (use the dummy blob above for labs)

The small dummy under `samples/` is intended for this repo.
