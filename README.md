# even-codex

`even-codex` is a Developer Dashboard skill project for a production bridge between Even Realities glasses and a local Codex TUI session.

It solves the gap between a phone-hosted Even plugin and a machine-hosted Codex TUI. The glasses can display and control short Codex interactions, but the Even SDK runs inside the Even mobile app WebView and cannot rely on a laptop-local `localhost` route. This skill defines the production bridge contract that will connect those systems cleanly.

The repository now ships the first runnable LAN bridge slice and a real Even Hub package layer in addition to the governed specification. It includes:

- a DD-side connector that pairs a workspace ref to a Codex session id
- a local HTTP bridge that listens on port `6789` by default
- a bundled Even plugin web app served from that same bridge under `/plugin/`
- a packaged Even Hub app for `D2-Codex` under `even-hub/`

The skill will add:

- a local `even-codex` DD bridge skill
- a relay API and WebSocket contract for phone-to-machine connectivity
- relay-backed Codex streaming and command execution beyond the current LAN bootstrap slice

What it does right now:

- records the production architecture for the full `even-codex` system
- records the supported private local-network deployment mode for the Even plugin bridge
- exposes the runtime protocol contract module for event types, command names, and deployment modes
- stores workspace-to-Codex session pairings through `dashboard even-codex.start add <codex-session-id>`
- starts a LAN bridge through `dashboard even-codex.start`
- serves machine-readable `/health`, `/bootstrap`, `/session`, and `/prompt` routes plus the bundled Even plugin web app under `/plugin/`

## Installation

Install the skill into Developer Dashboard:

```bash
dashboard skills install ~/projects/skills/skills/even-codex
```

## CLI Usage

Pair the current workspace ref to the Codex session id you copied from `/status`:

```bash
dashboard even-codex.start add <codex-session-id>
```

Start the LAN bridge:

```bash
dashboard even-codex.start
```

The default listener is:

```text
http://127.0.0.1:6789
```

For phone-side Even use, point the phone app at a LAN-reachable host name or private IP instead of `127.0.0.1`. Override the advertised host when needed:

```bash
EVEN_CODEX_ADVERTISE_HOST=192.168.1.20 dashboard even-codex.start
```

Start or stop the Dockerized Even Hub simulator desktop:

```bash
dashboard even-codex.simulator start
dashboard even-codex.simulator stop
```

Open the running noVNC desktop at:

```bash
http://127.0.0.1:15700/vnc.html?autoconnect=1&resize=scale
```

The default simulator command now builds a skill-local image from `developer-dashboard:latest`, injects the active workspace pairing, and starts the DD environment, Hub app, bridge, Even simulator, and Codex CLI together.

The simulator container mounts `~/.codex` into `/home/dashboard/.codex`, keeps that path owned by the host caller UID, and reuses the existing Codex auth and config without a second login flow.
It resumes the paired session in a visible xterm window through the real bundled Codex CLI binary, not through a wrapper-only stub.

If you want the older host-local process mode instead of the Docker desktop:

```bash
EVEN_CODEX_SIMULATOR_MODE=local dashboard even-codex.simulator start
```

Start or stop the full local desktop E2E chain:

```bash
dashboard even-codex.e2e start
dashboard even-codex.e2e stop
```

That one command path builds the Hub app when needed, starts the DD bridge, starts a local Hub app server, and points the Even simulator at that served app URL.

Inside the Even app, the user can now:

- save and switch between different local DD connectors
- keep a saved session list for each connector
- choose the active Codex session from the phone plugin

Inside the glasses view, the user can:

- switch between saved sessions for the active connector
- refresh the active connector
- scroll a single live transcript window with native Even swipe behavior
- open the staged query input view with a glasses click only when a staged or reusable draft exists
- cycle `Send`, `Retry`, and `Cancel` inside that input view with glasses swipe input
- close the input view and return to transcript with a glasses double-click
- see live assistant progress text while Codex is still answering
- read recent prompt, progress, and reply text without extra glasses-side panes

The glasses view does not switch connectors. Connector changes stay in the phone plugin.

## Browser Usage

The bundled Even plugin web app is served by the same bridge:

```text
http://127.0.0.1:6789/plugin/
```

The plugin reads `/bootstrap` and shows:

- the paired workspace ref
- the paired Codex session id
- the bridge host and port
- the bootstrap endpoint
- the latest paired Codex prompt, progress, and reply from `/session`
- a staged query path that submits back to the paired session through `/prompt`

## Even Hub Packaging

Build the real Even Hub app:

```bash
cd ~/projects/skills/skills/even-codex
npm install
npm run build:hub
```

Package it for the bridge host you actually want to reach from the phone:

```bash
EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npm run pack:hub
```

That produces:

```text
dist/d2-codex.ehpk
```

The packaged app uses the Even Hub SDK, persists the chosen bridge origin through SDK local storage, and creates the startup glasses page as one transcript text container.

The current packaged UX now includes:

- a phone-side connection dashboard with setup checklist, connector profiles, session libraries, and refresh controls
- a glasses-side single transcript window that streams recent prompt, progress, and reply text
- a glasses-side staged query input view that opens only after a glasses click when a staged or reusable draft exists, and defaults to `Send`
- automatic background transcript refresh so the phone-side plugin and glasses view catch up to live Codex turns without a manual reload
- native transcript scrolling by default, with swipe input repurposed to action cycling only while the glasses input view is open
- a phone-side staged query composer that normalizes leading `Slash` or `slash` into `/`
- a live bridge submit path that writes staged queries into the paired Codex TUI session
- a documented SDK limitation note that current Even docs do not describe a hold-to-dictate popup flow

The current submission bundle now also includes:

- governed Even Hub listing metadata in `even-hub/listing.json`
- `tagline`, `description`, and `changelog` fields in `app.json`
- greyscale icon and background assets under `even-hub/assets/`
- a simulator-backed screenshot capture workflow for `glasses.png` and `webview.png`
- a Dockerized noVNC simulator controller for one-command viewing on port `15700`
- the Codex CLI inside that simulator container with host `~/.codex` reuse

## Examples

Normal-case example:

```bash
cd ~/project/foobar
dashboard workspace foobar
codex
```

Inside Codex, ask for a reply and then inspect `/status`. Copy the reported session id and pair it:

```bash
dashboard even-codex.start add <codex-session-id>
dashboard even-codex.simulator start
```

That brings up the Even bridge on port `6789`, serves the Hub app locally, and starts the Dockerized Even simulator desktop by default. After that, the phone plugin can save more connector origins and more session ids without leaving the Even app.
In the Dockerized noVNC desktop, the Codex xterm, the phone-side Even plugin, and the glasses view all reflect the paired session transcript. A live `hi -> Hi` smoke run has been proven end to end through fresh screenshot review of the running simulator desktop.
The same simulator flow now also proves the staged query path: `slash ship status` is normalized to `/ship status` and shown in the phone plugin composer.
The current release extends that to the visible simulator buttons too: a live screenshot-reviewed run proves transcript-by-default, the on-screen `Click` button keeps the transcript visible when nothing is staged, the same `Click` button opens the staged input view only when a real draft exists, `Up` and `Down` change the selected action inside that view, the on-screen `Click` button can send the staged prompt, and `Double click` returns to the transcript.

Edge-case example:

```bash
EVEN_CODEX_HOST=0.0.0.0 EVEN_CODEX_PORT=6790 EVEN_CODEX_ADVERTISE_HOST=192.168.1.20 dashboard even-codex.start
```

Use this when the phone-hosted Even app must connect to a different LAN host or port than the defaults.

## Documentation

- [Specification](SPEC.md)
- [Overview](docs/overview.md)
- [Release Rules](docs/release-rules.md)
- [Submission](docs/submission.md)
- [Usage](docs/usage.md)

## License

MIT. See [LICENSE](LICENSE).
