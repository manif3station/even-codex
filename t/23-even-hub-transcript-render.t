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

  process.stdout.write(JSON.stringify({ live, review }));
EOF
};

is( $?, 0, 'transcript render helper node check exits cleanly' );
my $data = decode_json($json);

ok( scalar @{ $data->{live} } <= 9, 'live-follow output is bounded to the visible wrapped-line budget' );
like( $data->{live}[-1], qr/END-MARKER/, 'live-follow output keeps the newest wrapped line with the end marker visible' );
ok( scalar @{ $data->{review} } > scalar @{ $data->{live} }, 'manual-review output exposes more wrapped history than live-follow output' );
my $joined_review = join "\n", @{ $data->{review} };
like( $joined_review, qr/Prompt short opening prompt/, 'manual-review output retains older transcript content for upward inspection' );

done_testing;
