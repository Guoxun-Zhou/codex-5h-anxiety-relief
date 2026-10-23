FROM node:24-bookworm-slim
ARG CODEX_VERSION=0.163.0
RUN apt-get update && apt-get install -y --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && mkdir -p /app /data /home/node/.codex \
    && chown node:node /data /home/node/.codex
WORKDIR /app
COPY monitor.py /app/monitor.py
USER node
ENV QUOTA_HELLO_DATA=/data
ENTRYPOINT ["python3", "/app/monitor.py"]
CMD ["watch"]
