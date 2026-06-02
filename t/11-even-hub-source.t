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

my $package = slurp('package.json');
like( $package, qr/\@evenrealities\/even_hub_sdk/, 'package.json includes the Even Hub SDK dependency' );
like( $package, qr/\@evenrealities\/evenhub-cli/, 'package.json includes the Even Hub CLI dependency' );
like( $package, qr/"build:hub"/, 'package.json exposes a build script for the Even Hub app' );
like( $package, qr/"pack:hub"/, 'package.json exposes a packaging script for the Even Hub app' );
like( $package, qr/"capture:hub-screens"/, 'package.json exposes a screenshot capture script for the Even Hub app' );

my $manifest = slurp('app.json');
like( $manifest, qr/"name"\s*:\s*"g2-microphone"/, 'app.json requests the documented glasses microphone permission for hybrid voice input' );

my $source = slurp('even-hub/src/main.ts');
like( $source, qr/waitForEvenAppBridge/, 'Even Hub source waits for the Even app bridge' );
like( $source, qr/__evenCodexWaitForBridge/, 'Even Hub source supports a bridge override hook for governed runtime proof' );
like( $source, qr/__evenCodexSpeechRecognitionFactory/, 'Even Hub source supports a speech-recognition override hook for governed runtime proof' );
like( $source, qr/createStartUpPageContainer/, 'Even Hub source creates a startup page container' );
like( $source, qr/RebuildPageContainer/, 'Even Hub source rebuilds the glasses layout when the popup overlay changes container structure' );
like( $source, qr/audioControl\(true\)/, 'Even Hub source starts the documented microphone path for hybrid voice capture' );
like( $source, qr/audioControl\(false\)/, 'Even Hub source stops the microphone path when voice capture finishes' );
like( $source, qr/OsEventTypeList\.DOUBLE_CLICK_EVENT/, 'Even Hub source handles glasses double-click events' );
like( $source, qr/eventSource === 1/, 'Even Hub source treats bare simulator glasses-touch events as click-compatible input' );
like( $source, qr/sysEventType === OsEventTypeList\.CLICK_EVENT/, 'Even Hub source handles simulator click gestures that arrive as system events' );
like( $source, qr/isTextContainerClick/, 'Even Hub source recognizes text-container click gestures' );
like( $source, qr/isTextContainerDoubleClick/, 'Even Hub source recognizes text-container double-click gestures' );
like( $source, qr/OsEventTypeList\.FOREGROUND_ENTER_EVENT/, 'Even Hub source handles foreground enter' );
like( $source, qr/OsEventTypeList\.FOREGROUND_EXIT_EVENT/, 'Even Hub source handles foreground exit' );
like( $source, qr/OsEventTypeList\.ABNORMAL_EXIT_EVENT/, 'Even Hub source handles abnormal exit' );
like( $source, qr/OsEventTypeList\.SYSTEM_EXIT_EVENT/, 'Even Hub source handles system exit' );
like( $source, qr/OsEventTypeList\.SCROLL_TOP_EVENT/, 'Even Hub source handles upward glasses navigation events' );
like( $source, qr/OsEventTypeList\.SCROLL_BOTTOM_EVENT/, 'Even Hub source handles downward glasses navigation events' );
like( $source, qr/transcriptLiveFollow/, 'Even Hub source tracks whether the glasses transcript is in live-follow mode' );
like( $source, qr/transcriptScrollOffset/, 'Even Hub source tracks transcript review offset in wrapped lines' );
like( $source, qr/transcriptScrollOffset \+= 1/, 'Even Hub source moves the transcript review upward by one line per upward gesture' );
like( $source, qr/Math\.max\(0, state\.transcriptScrollOffset - 1\)/, 'Even Hub source moves transcript review downward one line at a time' );
like( $source, qr/cycleInputAction/, 'Even Hub source cycles staged actions from glasses swipe input' );
like( $source, qr/selectedInputAction = 'send'/, 'Even Hub source resets the glasses input view to Send by default' );
like( $source, qr/GLASSES_POPUP_CONTAINER_ID/, 'Even Hub source defines a dedicated popup container id' );
like( $source, qr/Prompt Box/, 'Even Hub source renders a named popup prompt box on glasses' );
like( $source, qr/getLocalStorage/, 'Even Hub source remembers setup through SDK local storage' );
like( $source, qr/setLocalStorage/, 'Even Hub source persists setup through SDK local storage' );
like( $source, qr/setInterval/, 'Even Hub source schedules background bridge refreshes' );
like( $source, qr/normalizeDraftQuery/, 'Even Hub source normalizes staged query input' );
like( $source, qr/buildInputText/, 'Even Hub source renders a dedicated glasses input view' );
like( $source, qr/buildTranscriptRenderLines/, 'Even Hub source formats transcript content through a dedicated wrap-and-tail helper' );
like( $source, qr/TextContainerUpgrade/, 'Even Hub source can upgrade transcript and popup content without a full layout rebuild' );
like( $source, qr/startVoiceInput/, 'Even Hub source defines a hybrid voice-input entrypoint' );
like( $source, qr/stopVoiceInput/, 'Even Hub source defines a hybrid voice-input stop path' );
like( $source, qr/glassesLayoutMode/, 'Even Hub source tracks the current glasses layout mode so transcript refreshes do not rebuild unnecessarily' );
like( $source, qr/rebuildPageContainer/, 'Even Hub source rebuilds the page container only for layout transitions such as popup open or close' );
like( $source, qr/GLASSES_TRANSCRIPT_CONTAINER_NAME/, 'Even Hub source uses a dedicated single transcript container' );
like( $source, qr/loadBridge\(\)/, 'Even Hub source supports a bridge loader indirection for governed runtime proof' );
like( $source, qr/speechRecognitionSupported/, 'Even Hub source detects speech-recognition support' );
like( $source, qr/__evenCodexSpeechRecognitionFactory/, 'Even Hub source supports a speech-recognition factory override for runtime proof' );
like( $source, qr/audioControl\(true\)/, 'Even Hub source requests microphone capture when the hybrid voice path starts' );
like( $source, qr/startVoiceInput/, 'Even Hub source implements a dedicated voice-input start path' );
like( $source, qr/Voice \$\{state\.voiceInputState\.toUpperCase\(\)\}/, 'Even Hub source surfaces voice state in the glasses popup copy' );
like( $source, qr/truncateForGlasses/, 'Even Hub source trims voice status text for the glasses popup' );
like( $source, qr/Closed the popup because there is no staged query yet\./, 'Even Hub source closes the popup instead of erroring on an empty standby send' );
like( $source, qr/Voice capture stopped without recognised text\./, 'Even Hub source returns recording clicks to standby when no transcript is available' );

my $style = slurp('even-hub/src/style.css');
unlike( $style, qr/background(?:-color)?\s*:/i, 'Even Hub source styles avoid background fill declarations' );
like( $style, qr/border:/i, 'Even Hub source styles use borders for structure' );
like( $style, qr/\.input-area\b/, 'Even Hub source styles include the staged query textarea layout' );

my $transcript_helper = slurp('even-hub/src/transcript-view.js');
like( $transcript_helper, qr/wrapTranscriptLine/, 'transcript helper exposes line wrapping' );
like( $transcript_helper, qr/buildTranscriptRenderLines/, 'transcript helper exposes transcript render slicing' );
like( $transcript_helper, qr/slice\(-visibleLines\)/, 'transcript helper keeps live-follow output pinned to the newest wrapped lines' );
like( $transcript_helper, qr/scrollOffset/, 'transcript helper supports one-line transcript stepping during manual review' );

done_testing;
