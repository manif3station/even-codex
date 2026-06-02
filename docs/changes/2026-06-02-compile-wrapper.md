# 2026-06-02 Compile Wrapper

`even-codex 0.34` adds `dashboard even-codex.compile` as the governed wrapper
for packaging `D2-Codex`.

The wrapper solves the operator problem where `evenhub` is not installed
globally on the host `PATH`. It reuses the existing `pack:hub` workflow from
the skill repo, defaults the connector whitelist input to
`https://192.168.1.20:7890/ajax/even-codex`, first reuses the shared
`$HOME/node_modules` toolchain that `dashboard skills install` already stages,
auto-runs `npm ci` only when the required packaging binaries are still
missing, and reports the generated `.ehpk` artifact path.
