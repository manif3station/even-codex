FROM developer-dashboard:latest

ARG EVEN_CODEX_RUNTIME_USER=dashboard
ARG EVEN_CODEX_HOST_UID=1000
ARG EVEN_CODEX_HOST_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:1
ENV VITE_EVEN_CODEX_DEFAULT_BRIDGE_ORIGIN=http://127.0.0.1:6789
ENV EVEN_CODEX_REAL_CODEX_BIN=/opt/codex-cli/bin/codex
ENV EVEN_CODEX_RUNTIME_USER=${EVEN_CODEX_RUNTIME_USER}
ENV EVEN_CODEX_RUNTIME_HOME=/home/dashboard

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
    libjavascriptcoregtk-4.1-0 \
    libnss3 \
    libsoup-3.0-0 \
    libwebkit2gtk-4.1-0 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    novnc \
    openbox \
    scrot \
    websockify \
    xdotool \
    xterm \
    x11vnc \
    xvfb \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g @evenrealities/evenhub-simulator@0.7.3 \
 && npm install -g --prefix /opt/codex-cli @openai/codex@0.135.0

WORKDIR /opt/even-codex
COPY . /opt/even-codex

RUN npm install \
 && npm run build:hub \
 && dashboard skills install /opt/even-codex

RUN set -eux; \
    if ! getent group "${EVEN_CODEX_HOST_GID}" >/dev/null; then \
      groupadd --gid "${EVEN_CODEX_HOST_GID}" "${EVEN_CODEX_RUNTIME_USER}"; \
    fi; \
    if ! getent passwd "${EVEN_CODEX_HOST_UID}" >/dev/null; then \
      useradd --uid "${EVEN_CODEX_HOST_UID}" --gid "${EVEN_CODEX_HOST_GID}" --create-home --shell /bin/bash "${EVEN_CODEX_RUNTIME_USER}"; \
    fi; \
    mkdir -p "${EVEN_CODEX_RUNTIME_HOME}"; \
    chown -R "${EVEN_CODEX_HOST_UID}:${EVEN_CODEX_HOST_GID}" "${EVEN_CODEX_RUNTIME_HOME}" /opt/even-codex

COPY docker/simulator/entrypoint.sh /usr/local/bin/even-codex-simulator-entrypoint
COPY docker/simulator/runtime.sh /usr/local/bin/even-codex-simulator-runtime
COPY docker/simulator/query-launcher.sh /usr/local/bin/even-codex-query-launcher
RUN chmod 0755 /usr/local/bin/even-codex-simulator-entrypoint
RUN chmod 0755 /usr/local/bin/even-codex-simulator-runtime
RUN chmod 0755 /usr/local/bin/even-codex-query-launcher

USER ${EVEN_CODEX_HOST_UID}:${EVEN_CODEX_HOST_GID}

EXPOSE 6080 5900 7890 6789 4173 9898

CMD ["even-codex-simulator-entrypoint"]
