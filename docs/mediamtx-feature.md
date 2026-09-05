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
| Upstream | [bluenviron/mediamtx](https://github.com/bluenviron/mediamtx) **`main`** (merged 2026-09-05; not in `v1.20.1`) |
| Behaviour | When `true` and the RTSP source has a **single MPEG-TS** format, demux RTP payloads with the same MPEG-TS pipeline used for UDP/SRT sources |

### Success signal in MediaMTX

```text
[RTSP source] MPEG-TS demux mode enabled
```

API: `paths/get` -> `tracks` includes `H264` (not only `MPEG-TS`).

### Issue / PR / commit

The pull-side gap was filed as [#6138](https://github.com/bluenviron/mediamtx/issues/6138).
The implementation landed in [#6181](https://github.com/bluenviron/mediamtx/pull/6181)
(rebase of the branch linked from that issue; squash-merged to `main`).

| Link | URL |
|------|-----|
| Issue | https://github.com/bluenviron/mediamtx/issues/6138 |
| Upstream PR | https://github.com/bluenviron/mediamtx/pull/6181 |
| On `main` (squash) | [`c64b687`](https://github.com/bluenviron/mediamtx/commit/c64b687ac03cb9cc8e07932b20f4826d4dcff082) — author michalfita; `Co-authored-by: remreaygan` |
| Original commit (PR history) | [`0d21d506`](https://github.com/bluenviron/mediamtx/commit/0d21d5063e1bc7a11a71914f36ab3ddd97c76d85) — `rtsp: demux MPEG-TS from static source pull` |
| Working branch (this account) | https://github.com/resulemreaygan/mediamtx/tree/feat/rtsp-pull-mpegts-demux |

Build MediaMTX from `main` on or after `c64b687`, or wait for the first release after `v1.20.1`.
A stock `v1.20.1` binary still shows the **old** failure mode: pull OK,
`tracks: ["MPEG-TS"]`, HLS 404 — useful as a before/after demo.

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
| `rtspDemuxMpegts: true` (`main` ≥ `c64b687`) | `tracks` has `H264`, HLS 200 |

Verification steps: [verification.md](verification.md).

---

## Using the repo without caring about the PR

You can treat this project as a plain **MP2T RTSP source + MediaMTX glue**:

1. Use `samples/video_with_klv.ts` (or rebuild: [create-dummy-ts.md](create-dummy-ts.md))
2. Run the RTSP sim ([local-simulator.md](local-simulator.md))
3. Point any MediaMTX that supports `rtspDemuxMpegts` at that URL

The HTML tools and scripts do not depend on a specific GitHub PR number - only
on a MediaMTX binary that implements the flag.
