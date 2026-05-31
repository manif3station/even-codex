# 2026-05-31 Even Hub Simulator CLI

`even-codex` now ships a local simulator control command:

- `dashboard even-codex.simulator start`
- `dashboard even-codex.simulator stop`

The CLI is implemented as a bash entrypoint under `cli/simulator` and manages:

- simulator pid tracking
- simulator log output
- runtime files under the skill state area
- override env vars for the simulator binary, target URL, automation port, and file locations

This removes the need to manually launch and kill `evenhub-simulator` while iterating on `D2-Codex`.
