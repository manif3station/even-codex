use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use IO::Socket::INET;
use JSON::PP qw(decode_json);
use Test::More;

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return $text;
}

sub run_cli {
    my ( $env, @argv ) = @_;
    local %ENV = ( %{$env}, PATH => $ENV{PATH}, HOME => $ENV{HOME} );
    return _run_shell_command('./cli/e2e', @argv);
}

sub run_start_add {
    my ( $env, $session_id ) = @_;
    local %ENV = ( %{$env}, PATH => $ENV{PATH}, HOME => $ENV{HOME} );
    return _run_shell_command( './cli/start', 'add', $session_id );
}

sub http_get {
    my ($url) = @_;
    my ( $host, $port, $path ) = $url =~ m{\Ahttp://([^:/]+):(\d+)(/\S*)\z}
      or die "Unsupported URL $url";

    my $socket = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Unable to connect to $url: $!";

    print {$socket} "GET $path HTTP/1.0\r\nHost: $host\r\n\r\n";
    my $response = q{};
    while ( my $chunk = <$socket> ) {
        $response .= $chunk;
    }
    close $socket;

    $response =~ s/\A.*?\r?\n\r?\n//s;
    return $response;
}

sub _run_shell_command {
    my (@command) = @_;
    my ( $fh, $output_path ) = tempfile();
    close $fh or die "Unable to close temp output file: $!";

    my $command = join q{ }, map { _shell_quote($_) } @command;
    system( 'bash', '-lc', "$command > " . _shell_quote($output_path) . " 2>&1" );
    my $rc = $? >> 8;
    my $output = slurp($output_path);
    unlink $output_path or die "Unable to remove temp output file: $!";
    return ( $rc, $output );
}

sub _shell_quote {
    my ($value) = @_;
    $value = q{} if !defined $value;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
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

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $runtime_root = File::Spec->catdir( $tmp, 'runtime' );
    my $app_dir = File::Spec->catdir( $tmp, 'app' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path( $app_dir, $bin_dir );

    my $bridge_port = _reserve_port();
    my $app_port = _reserve_port();
    my $sim_capture = File::Spec->catfile( $tmp, 'simulator-capture.txt' );
    my $app_capture = File::Spec->catfile( $tmp, 'app-server-capture.txt' );

    my $index_html = File::Spec->catfile( $app_dir, 'index.html' );
    open my $index_fh, '>', $index_html or die $!;
    print {$index_fh} "<!doctype html><title>D2-Codex Test</title>\n";
    close $index_fh or die $!;

    my $app_server = File::Spec->catfile( $bin_dir, 'app-server.pl' );
    open my $app_fh, '>', $app_server or die $!;
    print {$app_fh} <<'PL';
#!/usr/bin/env perl
use strict;
use warnings;
use IO::Socket::INET;

my $capture = $ENV{EVEN_CODEX_E2E_APP_CAPTURE_FILE} or die "capture env required";
open my $cap, '>', $capture or die "Unable to open capture file: $!";
print {$cap} join(' ', @ARGV) . "\n";
close $cap or die "Unable to close capture file: $!";

my $host = $ENV{EVEN_CODEX_E2E_APP_HOST} || '127.0.0.1';
my $port = $ENV{EVEN_CODEX_E2E_APP_PORT} || die "port required";

my $server = IO::Socket::INET->new(
    LocalAddr => $host,
    LocalPort => $port,
    Listen    => 5,
    Proto     => 'tcp',
    ReuseAddr => 1,
) or die "Unable to start app test server: $!";

local $SIG{TERM} = sub { close $server; exit 0 };
local $SIG{INT}  = sub { close $server; exit 0 };

while ( my $client = $server->accept ) {
    while ( defined( my $line = <$client> ) ) {
        last if $line =~ /^\r?\n\z/;
    }
    print {$client} "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n";
    print {$client} "<!doctype html><title>D2-Codex Test</title><body>ok</body>";
    close $client;
}
PL
    close $app_fh or die $!;
    chmod 0755, $app_server or die "Unable to chmod app server: $!";

    my $simulator = File::Spec->catfile( $bin_dir, 'evenhub-simulator' );
    open my $sim_fh, '>', $simulator or die $!;
    print {$sim_fh} <<'SH';
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" > "$EVEN_CODEX_SIM_CAPTURE_FILE"
trap 'exit 0' TERM INT
while :; do
  sleep 1
done
SH
    close $sim_fh or die $!;
    chmod 0755, $simulator or die "Unable to chmod simulator stub: $!";

    my %env = (
        WORKSPACE_REF                    => 'foobar',
        EVEN_CODEX_CONFIG_ROOT          => $config_root,
        EVEN_CODEX_RUNTIME_ROOT         => $runtime_root,
        EVEN_CODEX_PORT                 => $bridge_port,
        EVEN_CODEX_E2E_APP_PORT         => $app_port,
        EVEN_CODEX_E2E_APP_DIR          => $app_dir,
        EVEN_CODEX_E2E_BUILD_MODE       => 'skip',
        EVEN_CODEX_E2E_APP_SERVER_BIN   => $app_server,
        EVEN_CODEX_E2E_APP_SERVER_CMD   => 'exec "$EVEN_CODEX_E2E_APP_SERVER_BIN" --serve "$EVEN_CODEX_E2E_APP_DIR"',
        EVEN_CODEX_E2E_APP_CAPTURE_FILE => $app_capture,
        EVEN_CODEX_SIMULATOR_BIN        => $simulator,
        EVEN_CODEX_SIM_CAPTURE_FILE     => $sim_capture,
        EVEN_CODEX_SIMULATOR_PORT       => 9988,
    );

    my ( $add_rc, $add_output ) = run_start_add( \%env, 'codex-session-901' );
    is( $add_rc, 0, "pairing command exits cleanly\n$add_output" );

    my ( $start_rc, $start_output ) = run_cli( \%env, 'start' );
    is( $start_rc, 0, "e2e start exits cleanly\n$start_output" );
    ok( length $start_output, 'start returns JSON output' ) or diag('start output was empty');
    my $start_payload = length $start_output ? decode_json($start_output) : {};
    is( $start_payload->{action}, 'start', 'start reports the start action' );
    is( $start_payload->{status}, 'started', 'start reports started status' );
    like( $start_payload->{bridge_url}, qr{:\Q$bridge_port\E\z}, 'start reports the bridge URL' );
    is( $start_payload->{app_url}, "http://127.0.0.1:$app_port", 'start reports the app URL' );
    is( $start_payload->{simulator_url}, "http://127.0.0.1:$app_port", 'start reports the simulator URL' );
    ok( $start_payload->{bridge_pid} > 0, 'start reports a bridge pid' );
    ok( $start_payload->{app_pid} > 0, 'start reports an app pid' );
    ok( -f $start_payload->{bridge_pid_file}, 'start writes a bridge pid file' );
    ok( -f $start_payload->{app_pid_file}, 'start writes an app pid file' );

    my $bootstrap = decode_json( http_get( $start_payload->{bootstrap_url} ) );
    is( $bootstrap->{workspace_ref}, 'foobar', 'bridge bootstrap exposes the workspace ref' );
    is( $bootstrap->{codex_session_id}, 'codex-session-901', 'bridge bootstrap exposes the Codex session id' );

    my $simulator_args = slurp($sim_capture);
    like( $simulator_args, qr{\Qhttp://127.0.0.1:$app_port\E}, 'simulator receives the app URL' );
    like( $simulator_args, qr{--automation-port 9988}, 'simulator receives the automation port' );

    my $app_args = slurp($app_capture);
    like( $app_args, qr{--serve}, 'app server command receives the serve marker' );
    like( $app_args, qr{\Q$app_dir\E}, 'app server command receives the app dir' );

    my ( $stop_rc, $stop_output ) = run_cli( \%env, 'stop' );
    is( $stop_rc, 0, "e2e stop exits cleanly\n$stop_output" );
    ok( length $stop_output, 'stop returns JSON output' ) or diag('stop output was empty');
    my $stop_payload = length $stop_output ? decode_json($stop_output) : {};
    is( $stop_payload->{action}, 'stop', 'stop reports the stop action' );
    is( $stop_payload->{status}, 'stopped', 'stop reports stopped status' );
    ok( !-f $start_payload->{bridge_pid_file}, 'stop removes the bridge pid file' );
    ok( !-f $start_payload->{app_pid_file}, 'stop removes the app pid file' );

    my ( $stop_again_rc, $stop_again_output ) = run_cli( \%env, 'stop' );
    is( $stop_again_rc, 0, "repeat e2e stop stays clean\n$stop_again_output" );
    ok( length $stop_again_output, 'repeat stop returns JSON output' ) or diag('repeat stop output was empty');
    my $stop_again_payload = length $stop_again_output ? decode_json($stop_again_output) : {};
    is( $stop_again_payload->{status}, 'not-running', 'repeat stop reports not-running' );
}

done_testing;
