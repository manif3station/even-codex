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
