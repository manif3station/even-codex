# even-codex Software Specification

## 1. Purpose

`even-codex` is a production Developer Dashboard skill system that connects Even Realities glasses sessions with a local Codex TUI session and keeps both sides synchronized.

The system must let a user:

- receive Codex progress, commentary, and final output on Even glasses
- send supported requests or commands from the Even side back into Codex
- keep the local Codex TUI aware of Even-originated turns
- operate through a production-safe bridge instead of assuming direct phone-to-laptop `localhost` access

## 2. Scope

This specification covers the full `even-codex` product as three coordinated deliverables:

1. `skills/even-codex`
   - the local DD skill and Codex bridge running on the machine that hosts Codex TUI
2. `even-codex-relay`
   - the reachable relay API and WebSocket service that links the phone-hosted Even plugin to the local machine
3. `even-codex-plugin`
   - the Even Hub plugin that runs inside the Even mobile app WebView and drives the glasses UI

## 3. Problem Statement

The Even SDK runtime is not the same as a laptop-local DD runtime:

- the plugin runs inside the Even mobile app WebView
- the glasses act as the display and limited-input surface
- Codex TUI runs locally on the developer machine
- the phone-hosted plugin must satisfy Even networking allowlists and browser CORS rules

Because of that split, a direct `Even plugin -> laptop-local localhost endpoint` design is not production-safe. A relay or bridge layer that is reachable from the phone runtime is required.

## 4. Goals

- provide reliable bidirectional synchronization between Even sessions and Codex TUI
- preserve live Codex progress streaming on the glasses
- support constrained inbound commands from Even without breaking the TUI session model
- tolerate short network interruptions and reconnect cleanly
- capture enough audit information to diagnose delivery and pairing issues
- create a stable contract that future implementation tickets can build and test against

## 5. Non-Goals For The Initial Release

- full arbitrary keyboard input directly from the glasses
- full desktop-equivalent browsing on the glasses
- speaker-driven audio playback from the glasses
- day-one freeform voice workflow without an explicit STT path
- direct dependence on laptop-local `127.0.0.1` or `localhost` routes from the phone-hosted plugin

## 6. Production Architecture

The production topology is:

`Even Glasses <-> Even mobile app plugin <-> relay API/WebSocket <-> local even-codex DD skill <-> Codex TUI`

This relay does not have to be public internet facing. A private LAN-reachable bridge is a supported production deployment shape, as long as the phone-hosted plugin can reach it and the Even networking constraints are satisfied.

### 6.1 Even Glasses

- render short formatted text, progress, menus, and final responses
- emit limited input actions through the plugin runtime

### 6.2 Even Plugin

- runs inside the Even mobile app WebView
- renders the glasses-facing UI using the Even SDK container model
- captures supported touch and lifecycle events
- optionally captures microphone audio in later phases
- connects to the relay over approved network origins

### 6.3 Relay Service

- terminates authenticated client connections from the plugin and the local bridge
- carries events between the phone-side plugin and the local bridge
- tracks session presence, heartbeats, acknowledgements, and reconnect windows
- buffers short-lived undelivered messages for reconnect recovery
- may be deployed on the local network instead of on a public internet host

### 6.4 Local DD Skill

- reuses the `telegram-codex` live-session bridge patterns where applicable
- detects and targets the active Codex TUI session
- injects Even-originated commands into the live TUI when possible
- streams commentary and final output back to the relay
- records local runtime state and audit traces for session recovery

### 6.5 Codex TUI

- remains the primary operator-facing coding environment
- receives injected Even-originated turns as normal Codex work
- continues to show local progress while mirroring that progress outward to the paired Even session

## 7. Functional Requirements

## 7.1 Outbound To Even

The system must:

- stream live commentary updates from Codex to the paired Even session
- stream final answers from Codex to the paired Even session
- show active task state and important lifecycle transitions
- support truncation and pagination rules that respect the glasses display limits

## 7.2 Inbound From Even

The initial production slice must support:

- `Status`
- `Resume`
- `Retry`
- `Stop`
- selection from a saved prompt list
- selection from recent threads or sessions

Later phases may add:

- microphone capture plus speech-to-text
- phone-assisted freeform text entry

## 7.3 Session Pairing

The system must:

- pair one Even session with one active Codex session at a time by default
- expose session identity clearly in logs and runtime state
- prevent cross-session message bleed
- support explicit reconnect to the same active Codex session after short disconnects

## 7.4 Live Injection

When a live tmux-backed Codex TUI session is available, the local bridge must:

- inject the Even-originated action into the active composer
- use the known-good live submission path
- verify that the turn was accepted by the TUI

If a live pane is unavailable, the system must:

- fall back to a controlled detached path
- report that fallback in the audit trail

## 8. Interface Contract

## 8.1 Event Model

The relay contract must support at least these event classes:

- `session.hello`
- `session.pair`
- `session.heartbeat`
- `session.resume`
- `codex.commentary`
- `codex.final`
- `codex.error`
- `even.command`
- `even.prompt`
- `delivery.ack`
- `delivery.retry`

## 8.2 Message Shape

Every event must carry:

- event id
- event type
- session id
- source role
- timestamp
- delivery sequence number
- payload

Optional fields may include:

- parent event id
- reconnect token
- transcript cursor
- message priority

## 8.3 Delivery Rules

- commentary events may be coalesced when the glasses display is saturated
- final-answer events must not be dropped silently
- commands from Even must be acknowledged explicitly
- relay retries must be idempotent at the consumer boundary

## 9. Security Requirements

- authenticate plugin and local bridge connections
- scope tokens to device/session or session pairings
- reject unauthenticated injection into Codex
- keep secrets out of browser-exposed payloads
- record failed auth attempts and suspicious session collisions
- do not trust phone-side clients to enforce authorization alone

## 10. Reliability Requirements

- support reconnect after transient mobile or relay interruption
- keep a short replay buffer for undelivered events
- mark stale sessions and stale pairings automatically
- preserve the final authoritative answer even if commentary streaming is interrupted
- expose health and status signals for relay and local bridge components

## 10.1 Local-Network Deployment Mode

`even-codex` must support a LAN-only deployment mode for users who do not want a public relay.

In this mode:

- the Even mobile app plugin connects to a relay or bridge on a LAN-reachable host or private DNS name
- the relay or bridge may run on the same machine that hosts Codex TUI, as long as the phone can reach that machine over the network
- the target must not be modeled as laptop-local `127.0.0.1` or `localhost` from the phone-hosted plugin perspective
- Even allowlists, browser CORS rules, and any packaged-app HTTPS requirements still apply

Example LAN deployment topology:

`Even Glasses <-> Even mobile app plugin <-> 192.168.x.x or private hostname <-> local even-codex bridge <-> Codex TUI`

This mode is intended for:

- home or office private-network use
- same-Wi-Fi phone-to-laptop workflows
- local-first deployments where the user does not want a public cloud relay

This mode does not remove the need for:

- authenticated sessions
- reconnect handling
- event acknowledgements
- operational logging
- packaged-app network whitelist compliance

## 11. UX Requirements For Even

- optimize for short text and decisive actions
- prioritize current task, latest progress, and final answer
- keep menu depth shallow
- provide a clear connected/disconnected state
- make retry and stop actions easy to reach
- degrade gracefully when output is too long for the display

## 12. Observability

The production system must record:

- session start and end
- pairing actions
- reconnect attempts
- outbound and inbound event counts
- live-injection success and fallback usage
- terminal delivery failures

Observability outputs should include:

- structured logs
- local runtime ledgers in the DD skill
- relay-side operational logs and counters

## 13. Repository Layout

This skill repository currently owns the local DD bridge specification. The full product should ultimately be organized as:

- `skills/even-codex`
- `even-codex-relay`
- `even-codex-plugin`

The local DD skill repository must remain self-contained and must not depend on editing `Developer-Dashboard/`.

## 14. Testing Strategy

Implementation tickets derived from this specification must provide:

- Docker-based tests for the local DD skill
- `100%` coverage for the skill repository
- protocol tests for message shape and reconnect handling
- simulator or headless validation for the Even plugin
- integration tests for relay-to-bridge delivery
- end-to-end tests for live commentary streaming and final-answer delivery
- verification for both public-hosted and LAN-only supported deployment modes where applicable

## 15. Delivery Plan

## 15.1 Phase 1

- finalize specification
- define event contract
- define repository boundaries

## 15.2 Phase 2

- ship relay foundation
- ship local DD bridge foundation
- verify session pairing and outbound status streaming

## 15.3 Phase 3

- ship command-driven Even input
- ship live commentary and final-answer streaming
- verify bidirectional sync against live Codex sessions

## 15.4 Phase 4

- add optional voice path with STT
- harden operations, reconnect, rate limits, and observability

## 16. Acceptance Criteria For The Future Runtime

The implemented `even-codex` system will be considered production-ready only when:

- the Even plugin can connect through the relay to a paired local Codex session
- Codex commentary and final answers reliably appear on the glasses
- supported Even-originated commands reliably reach the paired Codex session
- reconnect and short outage recovery are verified
- security controls and auditability are in place
- release gates pass for each owning repository

## 17. Open Questions

- whether the first freeform-input path should use microphone STT or phone-assisted text entry
- whether the relay is self-hosted by the user or centrally hosted
- whether one user may intentionally pair multiple glasses devices to one Codex identity
- how aggressively commentary should be summarized before display on the glasses
