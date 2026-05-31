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
