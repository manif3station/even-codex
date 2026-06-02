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
like( $source, qr/Connector Auth/, 'phone UI exposes the active connector auth summary' );
like( $source, qr/Auth Mode/, 'phone UI exposes the connector auth-mode selector' );
like( $source, qr/API Key/, 'phone UI exposes the fixed DD API key label' );
like( $source, qr/even-codex-connector/, 'phone UI shows the fixed DD API key name' );
like( $source, qr/API Secret/, 'phone UI exposes the DD API secret field' );
like( $source, qr/X-DD-API-Key/, 'phone UI explains the DD API key header path' );
like( $source, qr/X-DD-API-Secret/, 'phone UI explains the DD API secret header path' );
like( $source, qr/DEFAULT_CONNECTOR_API_SECRET/, 'phone UI source carries the default DD API secret constant through the fixed-key connector flow' );
like( $source, qr/Helper Session/, 'phone UI exposes the helper-session connector mode' );
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
like( $source, qr/data-role="start-voice-query-button"/, 'phone UI exposes a voice-start control' );
like( $source, qr/data-role="stop-voice-query-button"/, 'phone UI exposes a voice-stop control' );
like( $source, qr/starts with <code>Slash<\/code>|normalize/i, 'phone UI explains slash normalization for staged queries' );
like( $source, qr/\/session/, 'source fetches the live transcript route' );
like(
    $source,
    qr/fetch\(connector\.promptUrl,\s*\{/,
    'source submits staged prompts through the active connector prompt URL',
);
like( $source, qr/refreshBootstrap/, 'source centralizes bridge refresh work' );
like( $source, qr/buildTranscriptText/, 'source builds the glasses transcript view' );
like( $source, qr/buildInputText/, 'source builds a staged glasses popup view' );
like( $source, qr/buildTranscriptLines/, 'source builds transcript lines before applying live-follow slicing' );
like( $source, qr/quiet:\s*true/, 'source uses a quiet background refresh path for live transcript updates' );
like( $source, qr/textContainerUpgrade/, 'source upgrades transcript content without recreating the full page layout' );
like( $source, qr/rebuildPageContainer/, 'source still rebuilds the glasses layout for popup overlay transitions' );
like( $source, qr/OsEventTypeList\.CLICK_EVENT/, 'source handles click events for glasses interaction' );
like( $source, qr/sysEventType === OsEventTypeList\.CLICK_EVENT/, 'source accepts simulator click gestures that surface as system events' );
like( $source, qr/textEvent\?->\{?containerID|\btextEvent\b/, 'source reacts to Even text events from glasses containers' );
like( $source, qr/Up and Down use the native Even transcript scroll path/, 'phone UI explains native glasses transcript scrolling' );
like( $source, qr/live bottom line|live-follow/i, 'phone UI source explains the live-follow transcript behavior' );
like( $source, qr/Click opens the staged query popup over the transcript and starts a companion voice-input attempt/, 'phone UI explains click-to-popup voice behavior' );
like( $source, qr/Recognised speech is mirrored into the popup draft/, 'phone UI explains that recognised speech flows back into the popup draft' );
like( $source, qr/Double-click closes the popup and returns to the live transcript/, 'phone UI explains double-click popup restore behavior' );
like( $source, qr/hybrid glasses-plus-webview implementation/, 'phone UI explains the hybrid voice-input limitation clearly' );
like( $source, qr/DD helper login.*browser session.*API-key mode always uses the fixed DD API key/s, 'phone UI explains the governed helper and fixed-key API auth setups clearly' );
like( $source, qr/Click again to close or speak again/, 'source surfaces a standby-close recovery message for empty voice captures' );
like( $source, qr/Popup closed with no staged query/, 'source surfaces the close-on-empty-popup behavior clearly' );
like( $source, qr/Prompt /, 'glasses transcript includes prompt lines' );
like( $source, qr/Reply /, 'glasses transcript includes reply lines' );
like( $source, qr/Progress /, 'glasses transcript includes progress lines' );
like( $source, qr/Prompt Box/, 'glasses popup view includes a prompt-box heading' );
like( $source, qr/Voice \$\{state\.voiceInputState\.toUpperCase\(\)\}/, 'glasses popup view includes the current voice state' );
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
