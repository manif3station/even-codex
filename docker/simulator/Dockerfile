FROM developer-dashboard:latest

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VITE_EVEN_CODEX_DEFAULT_BRIDGE_ORIGIN=http://127.0.0.1:6789

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libasound2t64 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2t64 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libnss3 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    novnc \
    openbox \
    websockify \
    x11vnc \
    xvfb \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g @evenrealities/evenhub-simulator@0.7.3

WORKDIR /opt/even-codex
COPY . /opt/even-codex

RUN npm install \
 && npm run build:hub \
 && dashboard skills install /opt/even-codex

COPY docker/simulator/entrypoint.sh /usr/local/bin/even-codex-simulator-entrypoint
RUN chmod 0755 /usr/local/bin/even-codex-simulator-entrypoint

EXPOSE 6080 5900 7890 6789 4173 9898

CMD ["even-codex-simulator-entrypoint"]
