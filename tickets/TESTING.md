# TESTING

## Docker Verification

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/even-codex && rm -rf cover_db /workspace/skills/even-codex/cover_db .even-hub-build dist node_modules package-lock.json && npm install && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t && npm run build:hub && EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npm run pack:hub && EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npx evenhub pack .even-hub-build/app.json dist -o dist/test-listing.ehpk && cover -report text -select lib/Even/Codex/Spec.pm -select lib/Even/Codex/Protocol.pm -select lib/Even/Codex/State.pm -select lib/Even/Codex/Plugin.pm -select lib/Even/Codex/Server.pm -select lib/Even/Codex/Manager.pm'
```

## Verified Result

- verified on 2026-05-31
- all 17 test files passed
- 347 assertions passed
- selected module statement coverage reached `100.0`
- selected module subroutine coverage reached `100.0`
- selected module branch coverage reached `100.0`
- selected module condition coverage reached `100.0`
- `t/08-plugin-playwright.t` passed and proved the bundled Even plugin page renders paired session data from `/bootstrap`
- `npm run build:hub` produced `dist/index.html`
- `EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npm run pack:hub` produced `dist/d2-codex.ehpk`
- `t/12-even-hub-ux.t` proved the stronger phone-side controls and multi-container glasses UX wiring
- `t/13-even-hub-listing.t` proved the listing metadata, greyscale assets, and screenshot workflow files
- `EVEN_CODEX_HUB_ORIGIN=http://192.168.1.20:6789 npx evenhub pack .even-hub-build/app.json dist -o dist/test-listing.ehpk` proved the richer manifest fields still pack
- `t/14-simulator-cli.t` proved the bash simulator controller start and stop lifecycle
- `t/15-e2e-cli.t` proved the one-command desktop E2E launcher starts the bridge, app server, and simulator flow together
- `t/16-even-hub-multisession.t` proved connector profile storage, per-connector session libraries, and glasses-side session switching guidance

Coverage summary from the verified run:

```text
lib/Even/Codex/Manager.pm   stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Plugin.pm    stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Protocol.pm  stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Server.pm    stmt 100.0  bran 100.0  cond 100.0  sub 100.0
lib/Even/Codex/Spec.pm      stmt 100.0                      sub 100.0
lib/Even/Codex/State.pm     stmt 100.0  bran 100.0  cond 100.0  sub 100.0
Total                       stmt 100.0  bran 100.0  cond 100.0  sub 100.0
```

## Cleanup

- remove `cover_db` with a disposable Docker container if host permissions block normal deletion:

```bash
docker run --rm -v ~/projects/skills/skills/even-codex:/workspace:rw ubuntu bash -lc 'rm -rf /workspace/cover_db'
```
