# TESTING

## Docker Verification

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/even-codex && rm -rf cover_db /workspace/skills/even-codex/cover_db .even-hub-build dist node_modules && npm ci && HARNESS_PERL_SWITCHES=-MDevel::Cover NODE_PATH=/opt/playwright/node_modules:/workspace/skills/even-codex/node_modules prove -lr t && npm run build:hub && EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npm run pack:hub && EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 ./node_modules/.bin/evenhub pack .even-hub-build/app.json dist -o dist/test-listing.ehpk && cover -report text -select lib/Even/Codex/Spec.pm -select lib/Even/Codex/Protocol.pm -select lib/Even/Codex/State.pm -select lib/Even/Codex/Plugin.pm -select lib/Even/Codex/Sender.pm -select lib/Even/Codex/Server.pm -select lib/Even/Codex/Manager.pm -select lib/Even/Codex/Transcript.pm'
```

## Verified Result

- verified on 2026-06-02 for release `0.29`
- all 23 test files passed
- `Files=23, Tests=704`
- selected module statement coverage reached `100.0`
- selected module subroutine coverage reached `100.0`
- selected module branch coverage reached `100.0`
- selected module condition coverage reached `100.0`
- `t/08-plugin-playwright.t` passed and proved the bundled Even plugin page renders paired session data from `/bootstrap`
- `npm run build:hub` produced `dist/index.html`
- `EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npm run pack:hub` produced `dist/d2-codex.ehpk`
- `t/12-even-hub-ux.t` proved the stronger phone-side controls plus glasses bottom-popup `click -> popup`, `down -> action cycle`, and `double-click -> transcript` wiring
- `t/13-even-hub-listing.t` proved the listing metadata, greyscale assets, and screenshot workflow files
- `EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 ./node_modules/.bin/evenhub pack .even-hub-build/app.json dist -o dist/test-listing.ehpk` proved the richer manifest fields still pack
- `t/21-even-hub-voice-playwright.t` now also proves the empty-popup fallback keeps the operator off `Voice UNSUPPORTED`, focuses the phone composer, and closes with a useful phone-mic guidance message
- `t/14-simulator-cli.t` proved the bash simulator controller start and stop lifecycle
- `t/15-e2e-cli.t` proved the one-command desktop E2E launcher starts the bridge, app server, and simulator flow together
- `t/16-even-hub-multisession.t` proved connector profile storage, per-connector session libraries, and glasses-side session switching guidance
- `t/17-simulator-docker.t` proved the default simulator launcher writes a Docker env file, resolves the active pairing, and shells out to skill-local Docker Compose
- `t/18-simulator-codex-container.t` proved the simulator image installs `codex`, mounts host `~/.codex`, and defaults the desktop runtime to the caller uid and gid
- `t/19-live-transcript.t` proved transcript parsing and the `/session` route
- `t/20-sender.t` proved launcher-mode prompt submission, tty fallback, xterm lookup, and default command execution paths
- `t/21-even-hub-voice-playwright.t` proved `glasses click -> recognised voice draft -> click submit` against a Vite-served Even Hub page with a fake bridge and fake speech-recognition engine
- `t/21-even-hub-voice-playwright.t` also proved the empty standby recovery path where a second click closes the popup cleanly instead of surfacing a dead-end send error
- `t/22-plugin-autorefresh-playwright.t` proved the phone-side plugin updates `Latest Prompt`, `Latest Progress`, and `Latest Reply` automatically from live session changes without a manual refresh click
- `t/22-plugin-autorefresh-playwright.t` also proved stale progress text clears when the live session no longer reports progress
- `t/02-repo-files.t` now proves the README keeps the governed end-to-end flow section for the bridge, plugin, glasses transcript, popup interaction, and Codex return path
- `t/18-simulator-codex-container.t` now proves the simulator publishes and launches the packaged native Codex binary path instead of the Node launcher wrapper path
- a real smoke run built the simulator image, started the containerized desktop, confirmed the runtime process was running as uid `1000`, confirmed `/home/dashboard/.codex` was present from the host mount, returned `HTTP 200` from `http://127.0.0.1:15700/`, and proved through fresh screenshot review outside the Perl suite that the noVNC desktop showed:
  - the Codex xterm with `hi` and `Hi`
  - the Even plugin with `Latest Prompt hi` and `Latest Reply Hi`
  - the glasses view staying on one transcript surface with `Prompt hi` and `Reply Hi`
  - the updated glasses control flow with transcript by default, the visible simulator `Click` button opening a bottom popup box while leaving the transcript visible behind it, visible `Up` or `Down` changing the staged action, a second visible `Click` dismissing the popup through `Cancel` or sending the staged prompt into Codex, and visible `Double click` restoring the transcript-only view
- a separate browser screenshot review outside the Perl suite proved the hybrid voice-query slice with:
  - a click-open popup path
  - recognised text `what is 2 plus 3` mirrored into the draft and staged-query panels
  - the same recognised text visible as the latest prompt after the second click send path
  - an empty standby click path that closes back to transcript mode with a clear recovery message
  - the README end-to-end release explanation matches the shipped interaction model the screenshots prove
- a direct runtime proof outside the Perl suite built the simulator image and ran:
  - `EVEN_CODEX_REAL_CODEX_BIN`
  - `test -x "$EVEN_CODEX_REAL_CODEX_BIN"`
  - `"$EVEN_CODEX_REAL_CODEX_BIN" --version`
  which confirmed the simulator now points at `/opt/codex-cli/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex` and executes `codex-cli 0.135.0` without entering the wrapper self-update path
- a follow-up exact-launcher proof outside the Perl suite refreshed the
  installed skill copy, reran `dashboard even-codex.simulator start` for the
  paired `books` workspace, and then confirmed from the live simulator process
  tree that:
  - the visible xterm launch target was the packaged native Codex binary path
  - `/opt/codex-cli/bin/codex` was no longer the xterm launch target
  - the X display was live and screenshot capture succeeded from the restarted
    simulator stack

Coverage summary from the verified run:

```text
lib/Even/Codex/Manager.pm   stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Plugin.pm    stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Protocol.pm  stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Sender.pm    stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Server.pm    stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Spec.pm      stmt 100.0                      sub 100.0
lib/Even/Codex/State.pm     stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Transcript.pm stmt 100.0  bran 100.0  cond 100.0  sub 100.0
Total                       stmt 100.0  bran 100.0  cond 100.0  sub 100.0
```

## Cleanup

- remove `cover_db` with a disposable Docker container if host permissions block normal deletion:

```bash
docker run --rm -v ~/projects/skills/skills/even-codex:/workspace:rw ubuntu bash -lc 'rm -rf /workspace/cover_db'
```
