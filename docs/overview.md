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
- exposes `/health`, `/bootstrap`, `/session`, `/prompt`, and `/plugin/`

The bundled plugin:

- is served directly by the connector
- fetches the connector bootstrap payload from `/bootstrap`
- fetches the live transcript payload from `/session`
- submits staged prompts through `/prompt`
- renders the paired workspace ref, Codex session id, host, port, latest prompt, latest progress text, and latest reply for the phone-hosted Even app flow

The packaged Even Hub app:

- lives under `even-hub/` with a Vite and TypeScript build
- uses `@evenrealities/even_hub_sdk`
- creates the startup page on the glasses at launch
- persists the bridge origin through SDK local storage
- exposes a phone-side setup dashboard with connector profile management, session libraries, refresh, and pairing guidance
- auto-refreshes the bridge transcript in the background so glasses and phone stay aligned with the current Codex turn
- keeps the glasses transcript on the newest bottom lines by default instead of bouncing back to the top during background refresh
- tails wrapped transcript rows so the newest physical glasses lines stay visible even when one message spans multiple rows
- pauses live-follow when the operator scrolls up to inspect older transcript lines and resumes it only after they return to the bottom
- renders the glasses view as a transcript region plus a bottom popup prompt box when click input is active
- keeps the transcript as the default glasses surface
- opens a bottom popup prompt box after an explicit glasses click while leaving the transcript visible behind it
- starts a hybrid voice-query attempt from that click when the companion webview exposes speech recognition
- mirrors recognised speech back into the popup draft and the phone-side composer
- scopes glasses `up` and `down` gestures to action cycling only while that popup is open
- closes an empty standby popup on click instead of surfacing a dead-end send error
- uses glasses double-click to close the popup and return to the transcript
- keeps staged query composition and `Send`, `Retry`, and `Cancel` controls on the phone side, now with explicit `Start Voice` and `Stop Voice` controls too
- shows assistant progress text during live Codex work in the same transcript stream as prompt and reply text
- records that the current Even docs do not document a native hold-to-dictate popup flow, so the shipped voice-input path is a hybrid glasses-plus-webview implementation
- packages through `evenhub pack` into `dist/d2-codex.ehpk`

The submission layer now also ships with the repo:

- Even Hub listing metadata in `even-hub/listing.json`
- long-text Hub manifest fields in `app.json`
- monochrome icon and background assets in `even-hub/assets/`
- a simulator-driven screenshot capture script for Hub screenshots
- a Dockerized noVNC simulator control CLI for one-command start and stop lifecycle management
- a simulator image that includes the Codex CLI and reuses host Codex auth through `~/.codex`
- a simulator image that resumes the paired session in a visible xterm through the packaged native Codex binary so the desktop runtime bypasses the Node launcher self-update branch
- a host-UID default runtime model for the simulator container so mounted Codex auth is not rewritten by `root`
- a one-command desktop E2E CLI that launches the bridge, app server, and simulator together
- a skill-local release rule that keeps simulator screenshot interpretation outside the Perl `.t` suite and requires fresh human or LLM review
- a release rule that requires the visible simulator control buttons to be verified on screen for tickets that change glasses interactions, instead of relying only on HTTP automation

The full product specification still matters. The shipped runtime is only the first local bridge slice, and the broader relay-plus-plugin architecture is still described in `SPEC.md` for later tickets.
