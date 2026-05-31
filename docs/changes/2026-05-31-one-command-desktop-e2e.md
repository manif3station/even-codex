# 2026-05-31 One-Command Desktop E2E

`even-codex` now ships `dashboard even-codex.e2e {start,stop}` for the full local desktop launch path.

The new bash orchestrator starts the governed DD bridge, starts a local Hub app server for `D2-Codex`, and points the Even simulator at that served app URL from one command. It also records pid and log files for the bridge and app server under the skill runtime area so the flow can be stopped cleanly.

The documented desktop path is now:

```bash
cd ~/project/foobar
dashboard workspace foobar
codex
```

After the paired Codex session id is recorded:

```bash
dashboard even-codex.start add <codex-session-id>
dashboard even-codex.e2e start
```

Stop the local chain with:

```bash
dashboard even-codex.e2e stop
```
