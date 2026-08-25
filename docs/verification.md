# Verification checklist

Replace `PATH`, `MTX_API`, and HLS base as needed.

```bash
PATH=demux-test
MTX_API=http://127.0.0.1:9997   # or :19997 for a second node
HLS_BASE=http://127.0.0.1:8888
```

## 1. Config flag

```bash
curl -s "$MTX_API/v3/config/paths/get/$PATH" | jq '{source, rtspDemuxMpegts, rtspTransport}'
```

Expect: `"rtspDemuxMpegts": true`.

## 2. Runtime tracks (critical)

```bash
curl -s "$MTX_API/v3/paths/get/$PATH" | jq '{ready, tracks, bytesReceived}'
```

| Result | Meaning |
|--------|---------|
| `ready=true`, `tracks` contains `H264` | Demux OK |
| `tracks` also contains `KLV` | TS had real KLV PES (optional; HLS still uses video) |
| `tracks: ["MPEG-TS"]` | Flag off or old binary |
| `ready=false` | Source unreachable / auth / stuck pull |

Optional: sample `bytesReceived` twice a few seconds apart - delta must be &gt; 0.

## 3. HLS muxer

```bash
curl -s "$MTX_API/v3/hlsmuxers/list" | jq --arg p "$PATH" '.items[]? | select(.path==$p)'
curl -sI "$HLS_BASE/$PATH/index.m3u8"
curl -s "$HLS_BASE/$PATH/index.m3u8" | head
```

Expect HTTP **200** and `#EXTM3U`.

## 4. Logs

Success:

```text
[RTSP source] MPEG-TS demux mode enabled
... ready: 1 track (H264)   # or 2 tracks (H264, KLV) when PES is present
... is converting into HLS ...
```

Failure hints:

| Observation | Likely cause |
|-------------|--------------|
| No demux log + tracks MPEG-TS | Old binary / flag false |
| `MPEG-TS demuxer error` | Bad TS / RTP loss |
| ready false | RTSP URL / network / source down |
| HLS 404, tracks H264 | Muxer crash - check HLS logs |

## 5. Result matrix

| tracks | demux log | HLS | Verdict |
|--------|-----------|-----|---------|
| H264 | yes | 200 | Pass |
| MPEG-TS | no | 404 | Patch/flag missing |
| MPEG-TS | yes | 404 | Demux parse failure |
| H264 | yes | 404 | Muxer issue |
| ready false | - | - | Source issue |

## 6. Do not use as sole proof

```bash
ffprobe -rtsp_transport tcp "$SOURCE_URL"
```

ffprobe may list h264+klv even when MediaMTX still exposes `MPEG-TS` internally.
