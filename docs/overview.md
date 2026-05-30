# Overview

`even-codex` is currently a governed specification-first skill repository.

The purpose of this first ticket is to freeze the production architecture before implementation begins. The repository records the required three-part system:

- the local DD bridge skill
- the reachable relay service
- the Even Hub plugin

This avoids building a false direct-connect design between the phone-hosted Even runtime and a laptop-local DD route.

The specification now also records a supported LAN-only deployment mode. That mode allows the bridge or relay to stay on a private local network, but it still must be reachable from the phone runtime and must not be treated as laptop-local `localhost`.
