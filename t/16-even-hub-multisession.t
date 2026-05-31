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

like( $source, qr/d2_codex\.config/, 'source stores Hub setup in a dedicated config payload' );
like( $source, qr/Connector Profiles/, 'phone UI exposes a connector profiles section' );
like( $source, qr/Session Library/, 'phone UI exposes a session library section' );
like( $source, qr/data-role="save-connector-button"/, 'phone UI exposes a save connector action' );
like( $source, qr/data-role="activate-connector"/, 'phone UI exposes connector activation controls' );
like( $source, qr/data-role="activate-session"/, 'phone UI exposes session activation controls' );
like( $source, qr/mergeBootstrapIntoConnector/, 'source merges bootstrap payloads into the active connector profile' );
like( $source, qr/cycleSession/, 'source supports session cycling for the glasses view' );
like( $source, qr/lastSubmittedQuery/, 'source tracks the latest query submitted from the phone plugin' );
like( $source, qr/selectedInputAction/, 'source tracks staged input actions for the plugin and glasses views' );
like( $source, qr/OsEventTypeList\.CLICK_EVENT/, 'source still reacts to glasses click events' );
like( $source, qr/Action .*SEND|Up\/down action|applyInputAction/s, 'source exposes an actionable staged input flow' );
unlike( $source, qr/Tap footer or header to refresh/, 'old footer or header refresh copy is removed' );

my $style = slurp('even-hub/src/style.css');
like( $style, qr/\.profile-list\b/, 'styles define a connector profile list' );
like( $style, qr/\.session-list\b/, 'styles define a session list layout' );
like( $style, qr/\.button-row\b/, 'styles define stacked button rows for management controls' );

done_testing;
