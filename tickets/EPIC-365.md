# EPIC-365

## Title

Align `even-codex` to the DD HTTPS connector and machine-auth model.

## Goal

Update `even-codex` so the Even plugin and glasses flow use the current
Developer Dashboard connector contract over HTTPS, with both supported DD auth
modes:

- helper-session browser auth on the DD-served plugin page
- route-scoped machine auth on the same saved `/ajax/even-codex/...` handlers
  through `X-DD-API-Key` and `X-DD-API-Secret`

The target runtime shape for `EVEN-CODEX-GOAL` is:

`codex <-> DD ajax/routes connector <-> Even Plugin <-> glasses ui`

with the DD connector acting as the shared middle layer for:

- transcript and progress reads from Codex to glasses
- prompt submission from the Even plugin or glasses back to Codex

## Tickets

- `DD-365` Add runtime-scoped DD machine-auth support for the governed ajax routes.
- `DD-366` Rework the Even plugin connector flow around DD helper auth and
  DD API-key auth.
- `DD-367` Prove the HTTPS DD connector modes in the simulator release gate.

## Status

complete
