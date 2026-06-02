# 2026-06-02 Native Codex Simulator Bin

## Summary

The Dockerized `even-codex` simulator now launches the packaged native Codex
binary directly inside the xterm session.

## What changed

- changed the simulator image's `EVEN_CODEX_REAL_CODEX_BIN` path from the Node
  launcher wrapper to the packaged native binary under the installed Codex
  package vendor tree
- changed the simulator entrypoint and query launcher defaults to use that
  packaged native path
- documented why the simulator bypasses the wrapper: to avoid the non-root
  startup branch that can try `npm install -g @openai/codex@latest`
