# 2026-05-31 Local-Network Deployment Mode

This specification update adds an explicit local-network deployment mode to `even-codex`.

It records that:

- the bridge or relay does not need to be public internet facing
- the phone-hosted Even plugin may target a LAN-reachable host or private DNS name
- laptop-local `localhost` remains an invalid assumption for the phone runtime
- whitelist, CORS, and packaged-app HTTPS constraints still apply
