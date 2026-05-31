use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';
use Even::Codex::Manager;
use Even::Codex::State;

sub capture_run {
    my ( $code_ref ) = @_;
    my $stdout = q{};
    my $stderr = q{};
    open my $out_fh, '>', \$stdout or die $!;
    open my $err_fh, '>', \$stderr or die $!;
    my $rc = $code_ref->( $out_fh, $err_fh );
    return ( $rc, $stdout, $stderr );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    EVEN_CODEX_CONFIG_ROOT => File::Spec->catdir( $tmp, 'config' ),
                },
            );
            return $manager->main_start( 'add', 'codex-session-1' );
        }
    );
    is( $rc, 2, 'main_start add fails without a workspace ref' );
    is( $stdout, q{}, 'main_start add keeps stdout empty on failure' );
    like( $stderr, qr/WORKSPACE_REF or TICKET_REF is required/, 'main_start add explains the missing workspace ref' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    WORKSPACE_REF           => 'foobar',
                    EVEN_CODEX_CONFIG_ROOT  => $config_root,
                },
            );
            return $manager->main_start( 'add', 'codex-session-1' );
        }
    );
    is( $rc, 0, 'main_start add succeeds when a workspace ref is present' );
    is( $stderr, q{}, 'main_start add leaves stderr empty on success' );
    my $payload = decode_json($stdout);
    is( $payload->{action}, 'add', 'main_start add reports the add action' );
    is( $payload->{workspace_ref}, 'foobar', 'main_start add reports the workspace ref' );
    is( $payload->{codex_session_id}, 'codex-session-1', 'main_start add reports the Codex session id' );
    is(
        Even::Codex::State::load_pairing(
            env           => { EVEN_CODEX_CONFIG_ROOT => $config_root },
            workspace_ref => 'foobar',
        ),
        'codex-session-1',
        'main_start add persists the workspace pairing'
    );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    Even::Codex::State::save_pairing(
        env              => { EVEN_CODEX_CONFIG_ROOT => $config_root },
        workspace_ref    => 'foobar',
        codex_session_id => 'codex-session-9',
    );

    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    WORKSPACE_REF            => 'foobar',
                    EVEN_CODEX_CONFIG_ROOT   => $config_root,
                    EVEN_CODEX_HOST          => '0.0.0.0',
                    EVEN_CODEX_PORT          => 6789,
                    EVEN_CODEX_ADVERTISE_HOST => '192.168.1.20',
                    EVEN_CODEX_START_CAPTURE => 1,
                },
            );
            return $manager->main_start();
        }
    );
    is( $rc, 0, 'main_start capture mode returns a connector plan' );
    is( $stderr, q{}, 'main_start capture mode leaves stderr empty' );
    my $payload = decode_json($stdout);
    is( $payload->{action}, 'serve', 'main_start capture mode reports the serve action' );
    is( $payload->{bind_host}, '0.0.0.0', 'main_start capture mode reports the bind host' );
    is( $payload->{advertised_host}, '192.168.1.20', 'main_start capture mode reports the advertised host' );
    is( $payload->{port}, 6789, 'main_start capture mode reports the default Even bridge port' );
    is( $payload->{workspace_ref}, 'foobar', 'main_start capture mode reports the workspace ref' );
    is( $payload->{codex_session_id}, 'codex-session-9', 'main_start capture mode reports the paired session id' );
    is( $payload->{plugin_url}, 'http://192.168.1.20:6789/plugin/', 'main_start capture mode reports the plugin URL' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    WORKSPACE_REF            => 'foobar',
                    EVEN_CODEX_CONFIG_ROOT   => File::Spec->catdir( $tmp, 'config' ),
                    EVEN_CODEX_START_CAPTURE => 1,
                },
            );
            return $manager->main_start();
        }
    );
    is( $rc, 2, 'main_start capture mode fails when the workspace is not paired' );
    is( $stdout, q{}, 'main_start capture mode keeps stdout empty on failure' );
    like( $stderr, qr/No even-codex pairing exists for workspace foobar/, 'main_start capture mode explains the missing pairing' );
}

done_testing;
