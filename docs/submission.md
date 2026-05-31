# Even Hub Submission

## Listing Metadata

`D2-Codex` now keeps its Hub listing material in the repo so the store-style presentation can be reviewed and changed under version control.

Primary listing files:

- `app.json`
- `even-hub/listing.json`
- `even-hub/assets/icon.svg`
- `even-hub/assets/background.svg`
- `even-hub/assets/screenshots/README.md`

## Current Listing Content

- display name: `D2-Codex`
- category: `AI`
- developer name: `Developer Dashboard`
- tagline: `Readable Codex status on Even glasses`
- short description: `Bridge a paired Codex session onto Even glasses over your local network.`

The longer about and information text lives in `even-hub/listing.json`, while the richer manifest fields that the current packer accepts live in `app.json`.

## Screenshot Workflow

Build the app first:

```bash
cd ~/projects/skills/skills/even-codex
npm install
npm run build:hub
```

Then point `evenhub-simulator` at the running app URL or other current target and expose the automation API:

```bash
evenhub-simulator http://127.0.0.1:4173 --automation-port 9898
```

You can also manage that simulator through the shipped bash wrapper:

```bash
EVEN_CODEX_SIMULATOR_URL=http://127.0.0.1:4173 dashboard even-codex.simulator start
dashboard even-codex.simulator stop
```

For the full desktop chain, use the shipped E2E orchestrator:

```bash
dashboard even-codex.e2e start
dashboard even-codex.e2e stop
```

That path starts the local DD bridge, the local Hub app server, and the simulator together so the packaged `D2-Codex` flow can be exercised from one command on a desktop session.

Capture the current screenshots:

```bash
npm run capture:hub-screens
```

This writes:

- `even-hub/assets/screenshots/glasses.png`
- `even-hub/assets/screenshots/webview.png`

In a headless shell session, `evenhub-simulator` may still require an X display to boot. If the simulator prints an X display error, run the capture workflow from a desktop session or under your preferred virtual display wrapper.

## Submission Notes

- The icon and background assets are monochrome or greyscale to match the current review rules.
- The screenshot workflow is simulator-backed because the current Even docs explicitly require screenshots that match real rendering.
- The runtime plugin UX and the listing metadata are separate concerns; both now live in the repo and can be reviewed together.
- The runtime plugin now keeps connector switching on the phone side while allowing session switching on glasses inside the active connector.
- The current glasses runtime is intentionally a single scrolling transcript surface because the current Even input model is strongest when one text container owns capture and native scroll.
- Release screenshots are allowed to be captured automatically, but the rendered-state interpretation must stay outside the Perl `.t` suite and be reviewed by a human or LLM before release.
