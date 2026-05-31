# EPIC-332

## Title

Run the Dockerized simulator desktop as the host UID.

## Goal

Stop the `even-codex` simulator container from writing root-owned files back into the host-mounted `~/.codex` tree by creating a runtime user whose UID matches the user who launches `dashboard even-codex.simulator start`.

## Tickets

- `DD-332` Add host-UID user creation and non-root simulator runtime.
- `DD-333` Add an LLM-reviewed screenshot acceptance gate for the simulator E2E flow.

## Status

Done
