#!/usr/bin/env python3
# Copyright (c) 2026 Resul Emre AYGAN
"""RTSP MP2T simulator: MPEG-TS track, realtime via ffmpeg -re -> FIFO -> rtpmp2tpay.

Exposes a single RTSP media with ``rtpmap: MP2T/90000`` (RTP PT=33) so MediaMTX
can pull it and, with ``rtspDemuxMpegts``, demux to elementary tracks for HLS.

:license: MIT
"""

from __future__ import annotations

import argparse
import atexit
import os
import signal
import subprocess
import sys
import tempfile


def _env(*names: str, default: str) -> str:
    """Return the first non-empty environment variable among *names*.

    :param names: Environment variable names to probe, in order.
    :type names: str
    :param default: Fallback when none of *names* is set or non-empty.
    :type default: str
    :returns: First non-empty value, or *default*.
    :rtype: str
    """
    for name in names:
        val = os.environ.get(name)
        if val:
            return val
    return default


def main() -> int:
    """Serve an MPEG-TS file as a single RTSP MP2T track.

    Paces the file with ffmpeg ``-re -map 0`` into a FIFO, then GstRtspServer
    payloads it as ``rtpmp2tpay`` (PT=33). CLI flags fall back to ``SIM_TS_PATH``,
    ``SIM_RTSP_PORT``, and ``SIM_RTSP_MOUNT``.

    :returns: Process exit code (``0`` on success, ``1`` on setup failure).
    :rtype: int
    """
    try:
        sys.stdout.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
        sys.stderr.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
    except Exception:
        pass

    default_ts = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "samples",
        "video_with_klv.ts",
    )
    parser = argparse.ArgumentParser(
        description="RTSP server exposing one MPEG-TS (MP2T) track from a .ts file.",
    )
    parser.add_argument("--ts", default=_env("SIM_TS_PATH", default=default_ts))
    parser.add_argument("--port", default=_env("SIM_RTSP_PORT", default="8555"))
    parser.add_argument("--mount", default=_env("SIM_RTSP_MOUNT", default="/mp2t"))
    args = parser.parse_args()

    ts_path = os.path.abspath(os.path.expanduser(args.ts))
    if not os.path.isfile(ts_path):
        print(f"ERROR: TS file not found: {ts_path}", file=sys.stderr)
        return 1

    mount = args.mount if args.mount.startswith("/") else f"/{args.mount}"

    try:
        import gi

        gi.require_version("Gst", "1.0")
        gi.require_version("GstRtsp", "1.0")
        gi.require_version("GstRtspServer", "1.0")
        from gi.repository import GLib, Gst, GstRtsp, GstRtspServer
    except Exception as exc:  # noqa: BLE001
        print("ERROR: GStreamer / PyGObject not available:", exc, file=sys.stderr)
        return 1

    Gst.init(None)

    fifo_dir = tempfile.mkdtemp(prefix="rtsp-mpegts-")
    fifo_path = os.path.join(fifo_dir, "live.ts")
    os.mkfifo(fifo_path)

    ffmpeg_cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "warning",
        "-re",
        "-stream_loop",
        "-1",
        "-i",
        ts_path,
        "-map",
        "0",
        "-c",
        "copy",
        "-f",
        "mpegts",
        "-y",
        fifo_path,
    ]

    ff_proc: subprocess.Popen | None = None

    def stop_ffmpeg() -> None:
        """Terminate the ffmpeg child if it is running.

        :returns: None
        :rtype: None
        """
        nonlocal ff_proc
        if ff_proc is None:
            return
        try:
            ff_proc.send_signal(signal.SIGTERM)
            ff_proc.wait(timeout=3)
        except Exception:
            try:
                ff_proc.kill()
            except Exception:
                pass
        ff_proc = None

    def start_ffmpeg() -> None:
        """Restart ffmpeg so the FIFO is fed in realtime (``-re``, looped).

        :returns: None
        :rtype: None
        """
        nonlocal ff_proc
        stop_ffmpeg()
        print(f"[ffmpeg] -re loop -> fifo {fifo_path}", flush=True)
        ff_proc = subprocess.Popen(ffmpeg_cmd)

    atexit.register(stop_ffmpeg)

    pipeline = (
        f'( filesrc location="{fifo_path}" ! '
        f"tsparse set-timestamps=true ! "
        f"rtpmp2tpay name=pay0 pt=33 )"
    )

    server = GstRtspServer.RTSPServer.new()
    server.set_service(str(args.port))
    try:
        server.set_address("0.0.0.0")
    except Exception:
        pass

    factory = GstRtspServer.RTSPMediaFactory.new()
    factory.set_launch(pipeline)
    factory.set_shared(True)
    factory.set_latency(200)
    try:
        factory.set_eos_shutdown(False)
    except Exception:
        pass
    try:
        factory.set_stop_on_disconnect(False)
    except Exception:
        pass
    try:
        factory.set_suspend_mode(GstRtsp.RTSPSuspendMode.NONE)
    except Exception:
        pass
    try:
        factory.set_protocols(GstRtsp.RTSPLowerTrans.TCP | GstRtsp.RTSPLowerTrans.UDP)
    except Exception:
        pass

    ffmpeg_started = {"v": False}

    def on_media_configure(_factory, media):
        """Start ffmpeg when the RTSP media is configured or prepared.

        :param _factory: GstRtspServer media factory that emitted the signal.
        :param media: RTSP media instance being configured.
        :returns: None
        :rtype: None
        """
        print(f"[media] configure status={media.get_status()}", flush=True)

        def on_prepared(_media):
            """Start ffmpeg once, on the GStreamer ``prepared`` signal.

            :param _media: RTSP media that reached the prepared state.
            :returns: None
            :rtype: None
            """
            print(f"[media] PREPARED status={_media.get_status()}", flush=True)
            if not ffmpeg_started["v"]:
                ffmpeg_started["v"] = True
                start_ffmpeg()

        try:
            media.connect("prepared", on_prepared)
        except Exception:
            pass

        if not ffmpeg_started["v"]:
            ffmpeg_started["v"] = True
            GLib.timeout_add(200, lambda: (start_ffmpeg(), False)[1])

    factory.connect("media-configure", on_media_configure)
    server.get_mount_points().add_factory(mount, factory)
    server.attach(None)

    def watchdog() -> bool:
        """Restart ffmpeg if it has exited.

        :returns: Always ``True`` so GLib keeps the timeout scheduled.
        :rtype: bool
        """
        nonlocal ff_proc
        if ff_proc is not None and ff_proc.poll() is not None:
            print(f"[ffmpeg] exited code={ff_proc.returncode} - restarting", flush=True)
            start_ffmpeg()
        return True

    GLib.timeout_add_seconds(2, watchdog)

    print("RTSP MP2T sim - ffmpeg -re + FIFO", flush=True)
    print(f"  TS : {ts_path}", flush=True)
    print(f"  URL: rtsp://0.0.0.0:{args.port}{mount}", flush=True)
    print(f"  Pipeline: {pipeline}", flush=True)

    try:
        GLib.MainLoop().run()
    except KeyboardInterrupt:
        print("\nStopped.", flush=True)
    finally:
        stop_ffmpeg()
        try:
            os.remove(fifo_path)
            os.rmdir(fifo_dir)
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
