# 2026-06-02 DD same-origin API mode

`even-codex 0.48` retires the old standalone API-mode simulator shell and keeps
the Even Hub client on the DD HTTPS page for both helper and API-key flows.

Changes in this slice:

- the simulator now launches API-key mode on
  `https://<dd-host>:7890/app/even-codex/even-hub?...` instead of a separate
  loopback app shell
- the Even Hub app accepts governed `connector_auth` and
  `connector_api_secret` query overrides for simulator startup
- the Even Hub app reanchors the primary connector to the current DD smart
  route page origin on startup so stale saved simulator profiles cannot keep an
  older standalone connector base
- the release records now treat the DD HTTPS page as the governed browser
  surface for both helper and API-key connector modes
