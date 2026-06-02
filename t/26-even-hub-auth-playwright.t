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

plan skip_all => 'Playwright even-hub auth test requires node, Chromium, NODE_PATH, and vite dependencies'
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

    my ( $fh, $script_path ) = tempfile( 'even-codex-auth-XXXXXX', SUFFIX => '.js', TMPDIR => 1 );
    print {$fh} <<'JS';
const { chromium } = require('playwright-core');

function connector(id, mode) {
  return {
    id,
    name: mode === 'api' ? 'API Connector' : 'Helper Connector',
    origin: 'https://dd.example.test/ajax/even-codex',
    authMode: mode,
    apiKey: 'even-codex-connector',
    apiSecret: mode === 'api' ? 'device-secret' : '0000',
    activeSessionId: 'codex-session-auth',
    sessions: [{ id: 'codex-session-auth', label: 'codex-session-auth', lastSeenAt: 'Now' }],
    workspaceRef: 'foobar',
    currentSessionId: 'codex-session-auth',
    bindHost: '0.0.0.0',
    advertisedHost: '192.168.1.20',
    port: 7890,
    healthUrl: 'https://dd.example.test/ajax/even-codex/health',
    bootstrapUrl: 'https://dd.example.test/ajax/even-codex/bootstrap',
    pluginUrl: 'https://dd.example.test/app/even-codex/plugin',
    promptUrl: 'https://dd.example.test/ajax/even-codex/prompt',
    lastSeenAt: 'Not checked yet',
    lastUserMessage: '',
    lastAssistantProgressMessage: '',
    lastAssistantMessage: '',
    recentTurns: [],
  };
}

async function runScenario(browser, mode) {
  const page = await browser.newPage();
  await page.addInitScript(({ mode }) => {
    const runtime = {
      requests: [],
      bridgeStorage: new Map([
        ['d2_codex.config', JSON.stringify({
          activeConnectorId: 'connector-1',
          connectors: [(() => ({
            id: 'connector-1',
            name: mode === 'api' ? 'API Connector' : 'Helper Connector',
            origin: 'https://dd.example.test/ajax/even-codex',
            authMode: mode,
            apiKey: 'even-codex-connector',
            apiSecret: mode === 'api' ? 'device-secret' : '0000',
            activeSessionId: 'codex-session-auth',
            sessions: [{ id: 'codex-session-auth', label: 'codex-session-auth', lastSeenAt: 'Now' }],
            workspaceRef: 'foobar',
            currentSessionId: 'codex-session-auth',
            bindHost: '0.0.0.0',
            advertisedHost: '192.168.1.20',
            port: 7890,
            healthUrl: 'https://dd.example.test/ajax/even-codex/health',
            bootstrapUrl: 'https://dd.example.test/ajax/even-codex/bootstrap',
            pluginUrl: 'https://dd.example.test/app/even-codex/plugin',
            promptUrl: 'https://dd.example.test/ajax/even-codex/prompt',
            lastSeenAt: 'Not checked yet',
            lastUserMessage: '',
            lastAssistantProgressMessage: '',
            lastAssistantMessage: '',
            recentTurns: [],
          }))()],
        })],
      ]),
      eventHandler: null,
      lastPrompt: '',
    };
    window.__evenCodexRuntime = runtime;
    window.__evenCodexWaitForBridge = async () => ({
      async createStartUpPageContainer() { return 0; },
      async rebuildPageContainer(payload) { runtime.lastRebuild = payload; return 0; },
      async textContainerUpgrade(payload) { runtime.lastTextUpgrade = payload; return 0; },
      onEvenHubEvent(callback) { runtime.eventHandler = callback; return () => {}; },
      async getLocalStorage(key) { return runtime.bridgeStorage.get(key) || null; },
      async setLocalStorage(key, value) { runtime.bridgeStorage.set(key, value); },
      async audioControl() { return true; },
    });
    window.fetch = async (input, init = {}) => {
      const url = String(input);
      const headers = {};
      const rawHeaders = new Headers(init.headers || {});
      rawHeaders.forEach((value, key) => {
        headers[key.toLowerCase()] = value;
      });
      runtime.requests.push({
        url,
        method: String(init.method || 'GET').toUpperCase(),
        headers,
        body: typeof init.body === 'string' ? init.body : '',
      });

      if (/\/health$/.test(url)) {
        return new Response(JSON.stringify({
          ok: true,
          service: 'even-codex',
          workspace_ref: 'foobar',
          codex_session_id: 'codex-session-auth',
          port: 7890,
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/bootstrap$/.test(url)) {
        const routeBase = mode === 'api' ? '/ajax/even-codex' : 'https://dd.example.test/ajax/even-codex';
        const pluginBase = mode === 'api' ? '/app/even-codex/plugin' : 'https://dd.example.test/app/even-codex/plugin';
        return new Response(JSON.stringify({
          workspace_ref: 'foobar',
          codex_session_id: 'codex-session-auth',
          bind_host: '0.0.0.0',
          advertised_host: '192.168.1.20',
          port: 7890,
          health_url: `${routeBase}/health`,
          bootstrap_url: `${routeBase}/bootstrap`,
          plugin_url: pluginBase,
          prompt_url: `${routeBase}/prompt`,
          last_assistant_progress_message: runtime.lastPrompt ? 'Working...' : 'No progress yet.',
          recent_turns: runtime.lastPrompt ? [{ prompt: runtime.lastPrompt, progress: 'Working...', reply: 'Done.' }] : [],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/session$/.test(url)) {
        return new Response(JSON.stringify({
          ok: true,
          session_id: 'codex-session-auth',
          session_file: '/tmp/codex-session-auth.jsonl',
          title: 'auth flow',
          last_user_message: runtime.lastPrompt,
          last_assistant_progress_message: runtime.lastPrompt ? 'Working...' : 'No progress yet.',
          last_assistant_message: runtime.lastPrompt ? 'Done.' : 'No reply yet.',
          recent_turns: runtime.lastPrompt ? [{ prompt: runtime.lastPrompt, progress: 'Working...', reply: 'Done.' }] : [],
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
      if (/\/prompt$/.test(url)) {
        const payload = JSON.parse(String(init.body || '{}'));
        runtime.lastPrompt = payload.query || '';
        return new Response(JSON.stringify({
          ok: true,
          codex_session_id: 'codex-session-auth',
          queued_query: runtime.lastPrompt,
          tty: 'pts/99',
        }), { status: 202, headers: { 'Content-Type': 'application/json' } });
      }
      return new Response('not found', { status: 404 });
    };
  }, { mode });

  await page.goto(process.env.EVEN_HUB_URL, { waitUntil: 'networkidle' });
  await page.fill('#draftQuery', mode === 'api' ? 'api ping' : 'helper ping');
  await page.click('[data-role="send-query-button"]');
  await page.waitForFunction(() => /Submitted query to Codex/.test(document.body.textContent || ''));
  const payload = await page.evaluate(() => window.__evenCodexRuntime.requests);
  await page.close();
  return payload;
}

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_BIN,
    headless: true,
  });
  const helperRequests = await runScenario(browser, 'helper');
  const apiRequests = await runScenario(browser, 'api');
  console.log(JSON.stringify({ helperRequests, apiRequests }));
  await browser.close();
})().catch((error) => {
  console.error(String(error && error.stack || error));
  process.exit(1);
});
JS
    close $fh or die "Unable to close Playwright script: $!";

    my $output = qx{NODE_PATH="$ENV{NODE_PATH}" CHROMIUM_BIN="$chromium_bin" EVEN_HUB_URL="http://127.0.0.1:$port/" "$node_bin" "$script_path" 2>&1};
    my $exit = $? >> 8;
    is( $exit, 0, "Playwright verifies DD helper and API auth connector modes\n$output" );

    my $payload = decode_json($output);
    my $helper = $payload->{helperRequests};
    my $api = $payload->{apiRequests};

    ok( !scalar( grep { $_->{url} =~ /\/health$/ } @{$helper} ), 'helper mode skips the direct bridge health route when the connector origin is the DD ajax surface' );
    ok( !scalar( grep { $_->{url} =~ /\/health$/ } @{$api} ), 'API-key mode skips the DD health route and relies on bootstrap plus session' );

    ok( scalar( grep { $_->{url} =~ /\/bootstrap$/ } @{$helper} ), 'helper mode reads the DD bootstrap route' );
    ok( scalar( grep { $_->{url} =~ /\/session$/ } @{$helper} ), 'helper mode reads the DD session route' );
    ok( scalar( grep { $_->{url} =~ /\/prompt$/ && $_->{method} eq 'POST' } @{$helper} ), 'helper mode posts prompts through the DD prompt route' );
    ok( scalar( grep { $_->{url} =~ /\/bootstrap$/ } @{$api} ), 'API-key mode reads the DD bootstrap route' );
    ok( scalar( grep { $_->{url} =~ /\/session$/ } @{$api} ), 'API-key mode reads the DD session route' );
    ok( scalar( grep { $_->{url} =~ /\/prompt$/ && $_->{method} eq 'POST' } @{$api} ), 'API-key mode posts prompts through the DD prompt route' );
    ok(
        scalar( grep { $_->{url} eq 'https://dd.example.test/ajax/even-codex/prompt' } @{$api} ),
        'API-key mode resolves relative bootstrap prompt routes back onto the DD connector origin',
    );

    ok(
        !scalar( grep {
            defined $_->{headers}{'x-dd-api-key'} || defined $_->{headers}{'x-dd-api-secret'}
        } @{$helper} ),
        'helper mode does not attach DD API headers',
    );

    my @api_header_requests = grep {
        $_->{url} =~ m{/bootstrap$|/session$|/prompt$}
    } @{$api};
    ok( @api_header_requests >= 3, 'API-key mode exercises bootstrap, session, and prompt through the DD connector' );
    for my $request (@api_header_requests) {
        is( $request->{headers}{'x-dd-api-key'}, 'even-codex-connector', 'API-key mode sends the fixed DD API key header' );
        is( $request->{headers}{'x-dd-api-secret'}, 'device-secret', 'API-key mode sends the DD API secret header' );
    }
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
