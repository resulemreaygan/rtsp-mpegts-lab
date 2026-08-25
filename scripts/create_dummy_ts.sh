#!/usr/bin/env bash
# Build samples/video_with_klv.ts (H264 + dummy KLV) from an input video.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIDEO="${1:-$ROOT/samples/source.mp4}"
WORK="${DUMMY_TS_WORK:-$ROOT/samples}"
TSDUCK_IMAGE="${TSDUCK_IMAGE:-miravallesg/tsduck:v3.21-1693}"

if [[ ! -f "$VIDEO" ]]; then
  echo "Usage: $0 [/path/to/input.mp4]" >&2
  echo "Writes: \$DUMMY_TS_WORK/video_with_klv.ts (default: $ROOT/samples)" >&2
  exit 1
fi

command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker required for TSDuck" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

mkdir -p "$WORK"
VIDEO="$(cd "$(dirname "$VIDEO")" && pwd)/$(basename "$VIDEO")"
cd "$WORK"

echo "==> work dir: $WORK"
echo "==> source  : $VIDEO"

if ! docker image inspect "$TSDUCK_IMAGE" >/dev/null 2>&1; then
  echo "==> pulling $TSDUCK_IMAGE"
  docker pull "$TSDUCK_IMAGE"
fi

TSDUCK=(docker run --rm -v "$WORK:/work" -w /work "$TSDUCK_IMAGE" tsp)

echo "==> ffmpeg -> video_only.ts"
ffmpeg -y -i "$VIDEO" \
  -c:v libx264 -profile:v main -pix_fmt yuv420p \
  -r 25 -g 50 -an \
  -f mpegts video_only.ts

echo "==> dummy.klv"
python3 <<'PY'
ul = bytes([
    0x06, 0x0E, 0x2B, 0x34, 0x02, 0x0B, 0x01, 0x01,
    0x0E, 0x01, 0x03, 0x01, 0x01, 0x00, 0x00, 0x00,
])
payload = b"DUMMY-KLV-TEST"
open("dummy.klv", "wb").write(ul + bytes([len(payload)]) + payload)
print("wrote dummy.klv", flush=True)
PY

echo "==> TSDuck PMT + KLV PID -> video_pmt_klv.ts"
"${TSDUCK[@]}" --add-input-stuffing 1/10 \
  -I file video_only.ts \
  -P pmt --add-pid 0x101/0x15 --add-pid-registration 0x101/0x4B4C5641 \
  -O file video_pmt_klv.ts

cp -f video_pmt_klv.ts video_with_klv.ts

echo "==> ffprobe"
ffprobe -v error -show_entries stream=index,codec_type,codec_name -of csv=p=0 video_with_klv.ts

echo
echo "Done."
echo "  export SIM_TS_PATH=$WORK/video_with_klv.ts"
echo "  ./scripts/start_rtsp_loop.sh"
