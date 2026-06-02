#!/usr/bin/env bash
set -euo pipefail

session_id="${1:-}"
prompt="${2-}"

if [[ -z "${session_id}" ]]; then
  echo "session id is required" >&2
  exit 2
fi

workspace_dir="${EVEN_CODEX_WORKSPACE_PATH:-/opt/even-codex}"
if [[ ! -d "${workspace_dir}" ]]; then
  workspace_dir="/opt/even-codex"
fi

codex_bin="${EVEN_CODEX_REAL_CODEX_BIN:-/opt/codex-cli/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex}"
runtime_root="${EVEN_CODEX_RUNTIME_ROOT:-/tmp/even-codex-simulator}"
pid_file="${runtime_root}/codex-xterm.pid"
launch_log="${runtime_root}/codex-launch.log"

mkdir -p "${runtime_root}"
export DISPLAY="${DISPLAY:-:1}"
export HOME="${EVEN_CODEX_RUNTIME_HOME:-/home/dashboard}"

if [[ -f "${pid_file}" ]]; then
  old_pid="$(cat "${pid_file}")"
  if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
    kill "${old_pid}" 2>/dev/null || true
    sleep 1
  fi
fi

cat >"${runtime_root}/run-codex-resume.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
session_id="${1:?}"
workspace_dir="${2:?}"
codex_bin="${3:?}"
prompt="${4-}"

cd "${workspace_dir}"
if [[ -n "${prompt}" ]]; then
  exec "${codex_bin}" resume "${session_id}" "${prompt}" --cd "${workspace_dir}" --no-alt-screen --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust
fi

exec "${codex_bin}" resume "${session_id}" --cd "${workspace_dir}" --no-alt-screen --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust
EOF
chmod 0755 "${runtime_root}/run-codex-resume.sh"

xterm -hold -geometry 160x48+24+24 -T "Codex ${session_id}" \
  -e "${runtime_root}/run-codex-resume.sh" "${session_id}" "${workspace_dir}" "${codex_bin}" "${prompt}" \
  >>"${launch_log}" 2>&1 &

new_pid="$!"
printf '%s\n' "${new_pid}" >"${pid_file}"
disown "${new_pid}" 2>/dev/null || true
