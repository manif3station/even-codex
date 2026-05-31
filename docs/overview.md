# Overview

`even-codex` now ships the first runnable LAN bridge slice for the larger Even-to-Codex system.

The repository currently contains two working application layers inside the governed skill repo:

- the DD-side connector runtime
- the bundled Even plugin web app

The connector runtime:

- stores a workspace-to-Codex session pairing
- resolves that pairing from the current `WORKSPACE_REF` or `TICKET_REF`
- starts a local HTTP bridge on `0.0.0.0:6789` by default
- exposes `/health`, `/bootstrap`, and `/plugin/`

The bundled plugin:

- is served directly by the connector
- fetches the connector bootstrap payload from `/bootstrap`
- renders the paired workspace ref, Codex session id, host, and port for the phone-hosted Even app flow

The full product specification still matters. The shipped runtime is only the first local bridge slice, and the broader relay-plus-plugin architecture is still described in `SPEC.md` for later tickets.
