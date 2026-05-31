# Even Hub Screenshots

Use the `evenhub-simulator` control plane to regenerate the submission screenshots for `D2-Codex`.

Expected outputs in this folder:

- `glasses.png`
- `webview.png`

Recommended workflow:

1. Build the app with `npm run build:hub`.
2. Launch the simulator against the app URL or QR target and expose `--automation-port 9898`.
3. Run `node scripts/capture-even-hub-screenshots.mjs`.
4. Review the new `glasses.png` and `webview.png` files before submission.

The screenshot images should match what the app actually renders in the simulator and on hardware.
