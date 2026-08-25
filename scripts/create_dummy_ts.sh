#!/usr/bin/env bash
# Build samples/video_with_klv.ts (H264 + dummy KLV PES) from an input video.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIDEO="${1:-$ROOT/samples/source.mp4}"
WORK="${DUMMY_TS_WORK:-$ROOT/samples}"

if [[ ! -f "$VIDEO" ]]; then
  echo "Usage: $0 [/path/to/input.mp4]" >&2
  echo "Writes: \$DUMMY_TS_WORK/video_with_klv.ts (default: $ROOT/samples)" >&2
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

PY="${SIM_PYTHON:-}"
if [[ -z "$PY" && -x "$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python" ]]; then
  PY="$HOME/miniconda3/envs/rtsp-mpegts-lab/bin/python"
elif [[ -z "$PY" ]]; then
  PY="python3"
fi

mkdir -p "$WORK"
VIDEO="$(cd "$(dirname "$VIDEO")" && pwd)/$(basename "$VIDEO")"
cd "$WORK"

echo "==> work dir: $WORK"
echo "==> source  : $VIDEO"
echo "==> python  : $PY"

echo "==> ffmpeg -> video_only.ts"
ffmpeg -y -hide_banner -loglevel error -i "$VIDEO" \
  -c:v libx264 -profile:v main -pix_fmt yuv420p \
  -r 25 -g 50 -an \
  -f mpegts video_only.ts

echo "==> dummy.klv"
"$PY" <<'PY'
ul = bytes([
    0x06, 0x0E, 0x2B, 0x34, 0x02, 0x0B, 0x01, 0x01,
    0x0E, 0x01, 0x03, 0x01, 0x01, 0x00, 0x00, 0x00,
])
payload = b"DUMMY-KLV-TEST"
open("dummy.klv", "wb").write(ul + bytes([len(payload)]) + payload)
print("wrote dummy.klv", flush=True)
PY

echo "==> mux KLV PES -> video_with_klv.ts"
"$PY" "$ROOT/scripts/mux_dummy_klv.py" video_only.ts dummy.klv video_with_klv.ts --count 50

echo "==> ffprobe"
ffprobe -v error -show_entries stream=index,codec_type,codec_name -of csv=p=0 video_with_klv.ts

echo "==> PID 0x101 packet count"
"$PY" - <<'PY'
from pathlib import Path
data = Path("video_with_klv.ts").read_bytes()
n = len(data) // 188
pid101 = 0
for i in range(n):
    pkt = data[i * 188:(i + 1) * 188]
    pid = ((pkt[1] & 0x1F) << 8) | pkt[2]
    if pid == 0x101:
        pid101 += 1
print(f"pid 0x101 packets={pid101}")
if pid101 < 1:
    raise SystemExit("ERROR: KLV PID has no packets")
PY

echo
echo "Done."
echo "  export SIM_TS_PATH=$WORK/video_with_klv.ts"
echo "  ./scripts/start_rtsp_loop.sh"
