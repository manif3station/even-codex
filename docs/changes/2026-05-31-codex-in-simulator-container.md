# 2026-05-31 Codex In Simulator Container

The Dockerized `D2-Codex` simulator desktop now includes the Codex CLI itself.

The simulator image now installs `@openai/codex@0.135.0`, and the compose stack mounts the host `~/.codex` directory into `/root/.codex` so the running container can reuse the same Codex auth and config already present on the host machine.

This makes the noVNC desktop closer to a full E2E environment instead of only a DD bridge and Even simulator environment.
