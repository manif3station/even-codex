use strict;
use warnings;

use JSON::PP qw(decode_json);
use Test::More;

my $json = qx{
  node --input-type=module <<'EOF'
  import { buildTranscriptRenderLines } from './even-hub/src/transcript-view.js';

  const sourceLines = [
    'Prompt short opening prompt for context',
    'Progress short opening progress for context',
    'Reply short opening reply for context',
    'Prompt latest bottom prompt with enough extra words to force another wrap and test whether the newest reply remains visible on first render',
    'Progress latest bottom progress with enough extra words to force another wrap and prove whether the live transcript follows the real bottom edge during refresh',
    'Reply latest bottom reply with enough extra words to force another wrap and prove whether the real newest line marker stays visible all the way to END-MARKER',
  ];

  const live = buildTranscriptRenderLines(sourceLines, { follow: true, popup: false });
  const review = buildTranscriptRenderLines(sourceLines, { follow: false, popup: false });
  const reviewUpOne = buildTranscriptRenderLines(sourceLines, { follow: false, popup: false, scrollOffset: 1 });

  process.stdout.write(JSON.stringify({ live, review, reviewUpOne }));
EOF
};

is( $?, 0, 'transcript render helper node check exits cleanly' );
my $data = decode_json($json);

ok( scalar @{ $data->{live} } <= 9, 'live-follow output is bounded to the visible wrapped-line budget' );
like( $data->{live}[-1], qr/END-MARKER/, 'live-follow output keeps the newest wrapped line with the end marker visible' );
is( join("\n", @{ $data->{review} }), join("\n", @{ $data->{live} }), 'manual-review without offset keeps the same visible window until the first upward step is applied' );
isnt( join("\n", @{ $data->{reviewUpOne} }), join("\n", @{ $data->{live} }), 'one upward step changes the rendered transcript window' );
ok( scalar @{ $data->{reviewUpOne} } <= scalar @{ $data->{live} }, 'one upward step still stays within the visible window size' );
my $joined_review_up_one = join "\n", @{ $data->{reviewUpOne} };
like( $joined_review_up_one, qr/Progress latest bottom progress|Prompt latest bottom prompt|Reply latest bottom reply/, 'one upward step still renders the same transcript block while shifting the visible wrapped rows' );

done_testing;
