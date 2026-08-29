# Optional Linux image for the MP2T RTSP simulator only (not MediaMTX).
# Avoids the conda-forge osx-arm64 GstRtspServer typelib gap.
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-gi \
        gir1.2-gstreamer-1.0 \
        gir1.2-gst-rtsp-server-1.0 \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        libgstrtspserver-1.0-0 \
        ffmpeg \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY mpegts_rtsp_server.py /app/mpegts_rtsp_server.py
COPY samples /app/samples

ENV PYTHONUNBUFFERED=1 \
    SIM_TS_PATH=/app/samples/video_with_klv.ts \
    SIM_RTSP_PORT=8555 \
    SIM_RTSP_MOUNT=/mp2t

EXPOSE 8555

CMD ["python3", "/app/mpegts_rtsp_server.py"]
