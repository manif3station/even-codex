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
like( $source, qr/data-role="save-connector-button"/, 'phone UI exposes a connector save control' );
like( $source, qr/Connection Checklist/, 'phone UI exposes a setup checklist heading' );
like( $source, qr/Connector Profiles/, 'phone UI exposes connector management' );
like( $source, qr/Session Library/, 'phone UI exposes saved session management' );
like( $source, qr/Port 6789/, 'phone UI explains the default bridge port' );
like( $source, qr/Latest Prompt/, 'phone UI exposes the latest prompt transcript panel' );
like( $source, qr/Latest Reply/, 'phone UI exposes the latest reply transcript panel' );
like( $source, qr/\/session/, 'source fetches the live transcript route' );
like( $source, qr/refreshBootstrap/, 'source centralizes bridge refresh work' );
like( $source, qr/quiet:\s*true/, 'source uses a quiet background refresh path for live transcript updates' );
like( $source, qr/rebuildPageContainer/, 'source rebuilds the glasses page for richer UI updates' );
like( $source, qr/OsEventTypeList\.CLICK_EVENT/, 'source handles click events for glasses interaction' );
like( $source, qr/textEvent\?->\{?containerID|\btextEvent\b/, 'source reacts to Even text events from glasses containers' );
like( $source, qr/Tap detail to cycle/, 'glasses UI explains how to navigate detail panes' );
like( $source, qr/Refresh and switch from phone/, 'glasses UI explains that refresh and session switching stay on the phone plugin' );

my $style = slurp('even-hub/src/style.css');
like( $style, qr/\.panel\b/, 'styles define richer panel sections' );
like( $style, qr/\.metric-grid\b/, 'styles define a metric grid layout' );
like( $style, qr/\.action-row\b/, 'styles define an action row layout' );
like( $style, qr/\.profile-list\b/, 'styles define connector profile layouts' );

done_testing;
