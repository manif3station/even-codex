# even-codex

`even-codex` is a Developer Dashboard skill project for a production bridge between Even Realities glasses and a local Codex TUI session.

It solves the gap between a phone-hosted Even plugin and a machine-hosted Codex TUI. The glasses can display and control short Codex interactions, but the Even SDK runs inside the Even mobile app WebView and cannot rely on a laptop-local `localhost` route. This skill defines the production bridge contract that will connect those systems cleanly.

The current repository state is specification-first. It does not yet ship the live bridge implementation. It ships the governed software specification, project-management records, and verification around the specification metadata so future tickets can implement against a stable contract.

The skill will add:

- a local `even-codex` DD bridge skill
- a relay API and WebSocket contract for phone-to-machine connectivity
- a production Even Hub plugin that streams Codex progress to the glasses and sends supported commands back into Codex

What it does right now:

- records the production architecture for the `even-codex` system
- records the supported private local-network deployment mode for the Even plugin bridge
- defines the MVP scope, non-goals, interfaces, security constraints, and rollout phases
- captures the repository and release rules for future implementation tickets

## Installation

Implementation is not installable yet. The intended install shape after implementation is:

```bash
dashboard skills install even-codex
```

Until the runtime exists, this repository should be treated as the governed design source for that future skill.

## CLI Usage

There is no end-user CLI workflow yet. This bootstrap release is documentation-first and does not expose a live `dashboard even-codex.*` command.

## Browser Usage

There is no browser route yet. Browser-facing behavior will arrive in later tickets after the DD bridge and Even plugin runtime are implemented.

## Examples

Normal-case example:

```bash
dashboard skills install even-codex
```

This is the intended future installation flow once the implementation tickets are complete.

Edge-case example:

```bash
cd ~/projects/skills/skills/even-codex
sed -n '1,200p' SPEC.md
```

Use the specification directly when planning implementation, relay deployment, or test coverage for the future runtime.

## Documentation

- [Specification](SPEC.md)
- [Overview](docs/overview.md)

## License

MIT. See [LICENSE](LICENSE).
