# 2026-06-02 Exact Simulator Launcher Gate

`even-codex` now records an explicit release rule for simulator-launcher and
Codex-startup tickets.

What changed:

- documented that those tickets must prove the exact
  `dashboard even-codex.simulator start` path against a real paired workspace
- documented that container-only checks and direct `docker run` checks are not
  enough on their own for that slice
- documented that the installed skill copy under
  `~/.developer-dashboard/skills/even-codex` must be current before the
  launcher proof is trusted
- bound that rule into the repo guard test so the release language cannot drift
