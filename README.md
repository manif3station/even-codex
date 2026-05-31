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
- serves machine-readable `/health` and `/bootstrap` routes plus the bundled Even plugin web app under `/plugin/`

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

The packaged app uses the Even Hub SDK, persists the chosen bridge origin through SDK local storage, creates the startup glasses page on launch, and maps root double-click to `bridge.shutDownPageContainer(1)`.

The current packaged UX now includes:

- a phone-side connection dashboard with setup checklist, endpoint summaries, and refresh or reset controls
- a glasses-side three-panel layout with readable status, detail cycling, and tap-to-refresh behavior
- on-glasses prompts that make refresh, detail navigation, and exit behavior obvious

The current submission bundle now also includes:

- governed Even Hub listing metadata in `even-hub/listing.json`
- `tagline`, `description`, and `changelog` fields in `app.json`
- greyscale icon and background assets under `even-hub/assets/`
- a simulator-backed screenshot capture workflow for `glasses.png` and `webview.png`

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
dashboard even-codex.start
```

That brings up the Even bridge on port `6789` by default.

Edge-case example:

```bash
EVEN_CODEX_HOST=0.0.0.0 EVEN_CODEX_PORT=6790 EVEN_CODEX_ADVERTISE_HOST=192.168.1.20 dashboard even-codex.start
```

Use this when the phone-hosted Even app must connect to a different LAN host or port than the defaults.

## Documentation

- [Specification](SPEC.md)
- [Overview](docs/overview.md)
- [Submission](docs/submission.md)
- [Usage](docs/usage.md)

## License

MIT. See [LICENSE](LICENSE).
