# 2026-05-31 staged-query-simulator-input

## What changed

- added a phone-side staged query composer that normalizes a leading `Slash`
  or `slash` into `/`
- added glasses-side `Send`, `Retry`, and `Cancel` action cycling for the
  staged input pane
- accepted simulator click gestures that surface as Even system events so the
  noVNC desktop can drive the glasses interaction path more reliably

## Why

The Dockerized simulator release gate needed a user-friendly input path that
could be proven visually inside the noVNC desktop instead of only by source
inspection.

## Proof

- fresh noVNC screenshots showed `hi -> Hi` on the Codex xterm
- fresh noVNC screenshots showed `Latest Prompt hi` and `Latest Reply Hi` on
  the phone-side plugin plus `Prompt hi` and `Reply Hi` on the glasses view
- fresh noVNC screenshots showed the staged query `/ship status` and the
  glasses-side action selector moving through `Send`, `Retry`, and `Cancel`
