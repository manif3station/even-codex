# 2026-05-31 Docker noVNC Simulator

`D2-Codex` now ships a containerized simulator desktop behind noVNC.

The new default `dashboard even-codex.simulator start` flow:

- resolves the active workspace pairing from the local skill state
- writes a simulator-specific Docker env file
- builds a skill-local image from `developer-dashboard:latest`
- starts a noVNC desktop on host port `15700`
- starts the DD environment, local bridge, Hub app, and Even simulator inside the container

This turns the simulator flow into a one-command desktop setup that does not require manual local simulator bootstrapping on the host machine.
