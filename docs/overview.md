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
- renders the paired workspace ref, Codex session id, host, and port for the phone-hosted Even app flow

The packaged Even Hub app:

- lives under `even-hub/` with a Vite and TypeScript build
- uses `@evenrealities/even_hub_sdk`
- creates the startup page on the glasses at launch
- persists the bridge origin through SDK local storage
- handles root double-click exit with `bridge.shutDownPageContainer(1)`
- packages through `evenhub pack` into `dist/d2-codex.ehpk`

The full product specification still matters. The shipped runtime is only the first local bridge slice, and the broader relay-plus-plugin architecture is still described in `SPEC.md` for later tickets.
