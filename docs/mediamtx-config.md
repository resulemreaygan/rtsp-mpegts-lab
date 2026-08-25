# MediaMTX configuration

Requires a MediaMTX build that implements **RTSP pull MPEG-TS demux**
(feature flag `rtspDemuxMpegts`; example branch `feat/rtsp-pull-mpegts-demux`).

This lab's main job is to test that feature - see
[mediamtx-feature.md](mediamtx-feature.md).

## Path flag

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `rtspDemuxMpegts` | boolean | `false` | Demux MP2T on RTSP **static source pull** |

### YAML

```yaml
paths:
  my-stream:
    source: rtsp://encoder.example/mp2t
    rtspTransport: tcp
    rtspDemuxMpegts: true
```

See also [examples/mediamtx-path.yml](../examples/mediamtx-path.yml).

### API (v3)

Add:

```bash
curl -s -X POST "$MTX_API/v3/config/paths/add/my-stream" \
  -H 'Content-Type: application/json' \
  -d @examples/path-config.json
```

Or use the optional lab helper: [tools/add-path.html](../tools/add-path.html).

Replace / patch / delete use the standard MediaMTX config endpoints
(`replace`, `patch`, `DELETE .../delete/{name}`).

### pathDefaults

You may set a default for all paths:

```yaml
pathDefaults:
  rtspDemuxMpegts: true
  rtspTransport: tcp
```

Prefer **per-path** `true` only for MP2T sources so ordinary RTSP (elementary
H264) paths are unaffected.

## Companion settings

| Setting | Recommendation for MP2T-over-RTSP sources |
|---------|-------------------------------------|
| `rtspTransport` | `tcp` (stable over lossy links) |
| `source` | Full RTSP URL of the MP2T mount |
| HLS | Enable globally; no extra path flag required once tracks include H264 |

## Verify after create

```bash
curl -s "$MTX_API/v3/config/paths/get/$PATH" | jq '{source, rtspDemuxMpegts, rtspTransport}'
```

## Binary check

Old binary: flag ignored or rejected; `tracks` stay `["MPEG-TS"]`.

Patched binary log on connect:

```text
[path my-stream] [RTSP source] MPEG-TS demux mode enabled
[path my-stream] [RTSP source] ready: 1 track (H264)
```
