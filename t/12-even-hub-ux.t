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
like( $source, qr/Latest Progress/, 'phone UI exposes the latest assistant progress transcript panel' );
like( $source, qr/Query Composer/, 'phone UI exposes a staged query composer section' );
like( $source, qr/data-role="stage-query-button"/, 'phone UI exposes a stage query control' );
like( $source, qr/data-role="send-query-button"/, 'phone UI exposes a send query control' );
like( $source, qr/data-role="retry-query-button"/, 'phone UI exposes a retry query control' );
like( $source, qr/data-role="cancel-query-button"/, 'phone UI exposes a cancel query control' );
like( $source, qr/data-role="load-slash-sample-button"/, 'phone UI exposes a slash-sample helper for simulator proof' );
like( $source, qr/data-role="load-latest-prompt-button"/, 'phone UI exposes a latest-prompt helper for staged input reuse' );
like( $source, qr/starts with <code>Slash<\/code>|normalize/i, 'phone UI explains slash normalization for staged queries' );
like( $source, qr/\/session/, 'source fetches the live transcript route' );
like( $source, qr/\/prompt/, 'source submits staged prompts through the bridge prompt route' );
like( $source, qr/refreshBootstrap/, 'source centralizes bridge refresh work' );
like( $source, qr/buildTranscriptText/, 'source builds a single glasses transcript view' );
like( $source, qr/buildInputText/, 'source builds a staged glasses input view' );
like( $source, qr/quiet:\s*true/, 'source uses a quiet background refresh path for live transcript updates' );
like( $source, qr/textContainerUpgrade/, 'source updates the glasses transcript in place' );
like( $source, qr/OsEventTypeList\.CLICK_EVENT/, 'source handles click events for glasses interaction' );
like( $source, qr/sysEventType === OsEventTypeList\.CLICK_EVENT/, 'source accepts simulator click gestures that surface as system events' );
like( $source, qr/textEvent\?->\{?containerID|\btextEvent\b/, 'source reacts to Even text events from glasses containers' );
like( $source, qr/Up and Down use the native Even transcript scroll path/, 'phone UI explains native glasses transcript scrolling' );
like( $source, qr/Click opens the staged query input view/, 'phone UI explains click-to-input behavior' );
like( $source, qr/Double-click closes the input view and returns to the live transcript/, 'phone UI explains double-click transcript restore behavior' );
like( $source, qr/Hold-to-dictate is not documented by the current Even SDK/, 'phone UI explains the current hold limitation' );
like( $source, qr/Prompt /, 'glasses transcript includes prompt lines' );
like( $source, qr/Reply /, 'glasses transcript includes reply lines' );
like( $source, qr/Progress /, 'glasses transcript includes progress lines' );
like( $source, qr/Input/, 'glasses input view includes an input heading' );
like( $source, qr/Action .*SEND|Action \$\{state\.selectedInputAction\.toUpperCase\(\)\}/, 'glasses input view includes the selected action label' );
like( $source, qr/Up\/down choose action/, 'glasses input view explains swipe action cycling' );
like( $source, qr/Click apply/, 'glasses input view explains click-to-apply' );
like( $source, qr/Double-click close/, 'glasses input view explains double-click close' );

my $style = slurp('even-hub/src/style.css');
like( $style, qr/\.panel\b/, 'styles define richer panel sections' );
like( $style, qr/\.metric-grid\b/, 'styles define a metric grid layout' );
like( $style, qr/\.action-row\b/, 'styles define an action row layout' );
like( $style, qr/\.profile-list\b/, 'styles define connector profile layouts' );
like( $style, qr/\.input-area\b/, 'styles define the staged query input area' );

done_testing;
