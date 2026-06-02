use strict;
use warnings FATAL => 'all';

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use IO::Socket::INET;
use Test::More;
use Time::HiRes qw(sleep);

use lib 'lib';
use Even::Codex::Plugin;
use Even::Codex::Sender;
use Even::Codex::Server;

for my $case (
    [ 'host',             { port => 1, workspace_ref => 'w', codex_session_id => 's' }, qr/Host is required/ ],
    [ 'port',             { host => '127.0.0.1', workspace_ref => 'w', codex_session_id => 's' }, qr/Port is required/ ],
    [ 'workspace_ref',    { host => '127.0.0.1', port => 1, codex_session_id => 's' }, qr/Workspace ref is required/ ],
    [ 'codex_session_id', { host => '127.0.0.1', port => 1, workspace_ref => 'w' }, qr/Codex session id is required/ ],
) {
    my ( $label, $args, $pattern ) = @{$case};
    my $error = eval { Even::Codex::Server->new( %{$args} ); 1 } ? q{} : $@;
    like( $error, $pattern, "constructor requires $label" );
}

{
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => 6789,
        workspace_ref    => 'workspace-default',
        codex_session_id => 'session-default',
    );
    is( $server->{advertised_host}, '127.0.0.1', 'constructor defaults the advertised host to localhost' );
    is( ref $server->{env}, 'HASH', 'constructor defaults the env hash when none is provided' );
    isa_ok( $server->{sender}, 'Even::Codex::Sender', 'constructor creates a default sender when none is supplied' );
    is( $server->base_url, 'http://127.0.0.1:6789', 'base_url uses the advertised host and port' );
    is_deeply(
        [ $server->_response_for_request( 'OPTIONS', '/prompt', q{} ) ],
        [ 204, 'text/plain; charset=utf-8', q{} ],
        '_response_for_request returns the explicit prompt preflight response',
    );
    is_deeply(
        [ $server->_response_for_request( 'OPTIONS', '/health', q{} ) ],
        [ 404, 'text/plain; charset=utf-8', 'not found' ],
        '_response_for_request leaves non-prompt OPTIONS requests on the default not-found path',
    );
    is( Even::Codex::Server::_status_text(200), 'OK', '_status_text maps 200 to OK' );
    is( Even::Codex::Server::_status_text(202), 'Accepted', '_status_text maps 202 to Accepted' );
    is( Even::Codex::Server::_status_text(204), 'No Content', '_status_text maps 204 to No Content' );
    is( Even::Codex::Server::_status_text(400), 'Bad Request', '_status_text maps 400 to Bad Request' );
    is( Even::Codex::Server::_status_text(404), 'Not Found', '_status_text maps unknown statuses to Not Found' );
}

{
    my $server = Even::Codex::Server->new(
        host             => '0.0.0.0',
        port             => 4321,
        advertised_host  => '192.168.1.20',
        workspace_ref    => 'wrapped',
        codex_session_id => 'wrapped-session',
        env              => { HOME => '/tmp/wrapped-home' },
        sender           => bless( {}, 'Local::PromptSender' ),
    );

    local *Even::Codex::Connector::bootstrap_payload = sub {
        my (%args) = @_;
        return {
            plugin_url       => 'http://192.168.1.20:4321/plugin',
            workspace_ref    => $args{workspace_ref},
            codex_session_id => $args{codex_session_id},
        };
    };
    local *Even::Codex::Connector::health_payload = sub {
        my (%args) = @_;
        return { ok => 1, service => 'even-codex', port => $args{port}, workspace_ref => $args{workspace_ref} };
    };
    local *Even::Codex::Connector::session_payload = sub {
        my (%args) = @_;
        return { ok => 1, session_id => $args{codex_session_id}, workspace_ref => $args{workspace_ref} };
    };
    local *Even::Codex::Connector::prompt_payload = sub {
        my (%args) = @_;
        return {
            ok               => 1,
            workspace_ref    => $args{workspace_ref},
            codex_session_id => $args{codex_session_id},
            queued_query     => $args{query},
            sender_class     => ref $args{sender},
        };
    };

    my $wrapped_bootstrap = $server->bootstrap_payload;
    is( $wrapped_bootstrap->{plugin_url}, 'http://192.168.1.20:4321/plugin/', 'bootstrap_payload appends the trailing slash for the plugin url' );
    is( $wrapped_bootstrap->{workspace_ref}, 'wrapped', 'bootstrap_payload forwards the workspace ref through the connector' );

    my $wrapped_health = $server->health_payload;
    is( $wrapped_health->{port}, 4321, 'health_payload forwards the listen port through the connector' );

    my $wrapped_session = $server->session_payload;
    is( $wrapped_session->{session_id}, 'wrapped-session', 'session_payload forwards the paired Codex session id' );

    my $wrapped_prompt = $server->prompt_payload( query => 'ship status' );
    is( $wrapped_prompt->{queued_query}, 'ship status', 'prompt_payload forwards the user query to the connector' );
    is( $wrapped_prompt->{sender_class}, 'Local::PromptSender', 'prompt_payload forwards the configured sender object to the connector' );

    my $wrapped_prompt_error = eval { $server->prompt_payload( query => q{} ); 1 } ? q{} : $@;
    like( $wrapped_prompt_error, qr/Query is required/, 'prompt_payload rejects an empty wrapped query before reaching the connector' );
}

{
    my $socket = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Listen    => 1,
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "Unable to reserve the conflict test port: $!";
    my $busy_port = $socket->sockport;
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => $busy_port,
        workspace_ref    => 'busy',
        codex_session_id => 'busy-session',
    );
    my $error = eval { $server->serve( max_requests => 1 ); 1 } ? q{} : $@;
    like( $error, qr/Unable to start even-codex bridge on 127\.0\.0\.1:$busy_port/, 'serve fails clearly when the listen port is already in use' );
    close $socket or die "Unable to close the conflict test socket: $!";
}

my $tmp = tempdir( CLEANUP => 1 );
my $codex_home = File::Spec->catdir( $tmp, '.codex' );
my $session_dir = File::Spec->catdir( $codex_home, 'sessions', '2026', '05', '31' );
make_path($session_dir);
my $session_id = 'codex-session-77';
my $session_path = File::Spec->catfile( $session_dir, 'rollout-2026-05-31T17-00-00-' . $session_id . '.jsonl' );
open my $session_fh, '>', $session_path or die "Unable to open $session_path: $!";
print {$session_fh} <<'JSONL';
{"timestamp":"2026-05-31T17:00:00.000Z","type":"session_meta","payload":{"id":"codex-session-77","cwd":"/tmp/foobar","title":"hi"}}
{"timestamp":"2026-05-31T17:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"hi"}}
{"timestamp":"2026-05-31T17:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hello from codex"}],"phase":"final_answer"}}
JSONL
close $session_fh or die "Unable to close $session_path: $!";

my $port = _reserve_port();
my $pid = fork();
die "Unable to fork even-codex test server: $!" if !defined $pid;

if ( $pid == 0 ) {
    my @submitted;
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => $port,
        advertised_host  => '192.168.1.20',
        workspace_ref    => 'foobar',
        codex_session_id => $session_id,
        sender           => Even::Codex::Sender->new(
            ps_lines_provider => sub { return ["pts/9 /opt/codex-cli/bin/codex resume $session_id\n"]; },
            tty_writer        => sub {
                my ( $tty, $prompt ) = @_;
                push @submitted, { tty => $tty, prompt => $prompt };
                return 1;
            },
        ),
        env              => {
            HOME                   => $tmp,
            EVEN_CODEX_CODEX_HOME  => $codex_home,
        },
    );
    $server->serve( max_requests => 18 );
    exit 0;
}

eval {
    _wait_for_port($port);

    my $health = _http_get( $port, '/health' );
    is( $health->{status}, 200, '/health returns HTTP 200' );
    is( $health->{content_type}, 'application/json', '/health returns JSON' );
    is( $health->{access_control_allow_origin}, '*', '/health allows cross-origin Hub app fetches' );
    my $health_payload = decode_json( $health->{body} );
    ok( $health_payload->{ok}, '/health reports ok' );
    is( $health_payload->{workspace_ref}, 'foobar', '/health reports the workspace ref' );

    my $bootstrap = _http_get( $port, '/bootstrap' );
    is( $bootstrap->{status}, 200, '/bootstrap returns HTTP 200' );
    my $bootstrap_payload = decode_json( $bootstrap->{body} );
    is( $bootstrap_payload->{codex_session_id}, 'codex-session-77', '/bootstrap reports the paired Codex session id' );
    is( $bootstrap_payload->{last_user_message}, 'hi', '/bootstrap reports the latest user message' );
    is( $bootstrap_payload->{last_assistant_progress_message}, q{}, '/bootstrap reports the latest progress message when none exists yet' );
    is( $bootstrap_payload->{last_assistant_message}, 'hello from codex', '/bootstrap reports the latest assistant message' );
    is( $bootstrap_payload->{plugin_url}, 'http://192.168.1.20:' . $port . '/plugin/', '/bootstrap reports the plugin URL' );
    is( $bootstrap_payload->{prompt_url}, 'http://192.168.1.20:' . $port . '/prompt', '/bootstrap reports the prompt submit URL' );

    my $session = _http_get( $port, '/session' );
    is( $session->{status}, 200, '/session returns HTTP 200' );
    my $session_payload = decode_json( $session->{body} );
    ok( $session_payload->{ok}, '/session reports ok' );
    is( $session_payload->{last_user_message}, 'hi', '/session reports the latest user message' );
    is( $session_payload->{last_assistant_message}, 'hello from codex', '/session reports the latest assistant message' );
    is_deeply( $session_payload->{recent_turns}, [ { prompt => 'hi', progress => q{}, reply => 'hello from codex' } ], '/session returns the latest recent turn list' );

    my $prompt = _http_request( $port, 'POST', '/prompt', '{"query":"what is the year today?"}' );
    is( $prompt->{status}, 202, '/prompt accepts a prompt submission' );
    is( $prompt->{access_control_allow_methods}, 'GET, POST, OPTIONS', '/prompt advertises the CORS methods needed by the Hub WebView' );
    is( $prompt->{access_control_allow_headers}, 'Content-Type', '/prompt advertises the JSON content header needed by the Hub WebView' );
    my $prompt_payload = decode_json( $prompt->{body} );
    ok( $prompt_payload->{ok}, '/prompt reports ok' );
    is( $prompt_payload->{queued_query}, 'what is the year today?', '/prompt returns the queued query text' );
    is( $prompt_payload->{tty}, 'pts/9', '/prompt returns the tty used for Codex prompt submission' );

    my $prompt_preflight = _http_request( $port, 'OPTIONS', '/prompt' );
    is( $prompt_preflight->{status}, 204, '/prompt accepts the CORS preflight request used by the Hub WebView' );
    is( $prompt_preflight->{access_control_allow_methods}, 'GET, POST, OPTIONS', '/prompt preflight reports the allowed methods' );
    is( $prompt_preflight->{access_control_allow_headers}, 'Content-Type', '/prompt preflight reports the allowed headers' );

    my $wrong_preflight = _http_request( $port, 'OPTIONS', '/health' );
    is( $wrong_preflight->{status}, 404, 'OPTIONS only matches the prompt preflight route' );

    my $plugin = _http_get( $port, '/plugin/' );
    is( $plugin->{status}, 200, '/plugin/ returns HTTP 200' );
    like( $plugin->{body}, qr/D2-Codex Bridge/, '/plugin/ serves the plugin HTML shell' );
    like( $plugin->{body}, qr/even-codex-app/, '/plugin/ includes the plugin root container' );

    my $plugin_without_slash = _http_get( $port, '/plugin' );
    is( $plugin_without_slash->{status}, 200, '/plugin returns HTTP 200' );
    like( $plugin_without_slash->{body}, qr/D2-Codex Bridge/, '/plugin serves the plugin HTML shell without the trailing slash path' );

    my $manifest = _http_get( $port, '/plugin/manifest.json' );
    is( $manifest->{status}, 200, '/plugin/manifest.json returns HTTP 200' );
    my $manifest_payload = decode_json( $manifest->{body} );
    is( $manifest_payload->{id}, 'even-codex-plugin', 'plugin manifest exposes a stable plugin id' );
    is( $manifest_payload->{bootstrap_path}, '/bootstrap', 'plugin manifest points the app at the bootstrap route' );

    my $javascript = _http_get( $port, '/plugin/app.js' );
    is( $javascript->{status}, 200, '/plugin/app.js returns HTTP 200' );
    like( $javascript->{body}, qr/fetch\('\/bootstrap'\)/, '/plugin/app.js fetches connector bootstrap data' );
    like( $javascript->{body}, qr/fetch\('\/session'\)/, '/plugin/app.js fetches connector session transcript data' );

    my $stylesheet = _http_get( $port, '/plugin/styles.css' );
    is( $stylesheet->{status}, 200, '/plugin/styles.css returns HTTP 200' );
    like( $stylesheet->{body}, qr/\.even-codex-shell/, '/plugin/styles.css serves the plugin stylesheet' );

    my $missing_query = _http_request( $port, 'POST', '/prompt', '{"query":""}' );
    is( $missing_query->{status}, 400, '/prompt rejects an empty query' );
    like( $missing_query->{body}, qr/Query is required/, '/prompt returns a clear validation error for empty queries' );

    my $non_hash = _http_request( $port, 'POST', '/prompt', '[]' );
    is( $non_hash->{status}, 400, '/prompt rejects a non-object JSON payload' );

    my $empty_post = _http_request( $port, 'POST', '/prompt', q{} );
    is( $empty_post->{status}, 400, '/prompt rejects an empty POST body' );

    my $bad_content_length = _raw_http_request(
        $port,
        "POST /prompt HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nContent-Type: application/json\r\nContent-Length: nope\r\nConnection: close\r\n\r\n{\"query\":\"ignored\"}",
    );
    is( $bad_content_length->{status}, 400, 'invalid content-length leaves the prompt body unread and returns a validation error' );

    my $bad_header = _raw_http_request(
        $port,
        "GET /health HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nBroken-Header\r\nConnection: close\r\n\r\n",
    );
    is( $bad_header->{status}, 200, 'header lines without a colon are ignored safely' );

    my $bad_request = _raw_http_request(
        $port,
        "BROKENREQUEST\r\nConnection: close\r\n\r\n",
    );
    is( $bad_request->{status}, 404, 'malformed request lines fall back to the default not found route' );

    is( Even::Codex::Plugin::manifest_hash()->{name}, 'D2-Codex', 'plugin manifest helper returns the plugin name' );
};
my $error = $@;

kill 'TERM', $pid;
waitpid $pid, 0;

die $error if $error;

done_testing;

sub _http_get {
    my ( $port, $path ) = @_;
    return _http_request( $port, 'GET', $path );
}

sub _http_request {
    my ( $port, $method, $path, $body ) = @_;
    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Unable to connect to test server: $!";

    my $payload = defined $body ? $body : q{};
    print {$socket} "$method $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nConnection: close\r\n";
    if ( $method eq 'POST' ) {
        print {$socket} "Content-Type: application/json\r\n";
        print {$socket} "Content-Length: " . length($payload) . "\r\n";
    }
    print {$socket} "\r\n";
    print {$socket} $payload if $method eq 'POST';
    my $raw = do { local $/; <$socket> };
    close $socket;
    return _parse_http_response($raw);
}

sub _raw_http_request {
    my ( $port, $raw_request ) = @_;
    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Unable to connect to test server: $!";

    print {$socket} $raw_request;
    my $raw = do { local $/; <$socket> };
    close $socket;
    return _parse_http_response($raw);
}

sub _parse_http_response {
    my ($raw) = @_;
    my ( $head, $response_body ) = split /\r?\n\r?\n/, $raw, 2;
    my ($status) = $head =~ m{\AHTTP/1\.1\s+(\d+)};
    my ($content_type) = $head =~ /^Content-Type:\s*(.+)$/mi;
    my ($allow_origin) = $head =~ /^Access-Control-Allow-Origin:\s*(.+)$/mi;
    my ($allow_methods) = $head =~ /^Access-Control-Allow-Methods:\s*(.+)$/mi;
    my ($allow_headers) = $head =~ /^Access-Control-Allow-Headers:\s*(.+)$/mi;
    $content_type =~ s/\r\z// if defined $content_type;
    $allow_origin =~ s/\r\z// if defined $allow_origin;
    $allow_methods =~ s/\r\z// if defined $allow_methods;
    $allow_headers =~ s/\r\z// if defined $allow_headers;
    return {
        status                      => 0 + $status,
        content_type                => $content_type,
        access_control_allow_origin => $allow_origin,
        access_control_allow_methods => $allow_methods,
        access_control_allow_headers => $allow_headers,
        body                        => defined $response_body ? $response_body : q{},
    };
}

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
