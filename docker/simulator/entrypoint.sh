#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=:1
export WORKSPACE_REF="${EVEN_CODEX_WORKSPACE_REF:-simulator}"
export EVEN_CODEX_RUNTIME_ROOT="${EVEN_CODEX_RUNTIME_ROOT:-/root/.developer-dashboard/state/even-codex}"
export EVEN_CODEX_HOST=0.0.0.0
export EVEN_CODEX_ADVERTISE_HOST=127.0.0.1
export EVEN_CODEX_PORT=6789
export EVEN_CODEX_E2E_APP_HOST=0.0.0.0
export EVEN_CODEX_E2E_APP_PORT=4173
export EVEN_CODEX_E2E_BUILD_MODE=skip
export EVEN_CODEX_E2E_SIMULATOR_MODE=local
export EVEN_CODEX_SIMULATOR_BIN=evenhub-simulator
export EVEN_CODEX_SIMULATOR_URL="http://127.0.0.1:4173"
export EVEN_CODEX_SIMULATOR_PORT=9898

mkdir -p "${EVEN_CODEX_RUNTIME_ROOT}" /tmp/even-codex-simulator

cleanup() {
  dashboard even-codex.e2e stop >/tmp/even-codex-simulator/e2e-stop.log 2>&1 || true
  dashboard stop >/tmp/even-codex-simulator/dashboard-stop.log 2>&1 || true
  kill "${dashboard_pid:-0}" "${novnc_pid:-0}" "${vnc_pid:-0}" "${openbox_pid:-0}" "${xvfb_pid:-0}" 2>/dev/null || true
}

trap cleanup EXIT TERM INT

Xvfb :1 -screen 0 1440x900x24 >/tmp/even-codex-simulator/xvfb.log 2>&1 &
xvfb_pid="$!"
sleep 1

openbox >/tmp/even-codex-simulator/openbox.log 2>&1 &
openbox_pid="$!"

x11vnc -display :1 -forever -shared -rfbport 5900 -nopw >/tmp/even-codex-simulator/x11vnc.log 2>&1 &
vnc_pid="$!"

websockify --web=/usr/share/novnc/ 6080 localhost:5900 >/tmp/even-codex-simulator/novnc.log 2>&1 &
novnc_pid="$!"

dashboard serve --host 0.0.0.0 --port 7890 --foreground >/tmp/even-codex-simulator/dashboard-serve.log 2>&1 &
dashboard_pid="$!"

dashboard even-codex.start add "${EVEN_CODEX_CODEX_SESSION_ID}"
dashboard even-codex.e2e start >/tmp/even-codex-simulator/e2e-start.json

while :; do
  sleep 3600
done
