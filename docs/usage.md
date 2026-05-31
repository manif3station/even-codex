# Usage

## Pair A Workspace To Codex

Start in the project you want to pair:

```bash
cd ~/project/foobar
dashboard workspace foobar
codex
```

Inside Codex, run your normal prompt and then inspect `/status`. Copy the session id from the `/status` output.

Pair that session id to the active workspace:

```bash
dashboard even-codex.start add <codex-session-id>
```

## Start The LAN Bridge

Start the bridge:

```bash
dashboard even-codex.start
```

Default listener details:

- bind host: `0.0.0.0`
- port: `6789`
- plugin path: `/plugin/`

Useful endpoints:

- `http://127.0.0.1:6789/health`
- `http://127.0.0.1:6789/bootstrap`
- `http://127.0.0.1:6789/plugin/`

## Build The Even Hub App

Build the packaged `D2-Codex` app from the repo root:

```bash
cd ~/projects/skills/skills/even-codex
npm install
npm run build:hub
```

This produces a real `dist/index.html` entrypoint for the Even Hub package flow.

## Package The Even Hub App

The app whitelist must match the exact LAN origin the phone-side Even app will call. Package with the right host and port:

```bash
EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npm run pack:hub
```

This writes:

```text
dist/d2-codex.ehpk
```

The generated package manifest is also written to:

```text
.even-hub-build/app.json
```

That generated manifest mirrors the committed `app.json` schema but swaps the network whitelist to the requested `EVEN_CODEX_HUB_ORIGIN`.

## Capture Hub Submission Screenshots

After the app is built and the `evenhub-simulator` control plane is running on port `9898`, capture the current listing screenshots with:

```bash
npm run capture:hub-screens
```

The workflow writes:

- `even-hub/assets/screenshots/glasses.png`
- `even-hub/assets/screenshots/webview.png`

## Start Or Stop The Simulator

Start the local simulator controller:

```bash
dashboard even-codex.simulator start
```

Stop it:

```bash
dashboard even-codex.simulator stop
```

Useful override environment variables:

- `EVEN_CODEX_SIMULATOR_BIN`
- `EVEN_CODEX_SIMULATOR_URL`
- `EVEN_CODEX_SIMULATOR_PORT`
- `EVEN_CODEX_RUNTIME_ROOT`
- `EVEN_CODEX_SIMULATOR_PID_FILE`
- `EVEN_CODEX_SIMULATOR_LOG_FILE`

Default runtime files:

- pid file: `~/.developer-dashboard/state/even-codex/simulator/simulator.pid`
- log file: `~/.developer-dashboard/state/even-codex/simulator/simulator.log`

Proven control outputs:

- `dashboard even-codex.simulator start` returns JSON with `status`, `pid`, `pid_file`, `log_file`, `simulator_url`, and `automation_port`
- repeating `dashboard even-codex.simulator start` while the pid is still alive returns `already-running`
- `dashboard even-codex.simulator stop` returns `stopped` and removes the pid file
- repeating `dashboard even-codex.simulator stop` returns `not-running`

## Start Or Stop The Full Desktop E2E Flow

Start the local desktop chain in one command:

```bash
dashboard even-codex.e2e start
```

This orchestration command:

- builds the Hub app if `dist/index.html` is missing
- starts the DD bridge on the configured local bridge port
- starts a local Hub app server on port `4173` by default
- points the Even simulator at that served Hub app URL

Stop the whole chain:

```bash
dashboard even-codex.e2e stop
```

Useful override environment variables:

- `EVEN_CODEX_E2E_BUILD_MODE`
- `EVEN_CODEX_E2E_BUILD_CMD`
- `EVEN_CODEX_E2E_APP_HOST`
- `EVEN_CODEX_E2E_APP_PORT`
- `EVEN_CODEX_E2E_APP_DIR`
- `EVEN_CODEX_E2E_APP_SERVER_CMD`
- `EVEN_CODEX_E2E_BRIDGE_PID_FILE`
- `EVEN_CODEX_E2E_BRIDGE_LOG_FILE`
- `EVEN_CODEX_E2E_APP_PID_FILE`
- `EVEN_CODEX_E2E_APP_LOG_FILE`

Proven control outputs:

- `dashboard even-codex.e2e start` returns JSON with bridge pid, app pid, bridge URLs, and simulator URL
- `dashboard even-codex.e2e stop` returns `stopped` after terminating the tracked bridge and app server processes
- repeating `dashboard even-codex.e2e stop` returns `not-running`

## Phone-Side Even Use

The phone-hosted Even app must not use laptop-local `127.0.0.1` unless it is actually running on that same device. For real phone-to-laptop use, advertise a LAN-reachable host:

```bash
EVEN_CODEX_ADVERTISE_HOST=192.168.1.20 dashboard even-codex.start
```

You can also change the port:

```bash
EVEN_CODEX_PORT=6790 EVEN_CODEX_ADVERTISE_HOST=192.168.1.20 dashboard even-codex.start
```

Inside `D2-Codex`, the phone-side plugin now gives the user:

- a connection status summary
- a setup checklist for the pairing workflow
- refresh, reset, and glasses-detail-cycle controls
- readable bridge endpoint summaries

On the glasses page, the current controls are:

- tap header to refresh the bridge data
- tap detail to cycle between summary, network, and setup-step panes
- double-click to exit through the Even confirmation flow

## Proven Outputs

- `dashboard even-codex.start add <codex-session-id>` writes the current workspace pairing
- `dashboard even-codex.start` serves JSON from `/health` and `/bootstrap`
- `/plugin/` loads the bundled Even plugin page and renders the paired workspace and session metadata
- `npm run build:hub` writes `dist/index.html` for Even Hub packaging
- `EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npm run pack:hub` writes `dist/d2-codex.ehpk`
- the packaged `D2-Codex` Hub app shows a guided phone-side setup dashboard and a multi-container glasses status layout
