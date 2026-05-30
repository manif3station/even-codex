use strict;
use warnings;

use Test::More;

open my $license_fh, '<', 'LICENSE' or die "Unable to open LICENSE: $!";
my $license = do { local $/; <$license_fh> };
close $license_fh;

like($license, qr/^MIT License/m, 'license is MIT');
like($license, qr/Permission is hereby granted/m, 'license contains MIT grant text');

done_testing;
