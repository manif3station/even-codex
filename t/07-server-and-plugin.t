use strict;
use warnings FATAL => 'all';

use JSON::PP qw(decode_json);
use IO::Socket::INET;
use Test::More;
use Time::HiRes qw(sleep);

use lib 'lib';
use Even::Codex::Plugin;
use Even::Codex::Server;

my $port = _reserve_port();
my $pid = fork();
die "Unable to fork even-codex test server: $!" if !defined $pid;

if ( $pid == 0 ) {
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => $port,
        advertised_host  => '192.168.1.20',
        workspace_ref    => 'foobar',
        codex_session_id => 'codex-session-77',
    );
    $server->serve( max_requests => 8 );
    exit 0;
}

eval {
    _wait_for_port($port);

    my $health = _http_get( $port, '/health' );
    is( $health->{status}, 200, '/health returns HTTP 200' );
    is( $health->{content_type}, 'application/json', '/health returns JSON' );
    my $health_payload = decode_json( $health->{body} );
    ok( $health_payload->{ok}, '/health reports ok' );
    is( $health_payload->{workspace_ref}, 'foobar', '/health reports the workspace ref' );

    my $bootstrap = _http_get( $port, '/bootstrap' );
    is( $bootstrap->{status}, 200, '/bootstrap returns HTTP 200' );
    my $bootstrap_payload = decode_json( $bootstrap->{body} );
    is( $bootstrap_payload->{codex_session_id}, 'codex-session-77', '/bootstrap reports the paired Codex session id' );
    is( $bootstrap_payload->{plugin_url}, 'http://192.168.1.20:' . $port . '/plugin/', '/bootstrap reports the plugin URL' );

    my $plugin = _http_get( $port, '/plugin/' );
    is( $plugin->{status}, 200, '/plugin/ returns HTTP 200' );
    like( $plugin->{body}, qr/Even Codex Bridge/, '/plugin/ serves the plugin HTML shell' );
    like( $plugin->{body}, qr/even-codex-app/, '/plugin/ includes the plugin root container' );

    my $manifest = _http_get( $port, '/plugin/manifest.json' );
    is( $manifest->{status}, 200, '/plugin/manifest.json returns HTTP 200' );
    my $manifest_payload = decode_json( $manifest->{body} );
    is( $manifest_payload->{id}, 'even-codex-plugin', 'plugin manifest exposes a stable plugin id' );
    is( $manifest_payload->{bootstrap_path}, '/bootstrap', 'plugin manifest points the app at the bootstrap route' );

    my $javascript = _http_get( $port, '/plugin/app.js' );
    is( $javascript->{status}, 200, '/plugin/app.js returns HTTP 200' );
    like( $javascript->{body}, qr/fetch\('\/bootstrap'\)/, '/plugin/app.js fetches connector bootstrap data' );

    my $stylesheet = _http_get( $port, '/plugin/styles.css' );
    is( $stylesheet->{status}, 200, '/plugin/styles.css returns HTTP 200' );
    like( $stylesheet->{body}, qr/\.even-codex-shell/, '/plugin/styles.css serves the plugin stylesheet' );

    is( Even::Codex::Plugin::manifest_hash()->{name}, 'Even Codex', 'plugin manifest helper returns the plugin name' );
};
my $error = $@;

kill 'TERM', $pid;
waitpid $pid, 0;

die $error if $error;

done_testing;

sub _http_get {
    my ( $port, $path ) = @_;
    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Unable to connect to test server: $!";

    print {$socket} "GET $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nConnection: close\r\n\r\n";
    my $raw = do { local $/; <$socket> };
    close $socket;

    my ( $head, $body ) = split /\r?\n\r?\n/, $raw, 2;
    my ($status) = $head =~ m{\AHTTP/1\.1\s+(\d+)};
    my ($content_type) = $head =~ /^Content-Type:\s*(.+)$/mi;
    $content_type =~ s/\r\z// if defined $content_type;
    return {
        status       => 0 + $status,
        content_type => $content_type,
        body         => defined $body ? $body : q{},
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
