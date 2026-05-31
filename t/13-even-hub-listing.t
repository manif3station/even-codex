use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return $text;
}

sub read_json_file {
    my ($path) = @_;
    return decode_json( slurp($path) );
}

my $app = read_json_file('app.json');
ok( length( $app->{tagline} || q{} ) >= 1, 'app.json carries a listing tagline' );
ok( length( $app->{description} || q{} ) >= 1, 'app.json carries a listing description' );
ok( length( $app->{changelog} || q{} ) >= 1, 'app.json carries a non-empty changelog for new submissions' );

my $listing = read_json_file('even-hub/listing.json');
is( $listing->{developer_name}, 'Developer Dashboard', 'listing metadata records the developer name' );
is( $listing->{category}, 'AI', 'listing metadata records the app category' );
ok( length( $listing->{about} || q{} ) >= 1, 'listing metadata records about text' );
ok( length( $listing->{contact_email} || q{} ) >= 1, 'listing metadata records a contact email' );
is_deeply( $listing->{languages}, ['English'], 'listing metadata records the supported listing languages' );

my $icon = slurp('even-hub/assets/icon.svg');
like( $icon, qr/<svg\b/, 'icon asset is present as svg' );
unlike( $icon, qr/(?:#ff0000|#00ff00|#0000ff|rgb\()/i, 'icon avoids arbitrary full-color gradients' );

my $background = slurp('even-hub/assets/background.svg');
like( $background, qr/<svg\b/, 'background asset is present as svg' );
unlike( $background, qr/(?:#ff|#0f0|#00f|rgb\()/i, 'background asset stays monochrome or greyscale' );

my $capture = slurp('scripts/capture-even-hub-screenshots.mjs');
like( $capture, qr/evenhub-simulator/, 'capture workflow references the Even Hub simulator' );
like( $capture, qr/automation-port/, 'capture workflow documents the simulator automation port' );
like( $capture, qr/\/api\/screenshot\/glasses/, 'capture workflow captures glasses screenshots' );
like( $capture, qr/\/api\/screenshot\/webview/, 'capture workflow captures webview screenshots' );

my $screens = slurp('even-hub/assets/screenshots/README.md');
like( $screens, qr/evenhub-simulator/, 'screenshots README explains simulator-driven capture' );
like( $screens, qr/glasses\.png/, 'screenshots README documents the expected glasses output file' );

done_testing;
