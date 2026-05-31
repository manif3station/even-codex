# 2026-05-31 Even Hub Package Alignment

`even-codex` now includes a real Even Hub package layer for `D2-Codex`.

The change adds:

- a committed `app.json` using the current Even Hub manifest schema
- a Vite and TypeScript app under `even-hub/`
- Even Hub SDK startup page creation and lifecycle handling
- SDK local-storage persistence for the bridge origin
- a documented root double-click exit path through `bridge.shutDownPageContainer(1)`
- a packaging workflow that rewrites the manifest whitelist for the requested LAN origin before running `evenhub pack`

The local bridge-served plugin remains available under `/plugin/`, but the repository now also produces a real `dist/d2-codex.ehpk` package for Even Hub sideloading and submission preparation.
