FROM mwader/static-ffmpeg:7.1 AS ffmpeg

FROM docker.n8n.io/n8nio/n8n
USER root
COPY --from=ffmpeg /ffprobe /usr/local/bin/
COPY --from=ffmpeg /ffmpeg /usr/local/bin/
USER node
