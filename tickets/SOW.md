# SOW

## ID

`SOW-015`

## Title

Define and deliver the `even-codex` production bridge in governed phases.

## Goal

Ship a governed `skills/even-codex` repository that starts from a stable production specification and proceeds through phased implementation of the local bridge, protocol contract, session runtime, and installable DD skill behaviors for an Even Realities glasses to Codex TUI bridge.

## Specification Mapping

`SPEC.md` maps into the following delivery workstreams:

1. Protocol foundation
   - event catalog
   - required message fields
   - deployment modes
   - supported Even command set
2. Local bridge foundation
   - runtime state layout
   - session identity
   - pairing and reconnect rules
3. Codex session integration
   - live tmux injection
   - detached fallback
   - transcript streaming and commentary delivery
4. DD install and operator workflows
   - install command
   - configuration storage
   - local audit and recovery tools
5. Relay and plugin integration boundary
   - bridge-facing contract for the external relay and Even plugin
   - LAN-only and public-hosted deployment support

## Initial Delivery Phases

### Phase 1

- specification and protocol foundation

### Phase 2

- local bridge runtime and session pairing foundation

### Phase 3

- live Codex integration and outbound streaming

### Phase 4

- installable DD operator workflow and relay boundary hardening
