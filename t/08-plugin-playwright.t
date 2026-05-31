use strict;
use warnings FATAL => 'all';

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use Test::More;
use Time::HiRes qw(sleep);

use lib 'lib';
use Even::Codex::Server;

my $node_bin = _find_command('node');
my $chromium_bin = $ENV{CHROMIUM_BIN} || _find_command(qw(chromium chromium-browser google-chrome google-chrome-stable));

plan skip_all => 'Playwright browser test requires node, Chromium, and NODE_PATH'
  if !$node_bin || !$chromium_bin || !$ENV{NODE_PATH};

my $port = _reserve_port();
my $tmp = tempdir( CLEANUP => 1 );
my $codex_home = File::Spec->catdir( $tmp, '.codex' );
my $session_dir = File::Spec->catdir( $codex_home, 'sessions', '2026', '05', '31' );
make_path($session_dir);
my $session_path = File::Spec->catfile( $session_dir, 'rollout-2026-05-31T17-00-00-codex-session-88.jsonl' );
open my $session_fh, '>', $session_path or die "Unable to open $session_path: $!";
print {$session_fh} <<'JSONL';
{"timestamp":"2026-05-31T17:00:00.000Z","type":"session_meta","payload":{"id":"codex-session-88","cwd":"/tmp/foobar","title":"hi"}}
{"timestamp":"2026-05-31T17:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"hi"}}
{"timestamp":"2026-05-31T17:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hello from codex"}],"phase":"final_answer"}}
JSONL
close $session_fh or die "Unable to close $session_path: $!";

my $pid = fork();
die "Unable to fork even-codex Playwright server: $!" if !defined $pid;

if ( $pid == 0 ) {
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => $port,
        advertised_host  => '192.168.1.20',
        workspace_ref    => 'foobar',
        codex_session_id => 'codex-session-88',
        env              => {
            HOME                   => $tmp,
            EVEN_CODEX_CODEX_HOME  => $codex_home,
        },
    );
    $server->serve( max_requests => 10 );
    exit 0;
}

eval {
    _wait_for_port($port);
    require File::Temp;
    my ( $fh, $script_path ) = File::Temp::tempfile( 'even-codex-playwright-XXXXXX', SUFFIX => '.js', TMPDIR => 1 );
    print {$fh} <<'JS';
const { chromium } = require('playwright-core');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_BIN,
    headless: true
  });
  const page = await browser.newPage();
  await page.goto(process.env.EVEN_CODEX_URL, { waitUntil: 'networkidle' });
  const title = await page.title();
  const workspace = await page.locator('[data-field="workspace-ref"]').innerText();
  const session = await page.locator('[data-field="codex-session-id"]').innerText();
  const endpoint = await page.locator('[data-field="bootstrap-url"]').innerText();
  const prompt = await page.locator('[data-field="last-user-message"]').innerText();
  const reply = await page.locator('[data-field="last-assistant-message"]').innerText();
  console.log(JSON.stringify({ title, workspace, session, endpoint, prompt, reply }));
  await browser.close();
})().catch((error) => {
  console.error(String(error && error.stack || error));
  process.exit(1);
});
JS
    close $fh or die "Unable to close Playwright script: $!";

    my $output = qx{NODE_PATH="$ENV{NODE_PATH}" CHROMIUM_BIN="$chromium_bin" EVEN_CODEX_URL="http://127.0.0.1:$port/plugin/" "$node_bin" "$script_path" 2>&1};
    my $exit = $? >> 8;
    is( $exit, 0, "Playwright verifies the Even plugin page\n$output" );
    require JSON::PP;
    my $payload = JSON::PP::decode_json($output);
    is( $payload->{title}, 'D2-Codex Bridge', 'Playwright sees the plugin page title' );
    is( $payload->{workspace}, 'foobar', 'Playwright sees the paired workspace ref' );
    is( $payload->{session}, 'codex-session-88', 'Playwright sees the paired Codex session id' );
    like( $payload->{endpoint}, qr{/bootstrap\z}, 'Playwright sees the bootstrap endpoint' );
    is( $payload->{prompt}, 'hi', 'Playwright sees the latest user message' );
    is( $payload->{reply}, 'hello from codex', 'Playwright sees the latest assistant message' );
};
my $error = $@;

kill 'TERM', $pid;
waitpid $pid, 0;

die $error if $error;

done_testing;

sub _wait_for_port {
    my ($port) = @_;
    for ( 1 .. 50 ) {
        my $socket = IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
            Proto    => 'tcp',
        );
        if ($socket) {
            close $socket;
            return 1;
        }
        sleep 0.1;
    }
    die "Timed out waiting for port $port";
}

sub _reserve_port {
    my $socket = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Listen    => 1,
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "Unable to reserve port: $!";
    my $port = $socket->sockport;
    close $socket;
    return $port;
}

sub _find_command {
    for my $candidate (@_) {
        my $path = qx{command -v $candidate 2>/dev/null};
        chomp $path;
        return $path if $path;
    }
    return;
}
