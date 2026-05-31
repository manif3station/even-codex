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
    'cli/start',
    'even-hub/index.html',
    'even-hub/src/main.ts',
    'even-hub/src/style.css',
    'even-hub/src/vite-env.d.ts',
    'scripts/build-even-hub.mjs',
    'vite.config.ts',
    'docs/overview.md',
    'docs/usage.md',
    'docs/changes/2026-05-31-initial-specification.md',
    'docs/changes/2026-05-31-runnable-lan-bridge-and-plugin.md',
    'tickets/SOW.md',
    'tickets/EPIC-315.md',
    'tickets/DD-315.md',
    'tickets/TESTING.md',
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
