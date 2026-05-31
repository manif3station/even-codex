# 2026-05-31 host-UID simulator runtime and visual release gate

The Dockerized `D2-Codex` simulator desktop now runs as the launcher's host UID instead of as `root`.

- the simulator image now reuses an existing image user when the target host UID already exists, and only creates a dedicated user when that UID is missing
- the image now defaults to the host UID and GID directly, so the mounted `~/.codex` tree is no longer written back with root ownership
- the stable simulator home stays at `/home/dashboard`, and the mounted Codex config is reused there regardless of the backing username inside the image
- the release gate now requires a fresh screenshot review outside the Perl `.t` suite so the visible Codex TUI, phone-side plugin, and glasses transcript are checked as rendered output rather than by hard-coded image assertions
