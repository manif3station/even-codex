use strict;
use warnings;

use Test::More;

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return $text;
}

my $source = slurp('even-hub/src/main.ts');

like( $source, qr/data-role="refresh-button"/, 'phone UI exposes a refresh control' );
like( $source, qr/data-role="reset-button"/, 'phone UI exposes a reset control' );
like( $source, qr/Connection Checklist/, 'phone UI exposes a setup checklist heading' );
like( $source, qr/Pairing Flow/, 'phone UI explains the pairing flow' );
like( $source, qr/Port 6789/, 'phone UI explains the default bridge port' );
like( $source, qr/refreshBootstrap/, 'source centralizes bridge refresh work' );
like( $source, qr/rebuildPageContainer/, 'source rebuilds the glasses page for richer UI updates' );
like( $source, qr/OsEventTypeList\.CLICK_EVENT/, 'source handles click events for glasses interaction' );
like( $source, qr/textEvent\?->\{?containerID|\btextEvent\b/, 'source reacts to Even text events from glasses containers' );
like( $source, qr/Tap detail to cycle/, 'glasses UI explains how to navigate detail panes' );
like( $source, qr/Tap header to refresh/, 'glasses UI explains how to refresh from glasses' );

my $style = slurp('even-hub/src/style.css');
like( $style, qr/\.panel\b/, 'styles define richer panel sections' );
like( $style, qr/\.metric-grid\b/, 'styles define a metric grid layout' );
like( $style, qr/\.action-row\b/, 'styles define an action row layout' );

done_testing;
