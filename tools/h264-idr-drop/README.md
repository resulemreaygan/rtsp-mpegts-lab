# h264-idr-drop

Lab tool that reproduces MediaMTX HLS muxer / recorder crashes caused by lost IDR
frames:

```text
ERR [HLS] [muxer test] muxer instance crashed: muxer error: unable to extract DTS: too many reordered frames (11)
ERR [path test] [recorder] too many reordered frames (11)
```

The DTS extractor (mediacommon `pkg/codecs/h264/dts_extractor.go`) treats the POC
reset of a new GOP whose IDR was lost as frame reordering.

## Why a dedicated tool

The bug only shows with **`pic_order_cnt_type = 0` and no B-frames**. libx264
switches to `pic_order_cnt_type = 2` when B-frames are disabled, and the DTS
extractor skips POC logic for type 2, so a plain x264 stream never crashes.

`convert` rewrites an x264 stream (`-bf 0 -coder cavlc`) into
`pic_order_cnt_type = 0` (16-bit POC LSB, 8-bit `frame_num`,
`gaps_in_frame_num_value_allowed_flag = 1`). Only SPS and slice headers change;
decoded pixels are identical (verify with `ffmpeg -f framemd5`). CAVLC is required
because slice data is shifted bitwise after the inserted header field.

`publish` sends the stream in realtime, in loop, via RTSP (gortsplib, TCP) and can
drop IDRs. Timestamps of dropped frames are skipped, as in a real loss.

## Build

```sh
cd tools/h264-idr-drop
go build -o h264-idr-drop .
```

## Prepare the input

```sh
mkdir -p /tmp/h264-idr-drop-work && cd /tmp/h264-idr-drop-work
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=25 -t 20 \
  -c:v libx264 -profile:v high -level 4.2 -pix_fmt yuv420p -preset veryfast \
  -bf 0 -refs 1 -coder cavlc -g 12 -keyint_min 12 -sc_threshold 0 \
  -x264-params repeat-headers=1 -f h264 x264.h264
/path/to/h264-idr-drop convert -in x264.h264 -out sim.h264
```

Any video can replace `testsrc2` (`-i input.mp4 -an -vf scale=1920:1080 -r 25`).

## Publish options

| Option | Meaning |
|--------|---------|
| `-drop-idr-every N` | drop every N-th IDR access unit |
| `-drop-after K` | also drop the K frames that follow a dropped IDR |
| `-keep-params` | keep SPS/PPS of dropped IDRs (default: whole access unit is dropped) |
| `-rtp-loss P` | drop P percent of RTP packets at random (large IDRs are hit most) |
| `-seed S` | random seed for `-rtp-loss` |
| `-duration D` | stop after D (e.g. `60s`) |

## Lab setup

```text
h264-idr-drop publish ──RTSP──► MediaMTX "source" (:8554, relay only)
                                        │ RTSP pull
                                        ▼
                                MediaMTX "test" (:8654, HLS :8888, recording)
```

`lab/source.yml` plays the role of the upstream encoder / media server;
`lab/test.yml` pulls from it, with `hlsAlwaysRemux` and recording enabled, so the DTS
extractor runs without viewers.

```sh
# NAME  MEDIAMTX_BIN  DURATION  [publish options]
lab/run_scenario.sh orig-drop3 /path/to/mediamtx-unpatched 60s -drop-idr-every 3
lab/run_scenario.sh fix-drop3  /path/to/mediamtx-patched   60s -drop-idr-every 3
```

Logs and a summary are written to `/tmp/h264-idr-drop-runs/NAME/`. Watch the stream
at `http://localhost:8888/test/` while a scenario runs.

Results with MediaMTX v1.21.0 (mediacommon v2.9.4), 60 s per scenario:

| Scenario | Unpatched | Patched |
|----------|-----------|---------|
| no drops | no errors | no errors |
| `-drop-idr-every 3` | 5 HLS muxer crashes (every ~11 s, 10 s recreate pause), 20 recorder errors | no errors |
| `-drop-idr-every 3 -keep-params` | 5 HLS muxer crashes, 20 recorder errors | no errors |
| `-drop-idr-every 3 -drop-after 2` | no crash, but reordered frame count stuck at 10: DTS lags PTS by up to 11.8 frames | no errors, DTS = PTS |
| `-rtp-loss 0.3` | 4 HLS muxer crashes, `too many reordered frames (11)` and `(18)` | no errors |
