# MediaMTX feature under test

## Why this repo exists

**Primary goal:** exercise and document the MediaMTX change that demuxes
**MPEG-TS carried over RTSP pull** (`MP2T` / RTP PT=33) into elementary tracks
so HLS (and other readers) work without an external remux hop.

**Secondary use:** anyone can still use the simulator + configs as a generic
lab for "RTSP with one MPEG-TS mux track -> MediaMTX -> HLS", even after the
feature is merged upstream.

```text
This repo (lab)                    MediaMTX (code under test)
---------------                    -------------------------
MP2T RTSP simulator                rtspDemuxMpegts on RTSP pull
example path YAML / API            -> elementary H264 (etc.)
watch / verify scripts             -> HLS 200
```

---

## Feature identity (point here from docs / issues)

| Item | Value |
|------|--------|
| Config / API flag | `rtspDemuxMpegts` (boolean, path-level) |
| Typical branch name | `feat/rtsp-pull-mpegts-demux` |
| Intended upstream | [bluenviron/mediamtx](https://github.com/bluenviron/mediamtx) |
| Behaviour | When `true` and the RTSP source has a **single MPEG-TS** format, demux RTP payloads with the same MPEG-TS pipeline used for UDP/SRT sources |

### Success signal in MediaMTX

```text
[RTSP source] MPEG-TS demux mode enabled
```

API: `paths/get` -> `tracks` includes `H264` (not only `MPEG-TS`).

### PR / commit links (fill when published)

Update these when the public PR exists so this lab stays tied to the change:

| Link | URL |
|------|-----|
| Upstream PR (bluenviron) | _TBD - paste after opening_ |
| Feature branch / fork | _e.g. `.../tree/feat/rtsp-pull-mpegts-demux`_ |
| Feature commit | _e.g. rewritten public commit hash_ |

Without a patched MediaMTX (flag ignored / missing), this lab will show the
**old** failure mode: pull OK, `tracks: ["MPEG-TS"]`, HLS 404 - which is still
useful as a before/after demo.

---

## Minimal path that exercises the feature

```yaml
paths:
  mpegts_sim:
    source: rtsp://127.0.0.1:8555/mp2t   # this repo's simulator
    rtspTransport: tcp
    rtspDemuxMpegts: true                # feature under test
```

| Flag | Expected lab result |
|------|---------------------|
| `rtspDemuxMpegts: false` (or stock MediaMTX) | `tracks: ["MPEG-TS"]`, HLS often 404 |
| `rtspDemuxMpegts: true` (patched build) | `tracks` has `H264`, HLS 200 |

Verification steps: [verification.md](verification.md).

---

## Using the repo without caring about the PR

You can treat this project as a plain **MP2T RTSP source + MediaMTX glue**:

1. Build a `.ts` ([create-dummy-ts.md](create-dummy-ts.md))
2. Run the RTSP sim ([local-simulator.md](local-simulator.md))
3. Point any MediaMTX that supports `rtspDemuxMpegts` at that URL

The HTML tools and scripts do not depend on a specific GitHub PR number - only
on a MediaMTX binary that implements the flag.
