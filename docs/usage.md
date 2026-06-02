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
npm ci
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

Start the default Dockerized simulator desktop:

```bash
dashboard even-codex.simulator start
```

Stop it:

```bash
dashboard even-codex.simulator stop
```

The default start flow now:

- uses `developer-dashboard:latest` as the base image
- starts a noVNC desktop on `http://127.0.0.1:15700/vnc.html?autoconnect=1&resize=scale`
- installs and runs `even-codex` inside the container
- installs the `codex` CLI inside the container
- mounts `~/.codex` into `/home/dashboard/.codex` so existing Codex auth and config are reused without root-owned writes on the host
- injects the active workspace pairing into the containerized bridge chain
- starts the DD web server, local bridge, Hub app server, and Even simulator without extra host setup
- opens the paired Codex session in a visible xterm window through the packaged native Codex binary instead of the Node launcher wrapper
- exposes the Even simulator automation API on port `19898` so the glasses `up`, `down`, `click`, and `double_click` controls can be driven in governed E2E checks

Useful override environment variables for Docker mode:

- `EVEN_CODEX_SIMULATOR_NOVNC_PORT`
- `EVEN_CODEX_SIMULATOR_VNC_PORT`
- `EVEN_CODEX_SIMULATOR_DASHBOARD_PORT`
- `EVEN_CODEX_SIMULATOR_BRIDGE_HOST_PORT`
- `EVEN_CODEX_SIMULATOR_APP_HOST_PORT`
- `EVEN_CODEX_SIMULATOR_AUTOMATION_HOST_PORT`
- `EVEN_CODEX_DOCKER_BIN`
- `EVEN_CODEX_SIMULATOR_COMPOSE_FILE`
- `EVEN_CODEX_SIMULATOR_ENV_FILE`

Docker mode proven outputs:

- `dashboard even-codex.simulator start` returns JSON with `mode`, `novnc_url`, `novnc_port`, `workspace_ref`, and `codex_session_id`
- repeating `dashboard even-codex.simulator start` while the compose state exists returns `already-running`
- `dashboard even-codex.simulator stop` tears the compose stack down and removes the generated env file
- the live noVNC desktop can show a real Codex turn in the xterm window and the same prompt or reply on the Even plugin and glasses surfaces

## Live Visual Release Gate

The screenshot acceptance gate stays outside the Perl `.t` suite.

Use the running noVNC desktop to capture fresh release evidence:

```bash
docker exec even-codex-simulator-simulator-1 bash -lc 'DISPLAY=:1 scrot /tmp/even-codex-release-gate.png'
docker cp even-codex-simulator-simulator-1:/tmp/even-codex-release-gate.png /tmp/even-codex-release-gate.png
```

Review the screenshot manually or with an LLM image check. The release gate is only satisfied when the image clearly shows:

- the Codex xterm with `hi` and `Hi`
- the phone-side Even plugin with `Latest Prompt hi` and `Latest Reply Hi`
- the glasses view with `Prompt hi` and `Reply Hi`
- the normalized staged query flow, including `/ship status` in the phone-side plugin composer

For tickets that change the live query loop, extend the same review with:

- a real query submitted from the plugin or glasses input flow
- the same query visible in the Codex TUI
- assistant progress text visible on the glasses while the answer is forming
- the glasses view showing transcript by default, the staged input view only after `click`, action changes after `up` or `down`, and transcript restore after `double_click`
- for glasses-interaction tickets, visible simulator button proof that the on-screen `Click`, `Up`, `Down`, and `Double click` controls change the glasses UI exactly as expected

This interpretation rule is reusable and permanent for this skill. The image or
framebuffer capture may be scripted, but the visual judgement must remain a
fresh human or LLM review outside the Perl `.t` suite.

If you want the older host-local process mode instead of Docker, force it explicitly:

```bash
EVEN_CODEX_SIMULATOR_MODE=local dashboard even-codex.simulator start
```

Local-mode override environment variables:

- `EVEN_CODEX_SIMULATOR_BIN`
- `EVEN_CODEX_SIMULATOR_URL`
- `EVEN_CODEX_SIMULATOR_PORT`
- `EVEN_CODEX_RUNTIME_ROOT`
- `EVEN_CODEX_SIMULATOR_PID_FILE`
- `EVEN_CODEX_SIMULATOR_LOG_FILE`

Default runtime files:

- pid file: `~/.developer-dashboard/state/even-codex/simulator/simulator.pid`
- log file: `~/.developer-dashboard/state/even-codex/simulator/simulator.log`

Local-mode proven outputs:

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
- saved connector profiles for different local DD connector origins
- a per-connector session library with activation and removal controls
- refresh and session-cycle controls
- readable bridge endpoint summaries
- live transcript panels for the latest prompt and latest reply
- background polling that refreshes the latest prompt and reply without a manual page reload
- a staged query composer that turns a leading `Slash` or `slash` into `/`
- explicit `Start Voice` and `Stop Voice` controls that exercise the hybrid voice-input path when speech recognition is available in the companion webview
- explicit `Send`, `Retry`, and `Cancel` controls for the staged query flow

Inside the glasses view, the same build now gives the user:

- one full-screen live transcript window
- a click-open bottom popup prompt box that keeps the transcript visible behind it and defaults to `Send`
- a hybrid voice-query path where the same click can start speech recognition in the companion webview and mirror recognised text into the popup draft
- `up` and `down` action cycling only while that popup is open
- a second glasses click path that applies the selected staged action from that popup, or closes the popup cleanly when no staged draft exists yet
- a double-click path back to the transcript view
- prompt, progress, and reply text in the same scrolling stream

On the glasses page, the current controls are:

- swipe up and swipe down to use native transcript scrolling
- click to open the bottom popup from the transcript, start the hybrid voice-input attempt when available, then click again to apply the selected staged action, close an empty standby popup, or dismiss `Cancel`
- no native hold-to-dictate popup, because the current Even SDK docs do not document one; the shipped voice path stays hybrid and depends on the companion webview speech-recognition support

## Full End-To-End Operator Flow

The release README now includes a dedicated `End-to-End Flow` section that
walks the operator through the full lifecycle:

1. start the local bridge or simulator flow on the laptop
2. pair the workspace to a Codex session id
3. open `D2-Codex` on the phone plugin
4. let the plugin bootstrap the current session from `/health` and `/bootstrap`
5. watch the glasses transcript surface reflect Codex prompt, progress, and reply
6. single-click on the glasses to open the bottom popup over the transcript
7. let the companion webview fill the staged draft when speech recognition is available
8. single-click again to submit that recognised draft into the paired Codex session
9. watch the updated Codex progress and reply stream back to both the phone plugin and the glasses transcript

When voice recognition does not yield a staged draft, the next click closes the
popup cleanly and records a recovery message instead of leaving the operator on
an empty send state.

## Proven Outputs

- `dashboard even-codex.start add <codex-session-id>` writes the current workspace pairing
- `dashboard even-codex.start` serves JSON from `/health` and `/bootstrap`
- `/plugin/` loads the bundled Even plugin page and renders the paired workspace and session metadata
- `npm run build:hub` writes `dist/index.html` for Even Hub packaging
- `EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npm run pack:hub` writes `dist/d2-codex.ehpk`
- the packaged `D2-Codex` Hub app shows a guided phone-side connector and session dashboard plus a single-container glasses transcript layout
- the hybrid voice-query browser proof shows `glasses click -> recognised draft -> click submit` with `what is 2 plus 3` flowing into the staged query and latest prompt panels
- the popup no longer traps the user in an empty `SEND` error path; a click with no recognised or typed draft now closes back to transcript standby
- the simulator xterm startup path now bypasses the Codex Node launcher wrapper so first-run desktop startup does not fall into a non-root `npm install -g @openai/codex@latest` failure
