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

sub _shell_quote {
    my ($value) = @_;
    $value = q{} if !defined $value;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $runtime_root = File::Spec->catdir( $tmp, 'runtime' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path($bin_dir);
    my $capture_file = File::Spec->catfile( $tmp, 'capture.txt' );
    my $stub_bin = File::Spec->catfile( $bin_dir, 'evenhub-simulator' );

    open my $stub_fh, '>', $stub_bin or die $!;
    print {$stub_fh} <<'SH';
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" > "$EVEN_CODEX_SIM_CAPTURE_FILE"
trap 'exit 0' TERM INT
while :; do
  sleep 1
done
SH
    close $stub_fh or die $!;
    chmod 0755, $stub_bin or die "Unable to chmod stub simulator: $!";

    my %env = (
        EVEN_CODEX_SIMULATOR_MODE    => 'local',
        EVEN_CODEX_SIMULATOR_BIN     => $stub_bin,
        EVEN_CODEX_SIMULATOR_URL     => 'http://127.0.0.1:4173',
        EVEN_CODEX_SIMULATOR_PORT    => 9898,
        EVEN_CODEX_RUNTIME_ROOT      => $runtime_root,
        EVEN_CODEX_SIM_CAPTURE_FILE  => $capture_file,
    );

    my ( $start_rc, $start_output ) = run_cli( \%env, 'start' );
    is( $start_rc, 0, 'simulator start exits cleanly' );
    my $start_payload = decode_json($start_output);
    is( $start_payload->{action}, 'start', 'start reports the start action' );
    is( $start_payload->{simulator_url}, 'http://127.0.0.1:4173', 'start reports the target URL' );
    is( $start_payload->{automation_port}, 9898, 'start reports the automation port' );
    ok( $start_payload->{pid} > 0, 'start reports a running pid' );
    ok( -f $start_payload->{pid_file}, 'start writes a pid file' );
    ok( -f $start_payload->{log_file}, 'start writes a log file path' );

    my $captured = slurp($capture_file);
    like( $captured, qr{http://127\.0\.0\.1:4173}, 'start passes the target URL to the simulator' );
    like( $captured, qr{--automation-port 9898}, 'start passes the automation port to the simulator' );

    my ( $again_rc, $again_output ) = run_cli( \%env, 'start' );
    is( $again_rc, 0, 'simulator start is idempotent while already running' );
    my $again_payload = decode_json($again_output);
    is( $again_payload->{action}, 'start', 'repeat start still reports the start action' );
    is( $again_payload->{status}, 'already-running', 'repeat start reports already-running status' );
    is( $again_payload->{pid}, $start_payload->{pid}, 'repeat start returns the same pid' );

    my ( $stop_rc, $stop_output ) = run_cli( \%env, 'stop' );
    is( $stop_rc, 0, 'simulator stop exits cleanly' );
    my $stop_payload = decode_json($stop_output);
    is( $stop_payload->{action}, 'stop', 'stop reports the stop action' );
    is( $stop_payload->{status}, 'stopped', 'stop reports stopped status' );
    ok( !-f $start_payload->{pid_file}, 'stop removes the pid file' );

    my ( $stop_again_rc, $stop_again_output ) = run_cli( \%env, 'stop' );
    is( $stop_again_rc, 0, 'simulator stop stays clean when nothing is running' );
    my $stop_again_payload = decode_json($stop_again_output);
    is( $stop_again_payload->{status}, 'not-running', 'repeat stop reports not-running status' );
}

done_testing;
