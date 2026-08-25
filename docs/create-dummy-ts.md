# Create a dummy MPEG-TS (H264 + optional KLV)

The lab ships a small dummy under [`samples/`](../samples/README.md)
(`source.mp4`, `video_with_klv.ts`, `dummy.klv`). Rebuild it with the steps
below if you change the source clip.

Target profile for demux / HLS lab work:

| Track | Codec | Notes |
|-------|-------|-------|
| video | H.264 | Main, ~1080p25, **no audio** |
| data (optional) | KLV | Dummy payload - not real MISB telemetry |

`ffprobe` success check:

```text
h264,video
klv,data
```

(order may vary)

---

## Tools

| Tool | Role |
|------|------|
| **FFmpeg** | Encode / remux video to MPEG-TS |
| **Docker** | Run TSDuck without a native package |
| **TSDuck (`tsp`)** | Add a KLV PID to the PMT (FFmpeg often cannot mux KLV) |
| **Python 3** | Tiny dummy `.klv` blob |

Verified with FFmpeg 4.x and Docker image `miravallesg/tsduck:v3.21-1693`.

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

## Full path (H264 + dummy KLV)

### 0) Docker (once)

```bash
sudo apt update && sudo apt install -y docker.io ffmpeg
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# re-login or: newgrp docker
docker pull miravallesg/tsduck:v3.21-1693
```

### 1) Work directory

```bash
cd samples
export TSDUCK="docker run --rm -v $(pwd):/work -w /work miravallesg/tsduck:v3.21-1693 tsp"
$TSDUCK --version
```

### 2) Video-only MPEG-TS

```bash
export VIDEO=$PWD/samples/source.mp4

ffmpeg -y -i "$VIDEO" \
  -c:v libx264 -profile:v main -pix_fmt yuv420p \
  -r 25 -g 50 -an \
  -f mpegts video_only.ts
```

Already H.264 and acceptable?

```bash
ffmpeg -y -i "$VIDEO" -c:v copy -an -f mpegts video_only.ts
```

Check:

```bash
ffprobe -v error -show_entries stream=codec_type,codec_name,profile,width,height \
  -of csv=p=0 video_only.ts
```

### 3) Dummy KLV blob

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

### 4) Add KLV PID to the PMT (TSDuck)

FFmpeg TS often has little stuffing - use `--add-input-stuffing`:

```bash
$TSDUCK --add-input-stuffing 1/10 \
  -I file video_only.ts \
  -P pmt --add-pid 0x101/0x15 --add-pid-registration 0x101/0x4B4C5641 \
  -O file video_pmt_klv.ts
```

| Parameter | Value |
|-----------|-------|
| KLV PID | `0x101` (avoid clash with video `0x100`) |
| Stream type | `0x15` (synchronous KLV) |
| Registration | `0x4B4C5641` (`KLVA`) |

### 5) Verify and name the lab file

```bash
ffprobe -v error -show_entries stream=index,codec_type,codec_name \
  -of csv=p=0 video_pmt_klv.ts

cp video_pmt_klv.ts video_with_klv.ts
```

Expected:

```text
0,h264,video
1,klv,data
```

If you only see `h264`, try stream type `0x06` (async) or a merge-based
TSDuck pipeline ([tsduck#1230](https://github.com/tsduck/tsduck/issues/1230)).

### 6) Use with this repo's RTSP simulator

```bash
export SIM_TS_PATH=$PWD/samples/video_with_klv.ts
./scripts/start_rtsp_loop.sh
# -> rtsp://127.0.0.1:8555/mp2t
```

See [local-simulator.md](local-simulator.md).

---

## One-shot script

```bash
export VIDEO=$PWD/samples/source.mp4
export WORK=$PWD/samples

mkdir -p "$WORK" && cd "$WORK"
docker pull miravallesg/tsduck:v3.21-1693
export TSDUCK="docker run --rm -v $(pwd):/work -w /work miravallesg/tsduck:v3.21-1693 tsp"

ffmpeg -y -i "$VIDEO" \
  -c:v libx264 -profile:v main -pix_fmt yuv420p -r 25 -g 50 -an \
  -f mpegts video_only.ts

python3 <<'PY'
ul = bytes([0x06,0x0E,0x2B,0x34,0x02,0x0B,0x01,0x01,0x0E,0x01,0x03,0x01,0x01,0x00,0x00,0x00])
payload = b"DUMMY-KLV-TEST"
open("dummy.klv","wb").write(ul + bytes([len(payload)]) + payload)
PY

$TSDUCK --add-input-stuffing 1/10 \
  -I file video_only.ts \
  -P pmt --add-pid 0x101/0x15 --add-pid-registration 0x101/0x4B4C5641 \
  -O file video_pmt_klv.ts

cp video_pmt_klv.ts video_with_klv.ts
ffprobe -v error -show_entries stream=codec_type,codec_name -of csv=p=0 video_with_klv.ts
echo "SIM_TS_PATH=$WORK/video_with_klv.ts"
```

The same flow is wrapped in [scripts/create_dummy_ts.sh](../scripts/create_dummy_ts.sh):

```bash
./scripts/create_dummy_ts.sh
# or: ./scripts/create_dummy_ts.sh /path/to/your.mp4
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `docker: permission denied` | Add user to `docker` group, re-login |
| Only `h264` after TSDuck | Try `--add-pid 0x101/0x06`; check stuffing |
| Huge file / slow encode | Use `-c:v copy -an` when source is already H.264 |
| Rebuild intermediates | `samples/video_only.ts` and `samples/video_pmt_klv.ts` are gitignored |

---

## What not to put in git

- Real camera or field recordings
- Real telemetry KLV captures (use the dummy blob above for labs)

The small dummy under `samples/` is intended for this repo.
