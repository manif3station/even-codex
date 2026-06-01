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

plan skip_all => 'Playwright even-hub voice test requires node, Chromium, NODE_PATH, and vite dependencies'
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

    my ( $fh, $script_path ) = tempfile( 'even-codex-voice-XXXXXX', SUFFIX => '.js', TMPDIR => 1 );
    print {$fh} <<'JS';
const { chromium } = require('playwright-core');

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_BIN,
    headless: true,
  });
  const page = await browser.newPage();
  await page.addInitScript(() => {
    const runtime = {
      bridgeStorage: new Map(),
      audioCalls: [],
      lastPrompt: '',
      lastReply: 'No reply yet.',
      eventHandler: null,
    };
    window.__evenCodexRuntime = runtime;
    window.__evenCodexWaitForBridge = async () => ({
      async createStartUpPageContainer() { return 0; },
      async rebuildPageContainer(payload) { runtime.lastRebuild = payload; return 0; },
      async textContainerUpgrade(payload) { runtime.lastTextUpgrade = payload; return 0; },
      onEvenHubEvent(callback) { runtime.eventHandler = callback; return () => {}; },
      async getLocalStorage(key) { return runtime.bridgeStorage.get(key) || null; },
      async setLocalStorage(key, value) { runtime.bridgeStorage.set(key, value); },
      async audioControl(isOpen) { runtime.audioCalls.push(Boolean(isOpen)); return true; },
    });
    window.__triggerEvenHubEvent = async (event) => {
      if (typeof runtime.eventHandler === 'function') {
        await runtime.eventHandler(event);
      }
    };
    window.__evenCodexSpeechRecognitionFactory = () => {
      return {
        continuous: false,
        interimResults: true,
        lang: 'en-GB',
        start() {
          setTimeout(() => this.onstart && this.onstart(), 0);
          setTimeout(() => this.onresult && this.onresult({
            resultIndex: 0,
            results: [
              { 0: { transcript: 'what is 2 plus 3' }, isFinal: true }
            ]
          }), 50);
          setTimeout(() => this.onend && this.onend(), 80);
        },
        stop() {
          setTimeout(() => this.onend && this.onend(), 0);
        },
        abort() {
          setTimeout(() => this.onend && this.onend(), 0);
        },
      };
    };
    const originalFetch = window.fetch.bind(window);
    window.fetch = async (input, init) => {
      const url = String(input);
      if (/\/health$/.test(url)) {
        return new Response(JSON.stringify({
          ok: true,
          service: 'even-codex',
          workspace_ref: 'foobar',
          codex_session_id: 'codex-session-voice',
          port: 6789,
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/bootstrap$/.test(url)) {
        return new Response(JSON.stringify({
          workspace_ref: 'foobar',
          codex_session_id: 'codex-session-voice',
          bind_host: '0.0.0.0',
          advertised_host: '192.168.1.20',
          port: 6789,
          health_url: 'http://192.168.1.20:6789/health',
          bootstrap_url: 'http://192.168.1.20:6789/bootstrap',
          plugin_url: 'http://192.168.1.20:6789/plugin/',
          prompt_url: 'http://192.168.1.20:6789/prompt',
          last_assistant_progress_message: runtime.lastPrompt ? 'Waiting for Codex response...' : 'No progress yet.',
          recent_turns: runtime.lastPrompt ? [{ prompt: runtime.lastPrompt, progress: 'Waiting for Codex response...', reply: runtime.lastReply }] : [],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/session$/.test(url)) {
        return new Response(JSON.stringify({
          ok: true,
          session_id: 'codex-session-voice',
          session_file: '/tmp/codex-session-voice.jsonl',
          title: 'voice flow',
          last_user_message: runtime.lastPrompt,
          last_assistant_progress_message: runtime.lastPrompt ? 'Waiting for Codex response...' : 'No progress yet.',
          last_assistant_message: runtime.lastReply,
          recent_turns: runtime.lastPrompt ? [{ prompt: runtime.lastPrompt, progress: 'Waiting for Codex response...', reply: runtime.lastReply }] : [],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/prompt$/.test(url) && init && init.method === 'POST') {
        const payload = JSON.parse(String(init.body || '{}'));
        runtime.lastPrompt = payload.query || '';
        runtime.lastReply = 'Voice query submitted.';
        return new Response(JSON.stringify({
          ok: true,
          codex_session_id: 'codex-session-voice',
          queued_query: runtime.lastPrompt,
          tty: 'pts/7',
        }), { status: 202, headers: { 'Content-Type': 'application/json' } });
      }
      return originalFetch(input, init);
    };
  });

  await page.goto(process.env.EVEN_HUB_URL, { waitUntil: 'networkidle' });
  await page.evaluate(() => window.__triggerEvenHubEvent({ sysEvent: { eventSource: 1 } }));
  await page.waitForFunction(() => {
    const area = document.querySelector('#draftQuery');
    return area && area.value === 'what is 2 plus 3';
  });
  await page.waitForFunction(() => {
    const value = Array.from(document.querySelectorAll('.panel .label')).some((node) => node.textContent === 'Voice Query');
    return Boolean(value);
  });
  await page.evaluate(() => window.__triggerEvenHubEvent({ sysEvent: { eventSource: 1 } }));
  await page.waitForFunction(() => {
    const nodes = Array.from(document.querySelectorAll('.panel .label'));
    const lastPrompt = nodes.find((node) => node.textContent === 'Latest Prompt');
    return !!lastPrompt && lastPrompt.parentElement && /what is 2 plus 3/.test(lastPrompt.parentElement.textContent || '');
  });
  const payload = await page.evaluate(() => ({
    draftQuery: document.querySelector('#draftQuery')?.value || '',
    statusText: document.querySelector('.status')?.textContent || '',
    latestPrompt: Array.from(document.querySelectorAll('.panel')).find((node) => /Latest Prompt/.test(node.textContent || ''))?.textContent || '',
    audioCalls: window.__evenCodexRuntime.audioCalls,
  }));

  const emptyPage = await browser.newPage();
  await emptyPage.addInitScript(() => {
    const runtime = {
      bridgeStorage: new Map(),
      audioCalls: [],
      eventHandler: null,
    };
    window.__evenCodexRuntime = runtime;
    window.__evenCodexWaitForBridge = async () => ({
      async createStartUpPageContainer() { return 0; },
      async rebuildPageContainer(payload) { runtime.lastRebuild = payload; return 0; },
      async textContainerUpgrade(payload) { runtime.lastTextUpgrade = payload; return 0; },
      onEvenHubEvent(callback) { runtime.eventHandler = callback; return () => {}; },
      async getLocalStorage(key) { return runtime.bridgeStorage.get(key) || null; },
      async setLocalStorage(key, value) { runtime.bridgeStorage.set(key, value); },
      async audioControl(isOpen) { runtime.audioCalls.push(Boolean(isOpen)); return true; },
    });
    window.__triggerEvenHubEvent = async (event) => {
      if (typeof runtime.eventHandler === 'function') {
        await runtime.eventHandler(event);
      }
    };
    const originalFetch = window.fetch.bind(window);
    window.fetch = async (input, init) => {
      const url = String(input);
      if (/\/health$/.test(url)) {
        return new Response(JSON.stringify({
          ok: true,
          service: 'even-codex',
          workspace_ref: 'foobar',
          codex_session_id: 'codex-session-empty',
          port: 6789,
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/bootstrap$/.test(url)) {
        return new Response(JSON.stringify({
          workspace_ref: 'foobar',
          codex_session_id: 'codex-session-empty',
          bind_host: '0.0.0.0',
          advertised_host: '192.168.1.20',
          port: 6789,
          health_url: 'http://192.168.1.20:6789/health',
          bootstrap_url: 'http://192.168.1.20:6789/bootstrap',
          plugin_url: 'http://192.168.1.20:6789/plugin/',
          prompt_url: 'http://192.168.1.20:6789/prompt',
          last_assistant_progress_message: 'No progress yet.',
          recent_turns: [],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/session$/.test(url)) {
        return new Response(JSON.stringify({
          ok: true,
          session_id: 'codex-session-empty',
          session_file: '/tmp/codex-session-empty.jsonl',
          title: 'empty flow',
          last_user_message: '',
          last_assistant_progress_message: 'No progress yet.',
          last_assistant_message: 'No reply yet.',
          recent_turns: [],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/prompt$/.test(url) && init && init.method === 'POST') {
        return new Response(JSON.stringify({
          ok: true,
          codex_session_id: 'codex-session-empty',
          queued_query: '',
          tty: 'pts/8',
        }), { status: 202, headers: { 'Content-Type': 'application/json' } });
      }
      return originalFetch(input, init);
    };
  });
  await emptyPage.goto(process.env.EVEN_HUB_URL, { waitUntil: 'networkidle' });
  await emptyPage.evaluate(() => window.__triggerEvenHubEvent({ sysEvent: { eventSource: 1 } }));
  await emptyPage.waitForFunction(() => /Voice query capture failed|Voice query capture is unavailable/.test(document.body.textContent || ''));
  await emptyPage.evaluate(() => window.__triggerEvenHubEvent({ sysEvent: { eventSource: 1 } }));
  await emptyPage.waitForFunction(() => {
    return /Popup closed with no staged query/.test(document.body.textContent || '');
  });
  const emptyPayload = await emptyPage.evaluate(() => ({
    statusText: document.body.textContent || '',
    voiceState: Array.from(document.querySelectorAll('.panel')).find((node) => /Voice Query/.test(node.textContent || ''))?.textContent || '',
  }));
  await emptyPage.close();
  console.log(JSON.stringify(payload));
  console.log(JSON.stringify(emptyPayload));
  await browser.close();
})().catch((error) => {
  console.error(String(error && error.stack || error));
  process.exit(1);
});
JS
    close $fh or die "Unable to close Playwright script: $!";

    my $output = qx{NODE_PATH="$ENV{NODE_PATH}" CHROMIUM_BIN="$chromium_bin" EVEN_HUB_URL="http://127.0.0.1:$port/" "$node_bin" "$script_path" 2>&1};
    my $exit = $? >> 8;
    is( $exit, 0, "Playwright verifies the Even Hub voice flow\n$output" );
    my @lines = grep { /\S/ } split /\n/, $output;
    my $payload = decode_json($lines[0]);
    my $empty_payload = decode_json($lines[1]);
    is( $payload->{draftQuery}, 'what is 2 plus 3', 'voice flow mirrors recognised text into the draft query field' );
    like( $payload->{latestPrompt}, qr/what is 2 plus 3/, 'voice flow submits the recognised query through the existing prompt path' );
    ok( scalar @{ $payload->{audioCalls} } >= 2, 'voice flow toggles bridge audio control during the simulated voice session' );
    like( $empty_payload->{statusText}, qr/Popup closed with no staged query/, 'empty standby click closes the popup instead of leaving a dead-end send error' );
    like( $empty_payload->{voiceState}, qr/(?:UNSUPPORTED|ERROR)/, 'empty-close proof also covers the non-usable speech-recognition fallback state' );
};
my $error = $@;

kill 'TERM', $pid;
waitpid $pid, 0;

die $error if $error;

done_testing;

sub _wait_for_http {
    my ($port) = @_;
    for ( 1 .. 100 ) {
        my $socket = IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
            Proto    => 'tcp',
        );
        if ($socket) {
            print {$socket} "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
            my $buffer = q{};
            while ( my $line = <$socket> ) {
                $buffer .= $line;
                last if $buffer =~ /\r?\n\r?\n/s;
            }
            close $socket;
            return 1 if $buffer =~ m{\AHTTP/1\.[01] 200};
        }
        sleep 0.1;
    }
    die "Timed out waiting for Vite on port $port";
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
