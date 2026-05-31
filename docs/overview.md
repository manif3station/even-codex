# Overview

`even-codex` now ships the first runnable LAN bridge slice and the first real Even Hub package for the larger Even-to-Codex system.

The repository currently contains two working application layers inside the governed skill repo:

- the DD-side connector runtime
- the bundled Even plugin web app
- the packaged Even Hub app source for `D2-Codex`

The connector runtime:

- stores a workspace-to-Codex session pairing
- resolves that pairing from the current `WORKSPACE_REF` or `TICKET_REF`
- starts a local HTTP bridge on `0.0.0.0:6789` by default
- exposes `/health`, `/bootstrap`, and `/plugin/`

The bundled plugin:

- is served directly by the connector
- fetches the connector bootstrap payload from `/bootstrap`
- fetches the live transcript payload from `/session`
- renders the paired workspace ref, Codex session id, host, port, latest prompt, and latest reply for the phone-hosted Even app flow

The packaged Even Hub app:

- lives under `even-hub/` with a Vite and TypeScript build
- uses `@evenrealities/even_hub_sdk`
- creates the startup page on the glasses at launch
- persists the bridge origin through SDK local storage
- exposes a phone-side setup dashboard with connector profile management, session libraries, refresh, and pairing guidance
- auto-refreshes the bridge transcript in the background so glasses and phone stay aligned with the current Codex turn
- renders a three-container glasses layout for header refresh, detail cycling, and footer session switching
- supports tap-to-refresh, tap-to-cycle, and tap-to-switch-session interactions from the glasses page
- handles root double-click exit with `bridge.shutDownPageContainer(1)`
- packages through `evenhub pack` into `dist/d2-codex.ehpk`

The submission layer now also ships with the repo:

- Even Hub listing metadata in `even-hub/listing.json`
- long-text Hub manifest fields in `app.json`
- monochrome icon and background assets in `even-hub/assets/`
- a simulator-driven screenshot capture script for Hub screenshots
- a Dockerized noVNC simulator control CLI for one-command start and stop lifecycle management
- a simulator image that includes the Codex CLI and reuses host Codex auth through `~/.codex`
- a simulator image that resumes the paired session in a visible xterm through the real bundled Codex CLI binary
- a one-command desktop E2E CLI that launches the bridge, app server, and simulator together

The full product specification still matters. The shipped runtime is only the first local bridge slice, and the broader relay-plus-plugin architecture is still described in `SPEC.md` for later tickets.
