#!/usr/bin/env bash
set -euo pipefail

PATH_NAME="${1:-mpegts_sim}"
MTX_API="${MTX_API:-http://127.0.0.1:9997}"
HLS_BASE="${HLS_BASE:-http://127.0.0.1:8888}"
SOURCE_RTSP="${SOURCE_RTSP:-rtsp://127.0.0.1:8555/mp2t}"

echo "=== 0) Source RTSP (optional ffprobe) ==="
if command -v ffprobe >/dev/null 2>&1; then
  ffprobe -v error -show_entries stream=codec_type,codec_name \
    -of csv=p=0 "$SOURCE_RTSP" || echo "(ffprobe source failed - server up?)"
else
  echo "ffprobe not installed, skip"
fi

echo
echo "=== 1) Path config (rtspDemuxMpegts) ==="
curl -s "$MTX_API/v3/config/paths/get/$PATH_NAME" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps({k:d.get(k) for k in ('source','rtspDemuxMpegts','rtspTransport')}, indent=2))"

echo
echo "=== 2) Path state (tracks) ==="
curl -s "$MTX_API/v3/paths/get/$PATH_NAME" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps({k:d.get(k) for k in ('ready','tracks','bytesReceived','bytesSent')}, indent=2))"

echo
echo "=== 3) HLS muxers ==="
curl -s "$MTX_API/v3/hlsmuxers/list" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); items=d.get('items') or []; print([i.get('path') for i in items])"

echo
echo "=== 4) HLS m3u8 ==="
code=$(curl -s -o /tmp/mpegts_sim.m3u8 -w "%{http_code}" "$HLS_BASE/$PATH_NAME/index.m3u8" || true)
echo "HTTP $code"
head -5 /tmp/mpegts_sim.m3u8 2>/dev/null || true

echo
echo "Success if: rtspDemuxMpegts=true, tracks has H264 (not only MPEG-TS), m3u8 HTTP 200"
echo "Optional: tracks also lists KLV when the source TS has KLV PES packets"
