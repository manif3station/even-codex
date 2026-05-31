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
    $server->serve( max_requests => 11 );
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
    my $prompt_payload = decode_json( $prompt->{body} );
    ok( $prompt_payload->{ok}, '/prompt reports ok' );
    is( $prompt_payload->{queued_query}, 'what is the year today?', '/prompt returns the queued query text' );
    is( $prompt_payload->{tty}, 'pts/9', '/prompt returns the tty used for Codex prompt submission' );

    my $plugin = _http_get( $port, '/plugin/' );
    is( $plugin->{status}, 200, '/plugin/ returns HTTP 200' );
    like( $plugin->{body}, qr/D2-Codex Bridge/, '/plugin/ serves the plugin HTML shell' );
    like( $plugin->{body}, qr/even-codex-app/, '/plugin/ includes the plugin root container' );

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

    my ( $head, $response_body ) = split /\r?\n\r?\n/, $raw, 2;
    my ($status) = $head =~ m{\AHTTP/1\.1\s+(\d+)};
    my ($content_type) = $head =~ /^Content-Type:\s*(.+)$/mi;
    my ($allow_origin) = $head =~ /^Access-Control-Allow-Origin:\s*(.+)$/mi;
    $content_type =~ s/\r\z// if defined $content_type;
    $allow_origin =~ s/\r\z// if defined $allow_origin;
    return {
        status                      => 0 + $status,
        content_type                => $content_type,
        access_control_allow_origin => $allow_origin,
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
