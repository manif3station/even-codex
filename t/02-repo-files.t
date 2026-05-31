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
    'plugin/app.js',
    'plugin/index.html',
    'plugin/manifest.json',
    'plugin/styles.css',
    'cli/start',
    'docs/overview.md',
    'docs/changes/2026-05-31-initial-specification.md',
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
