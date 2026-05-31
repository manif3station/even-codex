# TESTING

## Docker Verification

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/even-codex && rm -rf cover_db /workspace/skills/even-codex/cover_db && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t && cover -report text -select lib/Even/Codex/Spec.pm -select lib/Even/Codex/Protocol.pm -select lib/Even/Codex/State.pm -select lib/Even/Codex/Plugin.pm -select lib/Even/Codex/Server.pm -select lib/Even/Codex/Manager.pm'
```

## Verified Result

- verified on 2026-05-31
- all 10 test files passed
- 177 assertions passed
- selected module statement coverage reached `100.0`
- selected module subroutine coverage reached `100.0`
- selected module branch coverage reached `100.0`
- selected module condition coverage reached `100.0`
- `t/08-plugin-playwright.t` passed and proved the bundled Even plugin page renders paired session data from `/bootstrap`

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
