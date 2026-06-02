# EPIC-358

## Title

Require exact simulator launcher proof in the `even-codex` release gate.

## Goal

Make future `even-codex` simulator releases prove the real
`dashboard even-codex.simulator start` launcher path itself, not just repo
source, container internals, or screenshot-only slices.

## Ticket

- `DD-358` Record and guard the exact simulator launcher E2E gate.
