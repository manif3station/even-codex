use strict;
use warnings FATAL => 'all';

use File::Temp qw(tempfile);
use IO::Socket::INET;
use JSON::PP qw(decode_json);
use Test::More;
use Time::HiRes qw(sleep);

my $node_bin = _find_command('node');
my $chromium_bin = $ENV{CHROMIUM_BIN} || _find_command(qw(chromium chromium-browser google-chrome google-chrome-stable));
my $vite_bin = -x './node_modules/.bin/vite' ? './node_modules/.bin/vite' : undef;

plan skip_all => 'Playwright plugin auto-refresh test requires node, Chromium, NODE_PATH, and vite dependencies'
  if !$node_bin || !$chromium_bin || !$ENV{NODE_PATH} || !$vite_bin;

my $port = _reserve_port();
my $pid = fork();
die "Unable to fork vite dev server: $!" if !defined $pid;

if ( $pid == 0 ) {
    exec $vite_bin, '--host', '127.0.0.1', '--port', $port, '--strictPort';
    die "Unable to exec vite: $!";
}

eval {
    _wait_for_http($port);

    my ( $fh, $script_path ) = tempfile( 'even-codex-autorefresh-XXXXXX', SUFFIX => '.js', TMPDIR => 1 );
    print {$fh} <<'JS';
const { chromium } = require('playwright-core');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_BIN,
    headless: true,
  });
  const page = await browser.newPage();
  await page.addInitScript(() => {
    const originalSetInterval = window.setInterval.bind(window);
    window.setInterval = (handler, timeout, ...args) => {
      const shortened = typeof timeout === 'number' ? Math.min(timeout, 200) : 200;
      return originalSetInterval(handler, shortened, ...args);
    };

    const runtime = {
      bridgeStorage: new Map(),
      eventHandler: null,
      session: {
        prompt: 'hi',
        progress: 'Waiting for Codex response...',
        reply: '',
      },
    };

    window.__evenCodexRuntime = runtime;
    window.__setEvenCodexSession = (session) => {
      runtime.session = {
        ...runtime.session,
        ...session,
      };
    };

    window.__evenCodexWaitForBridge = async () => ({
      async createStartUpPageContainer() { return 0; },
      async rebuildPageContainer(payload) { runtime.lastRebuild = payload; return 0; },
      async textContainerUpgrade(payload) { runtime.lastTextUpgrade = payload; return 0; },
      onEvenHubEvent(callback) { runtime.eventHandler = callback; return () => {}; },
      async getLocalStorage(key) { return runtime.bridgeStorage.get(key) || null; },
      async setLocalStorage(key, value) { runtime.bridgeStorage.set(key, value); },
      async audioControl() { return true; },
    });

    const originalFetch = window.fetch.bind(window);
    window.fetch = async (input, init) => {
      const url = String(input);
      if (/\/health$/.test(url)) {
        return new Response(JSON.stringify({
          ok: true,
          service: 'even-codex',
          workspace_ref: 'foobar',
          codex_session_id: 'codex-session-refresh',
          port: 6789,
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/bootstrap$/.test(url)) {
        return new Response(JSON.stringify({
          workspace_ref: 'foobar',
          codex_session_id: 'codex-session-refresh',
          bind_host: '0.0.0.0',
          advertised_host: '192.168.1.20',
          port: 6789,
          health_url: 'http://192.168.1.20:6789/health',
          bootstrap_url: 'http://192.168.1.20:6789/bootstrap',
          plugin_url: 'http://192.168.1.20:6789/plugin/',
          prompt_url: 'http://192.168.1.20:6789/prompt',
          last_assistant_progress_message: runtime.session.progress,
          recent_turns: runtime.session.reply ? [{
            prompt: runtime.session.prompt,
            progress: runtime.session.progress,
            reply: runtime.session.reply,
          }] : [],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/session$/.test(url)) {
        return new Response(JSON.stringify({
          ok: true,
          session_id: 'codex-session-refresh',
          session_file: '/tmp/codex-session-refresh.jsonl',
          title: 'auto refresh',
          last_user_message: runtime.session.prompt,
          last_assistant_progress_message: runtime.session.progress,
          last_assistant_message: runtime.session.reply,
          recent_turns: runtime.session.reply ? [{
            prompt: runtime.session.prompt,
            progress: runtime.session.progress,
            reply: runtime.session.reply,
          }] : [],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      return originalFetch(input, init);
    };
  });

  await page.goto(process.env.EVEN_HUB_URL, { waitUntil: 'networkidle' });

  const initial = await page.evaluate(() => {
    const panels = Array.from(document.querySelectorAll('.panel'));
    const panelText = (label) => panels.find((node) => (node.textContent || '').includes(label))?.textContent || '';
    return {
      prompt: panelText('Latest Prompt'),
      progress: panelText('Latest Progress'),
      reply: panelText('Latest Reply'),
    };
  });

  await page.evaluate(() => {
    window.__setEvenCodexSession({
      prompt: 'status',
      progress: '',
      reply: 'Ship status is green.',
    });
  });

  await page.waitForFunction(() => {
    const panels = Array.from(document.querySelectorAll('.panel'));
    const prompt = panels.find((node) => (node.textContent || '').includes('Latest Prompt'))?.textContent || '';
    const progress = panels.find((node) => (node.textContent || '').includes('Latest Progress'))?.textContent || '';
    const reply = panels.find((node) => (node.textContent || '').includes('Latest Reply'))?.textContent || '';
    return /status/.test(prompt) && /No progress yet\./.test(progress) && /Ship status is green\./.test(reply);
  }, { timeout: 5000 });

  const updated = await page.evaluate(() => {
    const panels = Array.from(document.querySelectorAll('.panel'));
    const panelText = (label) => panels.find((node) => (node.textContent || '').includes(label))?.textContent || '';
    return {
      prompt: panelText('Latest Prompt'),
      progress: panelText('Latest Progress'),
      reply: panelText('Latest Reply'),
      lastChecked: document.querySelector('.hint')?.textContent || '',
    };
  });

  console.log(JSON.stringify({ initial, updated }));
  await browser.close();
})().catch((error) => {
  console.error(String(error && error.stack || error));
  process.exit(1);
});
JS
    close $fh or die "Unable to close Playwright script: $!";

    my $output = qx{NODE_PATH="$ENV{NODE_PATH}" CHROMIUM_BIN="$chromium_bin" EVEN_HUB_URL="http://127.0.0.1:$port/" "$node_bin" "$script_path" 2>&1};
    my $exit = $? >> 8;
    is( $exit, 0, "Playwright verifies the phone-side plugin auto-refresh flow\n$output" );
    my @lines = grep { /\S/ } split /\n/, $output;
    my $payload = decode_json($lines[-1]);
    like( $payload->{initial}{prompt}, qr/hi/, 'initial plugin view shows the first prompt' );
    like( $payload->{initial}{progress}, qr/Waiting for Codex response/, 'initial plugin view shows the first progress state' );
    like( $payload->{updated}{prompt}, qr/status/, 'plugin auto-refresh updates the latest prompt without a manual click' );
    like( $payload->{updated}{reply}, qr/Ship status is green\./, 'plugin auto-refresh updates the latest reply without a manual click' );
    like( $payload->{updated}{progress}, qr/No progress yet\./, 'plugin auto-refresh clears stale progress when the live session no longer reports one' );
    like( $payload->{updated}{lastChecked}, qr/Last check/, 'plugin auto-refresh updates the visible last-check status' );
};
my $error = $@;

kill 'TERM', $pid;
waitpid $pid, 0;

die $error if $error;

done_testing;

sub _wait_for_http {
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
    die "Timed out waiting for Vite dev server on $port";
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
