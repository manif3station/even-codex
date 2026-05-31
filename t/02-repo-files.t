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
    'scripts/build-even-hub.mjs',
    'scripts/capture-even-hub-screenshots.mjs',
    'vite.config.ts',
    'docs/overview.md',
    'docs/privacy.md',
    'docs/submission.md',
    'docs/usage.md',
    'docs/changes/2026-05-31-initial-specification.md',
    'docs/changes/2026-05-31-even-hub-package-alignment.md',
    'docs/changes/2026-05-31-even-hub-ux-upgrade.md',
    'docs/changes/2026-05-31-even-hub-listing-assets.md',
    'docs/changes/2026-05-31-even-hub-simulator-cli.md',
    'docs/changes/2026-05-31-docker-novnc-simulator.md',
    'docs/changes/2026-05-31-one-command-desktop-e2e.md',
    'docs/changes/2026-05-31-multi-connector-session-control.md',
    'docs/changes/2026-05-31-runnable-lan-bridge-and-plugin.md',
    'tickets/SOW.md',
    'tickets/EPIC-315.md',
    'tickets/EPIC-322.md',
    'tickets/EPIC-324.md',
    'tickets/EPIC-326.md',
    'tickets/EPIC-327.md',
    'tickets/EPIC-328.md',
    'tickets/EPIC-329.md',
    'tickets/DD-315.md',
    'tickets/DD-322.md',
    'tickets/DD-323.md',
    'tickets/DD-324.md',
    'tickets/DD-325.md',
    'tickets/DD-326.md',
    'tickets/DD-327.md',
    'tickets/DD-328.md',
    'tickets/DD-329.md',
    'tickets/TESTING.md',
    't/12-even-hub-ux.t',
    't/13-even-hub-listing.t',
    't/14-simulator-cli.t',
    't/15-e2e-cli.t',
    't/16-even-hub-multisession.t',
    't/17-simulator-docker.t',
);

for my $path (@paths) {
    ok(-f $path, "$path exists");
}

open my $spec_fh, '<', Even::Codex::Spec::spec_path() or die "Unable to open SPEC.md: $!";
my $spec = do { local $/; <$spec_fh> };
close $spec_fh;

for my $heading (Even::Codex::Spec::required_sections()) {
    like($spec, qr/^## .*?\Q$heading\E/m, "SPEC.md includes $heading section");
}

done_testing;
