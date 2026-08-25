# Sample media

Small dummy assets for the local MP2T RTSP simulator. Safe to commit.

| File | Role |
|------|------|
| `source.mp4` | 10s Big Buck Bunny clip (H.264, 640x360), CC BY 3.0 |
| `video_with_klv.ts` | Same video remuxed to MPEG-TS plus dummy KLV PES on PID `0x101` |
| `dummy.klv` | Tiny synthetic KLV blob (not real MISB telemetry) |

`ffprobe` on `video_with_klv.ts` should show `h264,video` and `klv,data`.
PID `0x101` must also contain packets (PMT advertisement alone is not enough).

Video source: [Big Buck Bunny](https://peach.blender.org/) (Blender Foundation).
Clip used: test-videos.co.uk Big Buck Bunny 360p 10s (~1 MB).

Rebuild (ffmpeg + Python mux):

```bash
./scripts/create_dummy_ts.sh samples/source.mp4
```

Do not add real camera recordings or real KLV captures here.
