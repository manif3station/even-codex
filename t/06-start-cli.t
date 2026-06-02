use strict;
use warnings;

use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json encode_json);
use Test::More;

use lib 'lib';
use Even::Codex::Manager;
use Even::Codex::State;

sub capture_run {
    my ($code_ref) = @_;
    my $stdout = q{};
    my $stderr = q{};
    open my $out_fh, '>', \$stdout or die $!;
    open my $err_fh, '>', \$stderr or die $!;
    my $rc = $code_ref->( $out_fh, $err_fh );
    return ( $rc, $stdout, $stderr );
}

sub write_fake_dashboard {
    my (%args) = @_;
    my $bin_dir = $args{bin_dir};
    my $log_path = $args{log_path};
    my $json_payload = encode_json( $args{json_payload} );
    my $exit_code = defined $args{exit_code} ? $args{exit_code} : 0;
    my $stderr_text = defined $args{stderr_text} ? $args{stderr_text} : q{};
    my $stdout_text = defined $args{stdout_text} ? $args{stdout_text} : q{};
    my $script_path = File::Spec->catfile( $bin_dir, 'fake-dashboard-api' );

    open my $fh, '>', $script_path or die "Unable to write $script_path: $!";
    print {$fh} <<"SH";
#!/usr/bin/env bash
set -eu
printf '%s\\n' "\$@" > "$log_path"
SH
    if ( $stderr_text ne q{} ) {
        print {$fh} "printf '%s' " . _shell_quote($stderr_text) . " >&2\n";
    }
    if ( defined $args{stdout_text} ) {
        print {$fh} "printf '%s' " . _shell_quote($stdout_text) . "\n";
    } else {
        print {$fh} "printf '%s' " . _shell_quote($json_payload) . "\n";
    }
    print {$fh} "exit $exit_code\n";
    close $fh or die "Unable to close $script_path: $!";
    chmod 0755, $script_path or die "Unable to chmod $script_path: $!";
    return $script_path;
}

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return $text;
}

sub _shell_quote {
    my ($value) = @_;
    $value =~ s/'/'"'"'/g;
    return q{'} . $value . q{'};
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
                    WORKSPACE_REF          => 'foobar',
                    EVEN_CODEX_CONFIG_ROOT => $config_root,
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
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => {
            action  => 'add',
            changed => 1,
            file    => File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ),
            key     => 'even-codex-connector',
        },
    );
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
                    HOME                      => $tmp,
                    WORKSPACE_REF             => 'foobar',
                    EVEN_CODEX_CONFIG_ROOT    => $config_root,
                    EVEN_CODEX_HOST           => '0.0.0.0',
                    EVEN_CODEX_PORT           => 6789,
                    EVEN_CODEX_ADVERTISE_HOST => '192.168.1.20',
                    EVEN_CODEX_START_CAPTURE  => 1,
                    EVEN_CODEX_DASHBOARD_BIN  => $script_path,
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
    is( $payload->{dd_api_client_name}, 'even-codex-connector', 'main_start capture mode uses the fixed DD API connector key name' );
    is( $payload->{dd_api_entry_status}, 'updated', 'main_start capture mode reports a changed DD API bootstrap result as updated' );
    is( $payload->{dd_api_secret_available}, 1, 'main_start capture mode always exposes the connector API secret it bootstrapped' );
    is( $payload->{dd_api_secret}, '0000', 'main_start capture mode defaults the connector API secret to 0000' );
    is(
        $payload->{dd_api_config_path},
        File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ),
        'main_start capture mode reports the DD API config path from dashboard api add',
    );

    is(
        slurp($log_path),
        join(
            "\n",
            'api',
            'add',
            '--key',
            'even-codex-connector',
            '--maybe-secret',
            '0000',
            '--route',
            '/ajax/even-codex/bootstrap',
            '--route',
            '/ajax/even-codex/health',
            '--route',
            '/ajax/even-codex/prompt',
            '--route',
            '/ajax/even-codex/session',
            '-o',
            'json',
            q{},
        ),
        'main_start capture mode shells out through dashboard api add with the fixed even-codex connector contract',
    );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => {
            action  => 'add',
            changed => 0,
            file    => File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ),
            key     => 'even-codex-connector',
        },
    );
    Even::Codex::State::save_pairing(
        env              => { EVEN_CODEX_CONFIG_ROOT => $config_root },
        workspace_ref    => 'foobar',
        codex_session_id => 'codex-session-10',
    );

    my $manager = Even::Codex::Manager->new(
        env => {
            HOME                           => $tmp,
            EVEN_CODEX_CONFIG_ROOT         => $config_root,
            EVEN_CODEX_DASHBOARD_BIN       => $script_path,
            EVEN_CODEX_CONNECTOR_API_SECRET => 'rotated-secret',
        },
    );
    my $client = $manager->ensure_dd_api_client;
    is( $client->{client_name}, 'even-codex-connector', 'ensure_dd_api_client keeps the fixed DD API connector key name' );
    is( $client->{status}, 'unchanged', 'ensure_dd_api_client reports no-change dashboard api bootstrap results as unchanged' );
    is( $client->{raw_secret}, 'rotated-secret', 'ensure_dd_api_client honors an explicit connector API secret override' );
    like( slurp($log_path), qr/\Qrotated-secret\E/, 'ensure_dd_api_client passes the explicit connector API secret override through dashboard api add' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => {
            action  => 'add',
            changed => 0,
            file    => File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ),
            key     => 'even-codex-connector',
        },
    );

    my $manager = Even::Codex::Manager->new(
        env => {
            HOME                            => $tmp,
            EVEN_CODEX_DASHBOARD_BIN        => $script_path,
            EVEN_CODEX_CONNECTOR_API_SECRET => q{},
        },
    );
    my $client = $manager->ensure_dd_api_client;
    is( $client->{raw_secret}, '0000', 'ensure_dd_api_client falls back to the governed default secret when the override is empty' );
    like( slurp($log_path), qr/\Q0000\E/, 'ensure_dd_api_client passes the governed default secret when the override is empty' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => {
            action  => 'add',
            changed => 0,
            file    => File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ),
            key     => 'even-codex-connector',
        },
    );
    my $dashboard_path = File::Spec->catfile( $bin_dir, 'dashboard' );
    rename $script_path, $dashboard_path or die "Unable to rename $script_path to $dashboard_path: $!";

    local $ENV{PATH} = $bin_dir . q{:} . ( $ENV{PATH} // q{} );
    my $manager = Even::Codex::Manager->new(
        env => {
            HOME => $tmp,
        },
    );
    my $client = $manager->ensure_dd_api_client;
    is( $client->{client_name}, 'even-codex-connector', 'ensure_dd_api_client finds the default dashboard command name on PATH when no override is set' );
    is( slurp($log_path), "api\nadd\n--key\neven-codex-connector\n--maybe-secret\n0000\n--route\n/ajax/even-codex/bootstrap\n--route\n/ajax/even-codex/health\n--route\n/ajax/even-codex/prompt\n--route\n/ajax/even-codex/session\n-o\njson\n", 'ensure_dd_api_client shells out through the default dashboard command name when no override is set' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => {
            action  => 'add',
            changed => 0,
            file    => q{},
            key     => q{},
        },
    );

    my $manager = Even::Codex::Manager->new(
        env => {
            HOME                     => $tmp,
            EVEN_CODEX_DASHBOARD_BIN => q{},
        },
    );

    local $ENV{PATH} = $bin_dir . q{:} . ( $ENV{PATH} // q{} );
    rename $script_path, File::Spec->catfile( $bin_dir, 'dashboard' ) or die "Unable to install fake dashboard on PATH: $!";
    my $client = $manager->ensure_dd_api_client;
    is( $client->{client_name}, 'even-codex-connector', 'ensure_dd_api_client falls back to the fixed key name when dashboard api add returns an empty key' );
    is(
        $client->{config_path},
        File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ),
        'ensure_dd_api_client falls back to the default DD api.json path when dashboard api add returns an empty file path',
    );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => {
            action  => 'add',
            changed => 1,
        },
    );

    my $manager = Even::Codex::Manager->new(
        env => {
            HOME                     => $tmp,
            EVEN_CODEX_DASHBOARD_BIN => $script_path,
        },
    );
    my $client = $manager->ensure_dd_api_client;
    is( $client->{client_name}, 'even-codex-connector', 'ensure_dd_api_client falls back to the fixed key name when dashboard api add omits it' );
    is(
        $client->{config_path},
        File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ),
        'ensure_dd_api_client falls back to the default DD api.json path when dashboard api add omits it',
    );
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

{
    my $error = eval {
        my $manager = Even::Codex::Manager->new( env => {} );
        $manager->ensure_dd_api_client;
        1;
    } ? q{} : $@;
    like( $error, qr/HOME is required/, 'ensure_dd_api_client requires HOME when it shells out through dashboard api' );
}

{
    my $error = eval {
        my $manager = Even::Codex::Manager->new( env => { HOME => q{} } );
        $manager->ensure_dd_api_client;
        1;
    } ? q{} : $@;
    like( $error, qr/HOME is required/, 'ensure_dd_api_client rejects an empty HOME value' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => { changed => 0 },
        stdout_text  => '{"broken":',
    );

    my $error = eval {
        my $manager = Even::Codex::Manager->new(
            env => {
                HOME                    => $tmp,
                EVEN_CODEX_DASHBOARD_BIN => $script_path,
            },
        );
        $manager->ensure_dd_api_client;
        1;
    } ? q{} : $@;
    like( $error, qr/dashboard api add returned invalid JSON/, 'ensure_dd_api_client fails clearly when dashboard api add does not return valid JSON' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => { changed => 0 },
        stdout_text  => '[]',
    );

    my $error = eval {
        my $manager = Even::Codex::Manager->new(
            env => {
                HOME                     => $tmp,
                EVEN_CODEX_DASHBOARD_BIN => $script_path,
            },
        );
        $manager->ensure_dd_api_client;
        1;
    } ? q{} : $@;
    like( $error, qr/dashboard api add returned invalid JSON/, 'ensure_dd_api_client also rejects valid JSON payloads that are not JSON objects' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    my $log_path = File::Spec->catfile( $tmp, 'dashboard-api.log' );
    require File::Path;
    File::Path::make_path($bin_dir);
    my $script_path = write_fake_dashboard(
        bin_dir      => $bin_dir,
        log_path     => $log_path,
        json_payload => { changed => 0 },
        exit_code    => 9,
        stderr_text  => "simulated dashboard api failure\n",
        stdout_text  => "dashboard api failure body\n",
    );

    my $error = eval {
        my $manager = Even::Codex::Manager->new(
            env => {
                HOME                    => $tmp,
                EVEN_CODEX_DASHBOARD_BIN => $script_path,
            },
        );
        $manager->ensure_dd_api_client;
        1;
    } ? q{} : $@;
    like( $error, qr/dashboard api add failed/, 'ensure_dd_api_client fails clearly when dashboard api add exits non-zero' );
    like( $error, qr/simulated dashboard api failure/, 'ensure_dd_api_client includes dashboard api stderr on failure' );
    like( $error, qr/dashboard api failure body/, 'ensure_dd_api_client includes dashboard api stdout on failure' );
}

done_testing;
