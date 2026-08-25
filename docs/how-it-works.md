# How RTSP MPEG-TS demux works

Feature pointer (branch / PR / flag): [mediamtx-feature.md](mediamtx-feature.md).

## Source profile (MP2T over RTSP)

Some encoders / media servers publish **one RTSP track** whose payload is an
**MPEG-TS multiplex** (H.264 + optional KLV / other PIDs), advertised in SDP as:

```text
m=video ... RTP/AVP 33
a=rtpmap:33 MP2T/90000
```

That is **not** the same as RTSP with separate `H264` / `mpeg4-generic` tracks.

```text
+--------------------+     RTSP (TCP/UDP)      +--------------------+
|  Upstream encoder  | ----------------------> |  MediaMTX (pull)   |
|  1x MP2T track     |   RTP PT=33 MPEG-TS    |                    |
+--------------------+                        +--------------------+
```

## Why HLS failed before the patch

MediaMTX already demuxes MPEG-TS for **UDP / SRT** static sources
(`mpegts.ToStream()` -> H264, KLV, ...).

For **RTSP pull**, the old behaviour was:

1. DESCRIBE -> SDP with a single MPEG-TS media
2. `SetReady(desc)` with that description unchanged
3. RTP passthrough -> internal stream tracks = `["MPEG-TS"]`
4. HLS muxer looks for H264/H265/AV1/... -> **no muxer** -> playlist **404**

`ffprobe` on the same URL can still show `h264` + `klv` because **ffprobe demuxes
the TS client-side**. That must not be used as proof that MediaMTX demuxed.

| Check | Reliable? |
|-------|-----------|
| MediaMTX API `paths/get` -> `tracks` | Yes |
| Log `MPEG-TS demux mode enabled` | Yes |
| `ffprobe` on RTSP URL | No (client demux) |

## What the patch does

When path config has `rtspDemuxMpegts: true` and the RTSP source exposes an
MPEG-TS (MP2T) track:

1. RTSP client receives RTP PT=33 packets
2. Payload bytes are fed into an MPEG-TS demuxer (`mpegts.ToStream`)
3. Internal stream is rebuilt with **elementary tracks** (H264, and KLV when the TS has PES)
4. HLS / WebRTC / recording can attach as usual

```text
RTSP pull (MP2T)
       |
       v
+------------------+
| RTP depayload    |  PT=33 -> TS bytes
+--------+---------+
         |
         v
+------------------+
| mpegts.ToStream  |  PID -> H264 / KLV / ...
+--------+---------+
         |
         v
  tracks: ["H264", ...]  ->  HLS muxer OK
```

Relevant MediaMTX areas (fork):

| Piece | Role |
|-------|------|
| `conf.Path.RTSPDemuxMpegts` | Path / API flag |
| `internal/staticsources/rtsp` | Pull source + demux wiring |
| `internal/protocols/rtpmpegts` | RTP MPEG-TS depayload |

Upstream UDP/SRT demux path is unchanged. RTSP **publish** demux (if present
upstream) is separate from **pull**.

## Enabling the flag

Set `rtspDemuxMpegts: true` on paths whose `source` is an RTSP URL that
carries MP2T. Ordinary elementary-H264 RTSP sources do not need it.

After deploying a new MediaMTX binary or changing the flag, **recreate** the
path (or replace its config) so the running instance picks up the setting.

## KLV / metadata

Demux may surface data tracks (e.g. KLV). HLS usually selects the video track
only; KLV is not expected in the HLS playlist. Playback still works when H264
is present on the path.

## Known operational pitfalls

1. **Stale path** - create/replace path after deploying the patched binary.
2. **Bursting lab source** - a file-based RTSP sim that dumps TS faster than
   realtime will look "alive" for a few seconds then stall; pace with
   `ffmpeg -re` (this repo's simulator).
3. **Wrong success metric** - do not trust ffprobe alone; use API `tracks`.
