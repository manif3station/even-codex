# 2026-05-31 - Runnable LAN Bridge And Plugin

`even-codex` now ships its first real runtime slice instead of remaining spec-only.

- added `dashboard even-codex.start add <codex-session-id>` to store a workspace-to-Codex pairing
- added `dashboard even-codex.start` to serve a LAN bridge on port `6789` by default
- added `/health` and `/bootstrap` connector routes
- bundled the first Even plugin web app under `/plugin/`
- added Docker and Playwright verification for the connector and bundled plugin
