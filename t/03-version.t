use strict;
use warnings;

use Test::More;

use lib 'lib';
use Even::Codex::Spec;

open my $env_fh, '<', '.env' or die "Unable to open .env: $!";
my $env = do { local $/; <$env_fh> };
close $env_fh;

like($env, qr/^VERSION=0\.05$/m, '.env stores version 0.05');
is($Even::Codex::Spec::VERSION, '0.05', 'module version matches .env');

done_testing;
