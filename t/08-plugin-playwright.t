use strict;
use warnings FATAL => 'all';

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
my $pid = fork();
die "Unable to fork even-codex Playwright server: $!" if !defined $pid;

if ( $pid == 0 ) {
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => $port,
        advertised_host  => '192.168.1.20',
        workspace_ref    => 'foobar',
        codex_session_id => 'codex-session-88',
    );
    $server->serve( max_requests => 8 );
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
  console.log(JSON.stringify({ title, workspace, session, endpoint }));
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
