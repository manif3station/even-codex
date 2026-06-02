use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

sub read_json_file {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return decode_json($text);
}

my $app = read_json_file('app.json');

is( $app->{name}, 'D2-Codex', 'Even Hub app name matches the target plugin name' );
is( $app->{edition}, '202601', 'Even Hub app edition matches the current documented edition' );
is( $app->{version}, '0.45.0', 'Even Hub app version matches the governed release' );
is( $app->{min_app_version}, '2.0.0', 'Even Hub app declares a minimum app version' );
is( $app->{min_sdk_version}, '0.0.10', 'Even Hub app declares the current SDK floor' );
is( $app->{entrypoint}, 'index.html', 'Even Hub app entrypoint points at the built HTML root' );
is_deeply( $app->{supported_languages}, ['en'], 'Even Hub app declares supported languages' );
like( $app->{package_id}, qr/\A[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+\z/, 'Even Hub app package id matches the documented reverse-domain rule' );
unlike( $app->{name}, qr/even/i, 'Even Hub app name avoids the forbidden Even prefix' );

is( ref $app->{permissions}, 'ARRAY', 'Even Hub app permissions are stored as an array' );
is( scalar @{ $app->{permissions} }, 2, 'Even Hub app now requests microphone and network permissions' );
is( $app->{permissions}[0]{name}, 'g2-microphone', 'Even Hub app requests the glasses microphone permission' );
ok( length( $app->{permissions}[0]{desc} ) >= 1, 'Even Hub microphone permission description is non-empty' );
is( $app->{permissions}[1]{name}, 'network', 'Even Hub app requests network permission' );
ok( length( $app->{permissions}[1]{desc} ) >= 1, 'Even Hub network permission description is non-empty' );
is( ref $app->{permissions}[1]{whitelist}, 'ARRAY', 'Even Hub network permission carries a whitelist array' );
ok( @{ $app->{permissions}[1]{whitelist} } >= 1, 'Even Hub network permission includes at least one whitelisted origin' );
like( $app->{permissions}[1]{whitelist}[0], qr{\Ahttps?://}, 'Even Hub whitelist uses full origins as documented' );

done_testing;
