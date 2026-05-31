# 2026-05-31 live transcript E2E proof

`even-codex` now routes the latest paired Codex prompt and reply through the bridge and both Even-facing surfaces.

- added transcript parsing for mounted `~/.codex/sessions/...jsonl` files so the bridge can expose the latest user and assistant turns for the paired session
- added `/session` JSON output plus transcript fields in `/bootstrap`
- updated the bridge-served plugin and the packaged Even Hub app to show the latest prompt and latest reply clearly
- tightened the simulator desktop flow so the VNC environment launches the real Codex CLI binary and can be driven through screenshot-reviewed E2E checks outside the Perl test suite
