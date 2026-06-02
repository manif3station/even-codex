use strict;
use warnings;

use Test::More;

use lib 'lib';
use Even::Codex::Spec;

my @paths = (
    '.env',
    'Changes',
    'LICENSE',
    'README.md',
    'SPEC.md',
    'app.json',
    'package.json',
    'plugin/app.js',
    'plugin/index.html',
    'plugin/manifest.json',
    'plugin/styles.css',
    'cli/e2e',
    'cli/start',
    'cli/simulator',
    'even-hub/index.html',
    'even-hub/listing.json',
    'even-hub/assets/icon.svg',
    'even-hub/assets/background.svg',
    'even-hub/assets/screenshots/README.md',
    'even-hub/src/main.ts',
    'even-hub/src/style.css',
    'even-hub/src/vite-env.d.ts',
    'docker-compose.simulator.yml',
    'docker/simulator/.dockerignore',
    'docker/simulator/Dockerfile',
    'docker/simulator/entrypoint.sh',
    'docker/simulator/query-launcher.sh',
    'docker/simulator/runtime.sh',
    'lib/Even/Codex/Sender.pm',
    'lib/Even/Codex/Transcript.pm',
    'scripts/build-even-hub.mjs',
    'scripts/capture-even-hub-screenshots.mjs',
    'vite.config.ts',
    'docs/overview.md',
    'docs/privacy.md',
    'docs/release-rules.md',
    'docs/submission.md',
    'docs/usage.md',
    'docs/changes/2026-05-31-initial-specification.md',
    'docs/changes/2026-05-31-even-hub-package-alignment.md',
    'docs/changes/2026-05-31-even-hub-ux-upgrade.md',
    'docs/changes/2026-05-31-even-hub-listing-assets.md',
    'docs/changes/2026-05-31-even-hub-simulator-cli.md',
    'docs/changes/2026-05-31-docker-novnc-simulator.md',
    'docs/changes/2026-05-31-live-transcript-e2e.md',
    'docs/changes/2026-05-31-host-uid-simulator-user.md',
    'docs/changes/2026-05-31-live-query-loop.md',
    'docs/changes/2026-05-31-one-command-desktop-e2e.md',
    'docs/changes/2026-05-31-multi-connector-session-control.md',
    'docs/changes/2026-05-31-runnable-lan-bridge-and-plugin.md',
    'docs/changes/2026-06-02-readme-e2e-flow.md',
    'docs/changes/2026-06-02-native-codex-simulator-bin.md',
    'docs/changes/2026-06-02-simulator-launcher-gate.md',
    'docs/changes/2026-06-02-plugin-autorefresh-proof.md',
    'tickets/SOW.md',
    'tickets/EPIC-315.md',
    'tickets/EPIC-322.md',
    'tickets/EPIC-324.md',
    'tickets/EPIC-326.md',
    'tickets/EPIC-327.md',
    'tickets/EPIC-328.md',
    'tickets/EPIC-329.md',
    'tickets/EPIC-330.md',
    'tickets/EPIC-331.md',
    'tickets/EPIC-332.md',
    'tickets/DD-315.md',
    'tickets/DD-322.md',
    'tickets/DD-323.md',
    'tickets/DD-324.md',
    'tickets/DD-325.md',
    'tickets/DD-326.md',
    'tickets/DD-327.md',
    'tickets/DD-328.md',
    'tickets/DD-329.md',
    'tickets/DD-330.md',
    'tickets/DD-331.md',
    'tickets/DD-332.md',
    'tickets/DD-333.md',
    'tickets/DD-334.md',
    'tickets/DD-335.md',
    'tickets/DD-343.md',
    'tickets/DD-344.md',
    'tickets/DD-356.md',
    'tickets/DD-357.md',
    'tickets/DD-358.md',
    'tickets/DD-359.md',
    'tickets/EPIC-343.md',
    'tickets/EPIC-334.md',
    'tickets/EPIC-356.md',
    'tickets/EPIC-357.md',
    'tickets/EPIC-358.md',
    'tickets/EPIC-359.md',
    'tickets/TESTING.md',
    't/12-even-hub-ux.t',
    't/13-even-hub-listing.t',
    't/14-simulator-cli.t',
    't/15-e2e-cli.t',
    't/16-even-hub-multisession.t',
    't/17-simulator-docker.t',
    't/18-simulator-codex-container.t',
    't/19-live-transcript.t',
    't/20-sender.t',
    't/22-plugin-autorefresh-playwright.t',
);

for my $path (@paths) {
    ok(-f $path, "$path exists");
}

open my $spec_fh, '<', Even::Codex::Spec::spec_path() or die "Unable to open SPEC.md: $!";
my $spec = do { local $/; <$spec_fh> };
close $spec_fh;

open my $readme_fh, '<', 'README.md' or die "Unable to open README.md: $!";
my $readme = do { local $/; <$readme_fh> };
close $readme_fh;

for my $heading (Even::Codex::Spec::required_sections()) {
    like($spec, qr/^## .*?\Q$heading\E/m, "SPEC.md includes $heading section");
}

like( $readme, qr/^## End-to-End Flow$/m, 'README.md includes the end-to-end flow heading' );
like( $readme, qr/Start the skill on the laptop\./, 'README.md explains the bridge start step' );
like( $readme, qr/Pair the workspace to a Codex session\./, 'README.md explains the pairing step' );
like( $readme, qr/Open `D2-Codex` on the phone plugin\./, 'README.md explains the phone plugin step' );
like( $readme, qr/The glasses receive the transcript view\./, 'README.md explains the glasses transcript step' );
like( $readme, qr/User interaction starts from the glasses click\./, 'README.md explains the popup interaction step' );
like( $readme, qr/The skill submits the query into the paired Codex session\./, 'README.md explains the return path into Codex' );
like( $readme, qr/dashboard even-codex\.simulator start/, 'README.md records the exact simulator launcher command for governed proof' );
like( $readme, qr/installed skill copy has been refreshed/, 'README.md records that the installed skill copy must be refreshed before trusting launcher proof' );

open my $rules_fh, '<', 'docs/release-rules.md' or die "Unable to open docs/release-rules.md: $!";
my $rules = do { local $/; <$rules_fh> };
close $rules_fh;

like( $rules, qr/dashboard even-codex\.simulator start/, 'release rules require the exact simulator launcher path' );
like( $rules, qr/installed skill copy under.*must be current with the repo under\s+test/s, 'release rules require a fresh installed skill copy before trusting launcher proof' );

done_testing;
