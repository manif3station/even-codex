#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=:1
export EVEN_CODEX_HOST=0.0.0.0
export EVEN_CODEX_ADVERTISE_HOST=127.0.0.1
export EVEN_CODEX_PORT=6789
export EVEN_CODEX_E2E_APP_HOST=0.0.0.0
export EVEN_CODEX_E2E_APP_PORT=4173
export EVEN_CODEX_E2E_BUILD_MODE=skip
export EVEN_CODEX_E2E_SIMULATOR_MODE=local
export EVEN_CODEX_SIMULATOR_BIN=evenhub-simulator
export EVEN_CODEX_SIMULATOR_PORT=9898
export HOME="${EVEN_CODEX_RUNTIME_HOME:?}"
export EVEN_CODEX_QUERY_LAUNCHER=/usr/local/bin/even-codex-query-launcher

mkdir -p "${EVEN_CODEX_RUNTIME_ROOT}" /tmp/even-codex-simulator
if [[ -d /opt/even-codex-host-auth/users ]]; then
  mkdir -p "${EVEN_CODEX_RUNTIME_HOME}/.developer-dashboard/config/auth/users"
  cp -R /opt/even-codex-host-auth/users/. "${EVEN_CODEX_RUNTIME_HOME}/.developer-dashboard/config/auth/users/"
fi
if command -v codex >/tmp/even-codex-simulator/codex-wrapper-path.txt 2>/dev/null; then
  :
else
  printf 'missing\n' >/tmp/even-codex-simulator/codex-wrapper-path.txt
fi
printf '%s\n' "${EVEN_CODEX_REAL_CODEX_BIN}" >/tmp/even-codex-simulator/codex-path.txt
"${EVEN_CODEX_REAL_CODEX_BIN}" --version >/tmp/even-codex-simulator/codex-version.txt

cleanup() {
  dashboard stop >/tmp/even-codex-simulator/dashboard-stop.log 2>&1 || true
  if [[ -f "${EVEN_CODEX_RUNTIME_ROOT}/codex-xterm.pid" ]]; then
    codex_pid="$(cat "${EVEN_CODEX_RUNTIME_ROOT}/codex-xterm.pid" || true)"
    kill "${codex_pid:-0}" 2>/dev/null || true
  fi
  kill "${simulator_pid:-0}" "${bridge_pid:-0}" "${codex_pid:-0}" "${dashboard_pid:-0}" "${novnc_pid:-0}" "${vnc_pid:-0}" "${openbox_pid:-0}" "${xvfb_pid:-0}" 2>/dev/null || true
}

trap cleanup EXIT TERM INT

dashboard skills install /opt/even-codex >/tmp/even-codex-simulator/skill-install.log 2>&1

Xvfb :1 -screen 0 1440x900x24 >/tmp/even-codex-simulator/xvfb.log 2>&1 &
xvfb_pid="$!"
sleep 1

openbox >/tmp/even-codex-simulator/openbox.log 2>&1 &
openbox_pid="$!"

x11vnc -display :1 -forever -shared -rfbport 5900 -nopw >/tmp/even-codex-simulator/x11vnc.log 2>&1 &
vnc_pid="$!"

websockify --web=/usr/share/novnc/ 6080 localhost:5900 >/tmp/even-codex-simulator/novnc.log 2>&1 &
novnc_pid="$!"

container_ip="$(hostname -I | awk '{print $1}')"
dashboard serve --host "${container_ip}" --port 7890 --ssl --foreground >/tmp/even-codex-simulator/dashboard-serve.log 2>&1 &
dashboard_pid="$!"

export EVEN_CODEX_SIMULATOR_URL="https://${container_ip}:7890/app/even-codex/even-hub?workspace_ref=${WORKSPACE_REF}"

cert_path="${EVEN_CODEX_RUNTIME_HOME}/.developer-dashboard/certs/server.crt"
while [[ ! -f "${cert_path}" ]]; do
  sleep 1
done
sudo install -m 0644 "${cert_path}" /usr/local/share/ca-certificates/even-codex-dashboard.crt
sudo update-ca-certificates >/tmp/even-codex-simulator/update-ca-certificates.log 2>&1

dashboard even-codex.start add "${EVEN_CODEX_CODEX_SESSION_ID}"
dashboard even-codex.start >/tmp/even-codex-simulator/start.json 2>&1 &
bridge_pid="$!"

workspace_dir="${EVEN_CODEX_WORKSPACE_PATH}"
if [[ ! -d "${workspace_dir}" ]]; then
  workspace_dir="/opt/even-codex"
fi

/usr/local/bin/even-codex-query-launcher "${EVEN_CODEX_CODEX_SESSION_ID}"
codex_pid="$(cat "${EVEN_CODEX_RUNTIME_ROOT}/codex-xterm.pid")"

evenhub-simulator "${EVEN_CODEX_SIMULATOR_URL}" --automation-port "${EVEN_CODEX_SIMULATOR_PORT}" >/tmp/even-codex-simulator/simulator.log 2>&1 &
simulator_pid="$!"

while :; do
  sleep 3600
done
