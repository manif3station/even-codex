use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
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
    my @pairs = map { $_ . '=' . _shell_quote( $env->{$_} ) } sort keys %{$env};
    my $command = join q{ }, @pairs, _shell_quote('./cli/simulator'), map { _shell_quote($_) } @argv;
    my $output = qx{cd . && env -i PATH="$ENV{PATH}" HOME="$ENV{HOME}" sh -lc '$command' 2>&1};
    my $rc = $? >> 8;
    return ( $rc, $output );
}

sub run_start_add {
    my ( $env, $session_id ) = @_;
    my @pairs = map { $_ . '=' . _shell_quote( $env->{$_} ) } sort keys %{$env};
    my $command = join q{ }, @pairs, _shell_quote('./cli/start'), 'add', _shell_quote($session_id);
    my $output = qx{cd . && env -i PATH="$ENV{PATH}" HOME="$ENV{HOME}" sh -lc '$command' 2>&1};
    my $rc = $? >> 8;
    return ( $rc, $output );
}

sub _shell_quote {
    my ($value) = @_;
    $value = q{} if !defined $value;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $runtime_root = File::Spec->catdir( $tmp, 'runtime' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path($bin_dir);

    my $docker_capture = File::Spec->catfile( $tmp, 'docker-capture.txt' );
    my $docker_stub = File::Spec->catfile( $bin_dir, 'docker' );
    open my $docker_fh, '>', $docker_stub or die $!;
    print {$docker_fh} <<'SH';
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$EVEN_CODEX_DOCKER_CAPTURE_FILE"
if [ "${1:-}" = "compose" ] && [ "${2:-}" = "-f" ]; then
  for arg in "$@"; do
    if [ "$arg" = "ps" ] && [ -f "$EVEN_CODEX_SIMULATOR_ENV_FILE" ]; then
      printf 'even-codex-simulator-simulator-1\n'
      exit 0
    fi
  done
fi
exit 0
SH
    close $docker_fh or die $!;
    chmod 0755, $docker_stub or die "Unable to chmod docker stub: $!";

    my %env = (
        WORKSPACE_REF                    => 'foobar',
        EVEN_CODEX_CONFIG_ROOT          => $config_root,
        EVEN_CODEX_RUNTIME_ROOT         => $runtime_root,
        EVEN_CODEX_DOCKER_BIN           => $docker_stub,
        EVEN_CODEX_DOCKER_CAPTURE_FILE  => $docker_capture,
        EVEN_CODEX_SIMULATOR_MODE       => 'docker',
        EVEN_CODEX_SIMULATOR_ENV_FILE   => File::Spec->catfile( $runtime_root, 'simulator-docker', 'simulator.env' ),
        EVEN_CODEX_SIMULATOR_NOVNC_PORT => 15700,
        EVEN_CODEX_SIMULATOR_VNC_PORT   => 15900,
        EVEN_CODEX_WORKSPACE_PATH       => '/tmp/foobar-workspace',
        EVEN_CODEX_SIMULATOR_CONNECTOR_MODE => 'api',
        EVEN_CODEX_SIMULATOR_API_KEY       => 'even-codex-connector',
        EVEN_CODEX_SIMULATOR_API_SECRET    => 'simulator-secret',
    );

    my ( $add_rc, $add_output ) = run_start_add( \%env, 'codex-session-444' );
    is( $add_rc, 0, "pairing command exits cleanly\n$add_output" );

    my ( $start_rc, $start_output ) = run_cli( \%env, 'start' );
    is( $start_rc, 0, "docker simulator start exits cleanly\n$start_output" );
    my $start_payload = decode_json($start_output);
    is( $start_payload->{action}, 'start', 'start reports the start action' );
    is( $start_payload->{status}, 'started', 'start reports started status' );
    is( $start_payload->{mode}, 'docker', 'start reports docker mode' );
    is( $start_payload->{workspace_ref}, 'foobar', 'start reports the active workspace ref' );
    is( $start_payload->{codex_session_id}, 'codex-session-444', 'start reports the active Codex session id' );
    is( $start_payload->{novnc_port}, 15700, 'start reports the noVNC host port' );
    like( $start_payload->{novnc_url}, qr{http://127\.0\.0\.1:15700/}, 'start reports the browser-viewable noVNC URL' );
    ok( -f $start_payload->{env_file}, 'start writes a compose env file' );

    my $env_file = slurp( $start_payload->{env_file} );
    like( $env_file, qr/^EVEN_CODEX_WORKSPACE_REF=foobar$/m, 'env file carries the workspace ref' );
    like( $env_file, qr/^EVEN_CODEX_CODEX_SESSION_ID=codex-session-444$/m, 'env file carries the session id' );
    like( $env_file, qr/^EVEN_CODEX_WORKSPACE_PATH=\/tmp\/foobar-workspace$/m, 'env file carries the active workspace path' );
    like( $env_file, qr/^EVEN_CODEX_NOVNC_PORT=15700$/m, 'env file carries the noVNC port' );
    like( $env_file, qr/^EVEN_CODEX_HOST_UID=\d+$/m, 'env file carries the host uid for the runtime user mapping' );
    like( $env_file, qr/^EVEN_CODEX_HOST_GID=\d+$/m, 'env file carries the host gid for the runtime user mapping' );
    like( $env_file, qr/^EVEN_CODEX_CONNECTOR_MODE=api$/m, 'env file carries the simulator connector auth mode' );
    like( $env_file, qr/^EVEN_CODEX_CONNECTOR_API_KEY=even-codex-connector$/m, 'env file carries the fixed simulator DD API key' );
    like( $env_file, qr/^EVEN_CODEX_CONNECTOR_API_SECRET=simulator-secret$/m, 'env file carries the simulator DD API secret' );

    my $docker_commands = slurp($docker_capture);
    like( $docker_commands, qr/compose .*docker-compose\.simulator\.yml .* up -d --build/, 'start shells out to docker compose up with build' );

    my ( $again_rc, $again_output ) = run_cli( \%env, 'start' );
    is( $again_rc, 0, 'docker simulator start is idempotent while state exists' );
    my $again_payload = decode_json($again_output);
    is( $again_payload->{status}, 'already-running', 'repeat start reports already-running status' );

    my ( $stop_rc, $stop_output ) = run_cli( \%env, 'stop' );
    is( $stop_rc, 0, "docker simulator stop exits cleanly\n$stop_output" );
    my $stop_payload = decode_json($stop_output);
    is( $stop_payload->{action}, 'stop', 'stop reports the stop action' );
    is( $stop_payload->{status}, 'stopped', 'stop reports stopped status' );
    ok( !-f $start_payload->{env_file}, 'stop removes the compose env file' );

    $docker_commands = slurp($docker_capture);
    like( $docker_commands, qr/compose .*docker-compose\.simulator\.yml .* down/, 'stop shells out to docker compose down' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $runtime_root = File::Spec->catdir( $tmp, 'runtime' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path($bin_dir);

    my $docker_capture = File::Spec->catfile( $tmp, 'docker-capture.txt' );
    my $docker_stub = File::Spec->catfile( $bin_dir, 'docker' );
    open my $docker_fh, '>', $docker_stub or die $!;
    print {$docker_fh} <<'SH';
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$EVEN_CODEX_DOCKER_CAPTURE_FILE"
if [ "${1:-}" = "compose" ] && [ "${2:-}" = "-f" ]; then
  for arg in "$@"; do
    if [ "$arg" = "ps" ]; then
      exit 0
    fi
  done
fi
exit 0
SH
    close $docker_fh or die $!;
    chmod 0755, $docker_stub or die "Unable to chmod docker stub: $!";

    my %env = (
        WORKSPACE_REF                    => 'foobar',
        EVEN_CODEX_CONFIG_ROOT          => $config_root,
        EVEN_CODEX_RUNTIME_ROOT         => $runtime_root,
        EVEN_CODEX_DOCKER_BIN           => $docker_stub,
        EVEN_CODEX_DOCKER_CAPTURE_FILE  => $docker_capture,
        EVEN_CODEX_SIMULATOR_MODE       => 'docker',
        EVEN_CODEX_SIMULATOR_ENV_FILE   => File::Spec->catfile( $runtime_root, 'simulator-docker', 'simulator.env' ),
        EVEN_CODEX_SIMULATOR_NOVNC_PORT => 15700,
        EVEN_CODEX_SIMULATOR_VNC_PORT   => 15900,
        EVEN_CODEX_WORKSPACE_PATH       => '/tmp/foobar-workspace',
    );

    my ( $add_rc, $add_output ) = run_start_add( \%env, 'codex-session-445' );
    is( $add_rc, 0, "pairing command exits cleanly for stale-state recovery\n$add_output" );

    my $docker_root = File::Spec->catdir( $runtime_root, 'simulator-docker' );
    make_path($docker_root);
    my $state_file = File::Spec->catfile( $docker_root, 'state.json' );
    open my $state_fh, '>', $state_file or die $!;
    print {$state_fh} qq|{"project_name":"even-codex-simulator"}\n|;
    close $state_fh or die $!;

    my ( $start_rc, $start_output ) = run_cli( \%env, 'start' );
    is( $start_rc, 0, "docker simulator start recovers from stale state files\n$start_output" );
    my $start_payload = decode_json($start_output);
    is( $start_payload->{status}, 'started', 'stale simulator state is cleared instead of reporting already-running' );

    my $docker_commands = slurp($docker_capture);
    like( $docker_commands, qr/compose .*docker-compose\.simulator\.yml .* up -d --build/, 'stale-state recovery starts a fresh compose stack after clearing dead state' );
}

done_testing;
