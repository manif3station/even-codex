use strict;
use warnings FATAL => 'all';

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use IO::Socket::INET;
use JSON::PP qw(decode_json);
use Test::More;
use Time::HiRes qw(sleep);

use lib 'lib';
use Even::Codex::Manager;
use Even::Codex::Plugin;
use Even::Codex::Sender;
use Even::Codex::Server;
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

sub write_fake_dashboard_api {
    my (%args) = @_;
    my $bin_dir = $args{bin_dir};
    my $script_path = File::Spec->catfile( $bin_dir, 'fake-dashboard-api' );
    my $payload = $args{payload};
    open my $fh, '>', $script_path or die "Unable to write $script_path: $!";
    print {$fh} <<"SH";
#!/usr/bin/env bash
set -eu
cat <<'JSON'
$payload
JSON
SH
    close $fh or die "Unable to close $script_path: $!";
    chmod 0755, $script_path or die "Unable to chmod $script_path: $!";
    return $script_path;
}

{
    my $home = tempdir( CLEANUP => 1 );
    local $ENV{HOME} = $home;
    is(
        Even::Codex::State::config_root( env => { HOME => $home } ),
        File::Spec->catdir( $home, '.developer-dashboard', 'configs', 'even-codex' ),
        'config_root falls back to the default HOME-based path'
    );
    is(
        Even::Codex::State::config_root( env => { HOME => $home, EVEN_CODEX_CONFIG_ROOT => q{} } ),
        File::Spec->catdir( $home, '.developer-dashboard', 'configs', 'even-codex' ),
        'config_root ignores an empty override'
    );
    is(
        Even::Codex::State::runtime_root( env => { HOME => $home } ),
        File::Spec->catdir( $home, '.developer-dashboard', 'state', 'even-codex' ),
        'runtime_root falls back to the default HOME-based path'
    );
    is(
        Even::Codex::State::runtime_root( env => { HOME => $home, EVEN_CODEX_RUNTIME_ROOT => q{} } ),
        File::Spec->catdir( $home, '.developer-dashboard', 'state', 'even-codex' ),
        'runtime_root ignores an empty override'
    );
    is(
        Even::Codex::State::runtime_root( env => { HOME => $home, EVEN_CODEX_RUNTIME_ROOT => '/tmp/even-runtime' } ),
        '/tmp/even-runtime',
        'runtime_root accepts a non-empty explicit override'
    );
    is(
        Even::Codex::State::config_root(),
        File::Spec->catdir( $home, '.developer-dashboard', 'configs', 'even-codex' ),
        'config_root also works without an explicit env hash'
    );
    is(
        Even::Codex::State::runtime_root(),
        File::Spec->catdir( $home, '.developer-dashboard', 'state', 'even-codex' ),
        'runtime_root also works without an explicit env hash'
    );
}

{
    my $error = eval { Even::Codex::State::config_root( env => {} ); 1 };
    ok( !$error, 'config_root dies without HOME or override' );
    like( $@, qr/HOME is required/, 'config_root explains the missing HOME' );
}

{
    my $error = eval { Even::Codex::State::runtime_root( env => {} ); 1 };
    ok( !$error, 'runtime_root dies without HOME or override' );
    like( $@, qr/HOME is required/, 'runtime_root explains the missing HOME' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    make_path($config_root);
    my $pairings = File::Spec->catfile( $config_root, 'workspace-pairings.json' );
    open my $fh, '>', $pairings or die $!;
    print {$fh} "[]";
    close $fh or die $!;
    is_deeply(
        Even::Codex::State::load_pairings( env => { EVEN_CODEX_CONFIG_ROOT => $config_root } ),
        {},
        'load_pairings normalises non-hash JSON payloads to an empty hash'
    );
}

{
    my $error = eval { Even::Codex::State::save_pairing( workspace_ref => q{}, codex_session_id => 'session-x' ); 1 };
    ok( !$error, 'save_pairing rejects an empty workspace ref' );
    like( $@, qr/Workspace ref is required/, 'save_pairing explains the missing workspace ref' );
}

{
    my $error = eval { Even::Codex::State::save_pairing( codex_session_id => 'session-x' ); 1 };
    ok( !$error, 'save_pairing rejects an undefined workspace ref' );
    like( $@, qr/Workspace ref is required/, 'save_pairing explains the undefined workspace ref' );
}

{
    my $error = eval { Even::Codex::State::save_pairing( workspace_ref => 'foobar', codex_session_id => q{} ); 1 };
    ok( !$error, 'save_pairing rejects an empty Codex session id' );
    like( $@, qr/Codex session id is required/, 'save_pairing explains the missing Codex session id' );
}

{
    my $error = eval { Even::Codex::State::save_pairing( workspace_ref => 'foobar' ); 1 };
    ok( !$error, 'save_pairing rejects an undefined Codex session id' );
    like( $@, qr/Codex session id is required/, 'save_pairing explains the undefined Codex session id' );
}

{
    my $error = eval { Even::Codex::State::load_pairing( workspace_ref => q{} ); 1 };
    ok( !$error, 'load_pairing rejects an empty workspace ref' );
    like( $@, qr/Workspace ref is required/, 'load_pairing explains the missing workspace ref' );
}

{
    my $error = eval { Even::Codex::State::load_pairing(); 1 };
    ok( !$error, 'load_pairing rejects an undefined workspace ref' );
    like( $@, qr/Workspace ref is required/, 'load_pairing explains the undefined workspace ref' );
}

{
    my $error = eval { Even::Codex::Plugin::asset_path(); 1 };
    ok( !$error, 'asset_path rejects an undefined plugin asset name' );
    like( $@, qr/Plugin asset name is required/, 'asset_path explains the missing asset name' );
}

{
    my $error = eval { Even::Codex::Plugin::asset_path(q{}); 1 };
    ok( !$error, 'asset_path rejects an empty plugin asset name' );
    like( $@, qr/Plugin asset name is required/, 'asset_path explains the empty asset name' );
}

{
    my $error = eval { Even::Codex::Plugin::asset_text('missing.js'); 1 };
    ok( !$error, 'asset_text dies for a missing plugin asset' );
}

{
    for my $case (
        [ { port => 6789, workspace_ref => 'w', codex_session_id => 'c' }, qr/Host is required/, 'host is required' ],
        [ { host => q{}, port => 6789, workspace_ref => 'w', codex_session_id => 'c' }, qr/Host is required/, 'host cannot be empty' ],
        [ { host => '127.0.0.1', workspace_ref => 'w', codex_session_id => 'c' }, qr/Port is required/, 'port is required' ],
        [ { host => '127.0.0.1', port => q{}, workspace_ref => 'w', codex_session_id => 'c' }, qr/Port is required/, 'port cannot be empty' ],
        [ { host => '127.0.0.1', port => 6789, codex_session_id => 'c' }, qr/Workspace ref is required/, 'workspace ref is required' ],
        [ { host => '127.0.0.1', port => 6789, workspace_ref => q{}, codex_session_id => 'c' }, qr/Workspace ref is required/, 'workspace ref cannot be empty' ],
        [ { host => '127.0.0.1', port => 6789, workspace_ref => 'w' }, qr/Codex session id is required/, 'Codex session id is required' ],
        [ { host => '127.0.0.1', port => 6789, workspace_ref => 'w', codex_session_id => q{} }, qr/Codex session id is required/, 'Codex session id cannot be empty' ],
    ) {
        my ( $args, $pattern, $label ) = @{$case};
        my $ok = eval { Even::Codex::Server->new(%{$args}); 1 };
        ok( !$ok, "server constructor rejects missing input: $label" );
        like( $@, $pattern, "server constructor explains missing input: $label" );
    }
}

{
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => 6789,
        workspace_ref    => 'foobar',
        codex_session_id => 'session-1',
    );
    is( $server->bootstrap_payload->{advertised_host}, '127.0.0.1', 'server defaults the advertised host when none is provided' );
}

{
    my $port = _reserve_port();
    my $blocker = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => $port,
        Listen    => 5,
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "Unable to reserve blocker socket: $!";
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => $port,
        workspace_ref    => 'foobar',
        codex_session_id => 'session-2',
    );
    my $ok = eval { $server->serve( max_requests => 1 ); 1 };
    ok( !$ok, 'server serve reports a socket bind failure when the port is already occupied' );
    like( $@, qr/Unable to start even-codex bridge/, 'server serve explains the socket bind failure' );
    close $blocker;
}

{
    my $port = _reserve_port();
    my $pid = fork();
    die "Unable to fork default even-codex server: $!" if !defined $pid;

    if ( $pid == 0 ) {
        my $server = Even::Codex::Server->new(
            host             => '127.0.0.1',
            port             => $port,
            workspace_ref    => 'foobar',
            codex_session_id => 'session-3',
            sender           => Even::Codex::Sender->new(
                ps_lines_provider => sub { return ["pts/3 /opt/codex-cli/bin/codex resume session-3\n"]; },
                tty_writer        => sub { return 1; },
            ),
        );
        $server->serve();
        exit 0;
    }

    _wait_for_port($port);
    my $plugin = _http_get( $port, '/plugin' );
    is( $plugin->{status}, 200, 'server also serves the plugin HTML on /plugin without a trailing slash' );
    my $malformed = _http_request( $port, 'BROKEN', '/plugin', undef, "Header-With-No-Value\r\n" );
    is( $malformed->{status}, 404, 'server ignores malformed request headers and leaves unmatched methods as 404' );
    my $garbled = _raw_http_request( $port, "GARBLED REQUEST\r\nContent-Length: nope\r\n\r\n" );
    is( $garbled->{status}, 404, 'server keeps the default route when the request line is defined but does not match an HTTP method and path pair' );
    my $post = _http_request( $port, 'POST', '/health' );
    is( $post->{status}, 404, 'server treats non-GET requests as unmatched routes' );
    my $bad_prompt = _http_request( $port, 'POST', '/prompt', '{}' );
    is( $bad_prompt->{status}, 400, 'server rejects prompt submissions that omit the query' );
    like( $bad_prompt->{body}, qr/Query is required/, 'server returns a useful prompt validation error' );
    my $bad_json = _http_request( $port, 'POST', '/prompt', '{not-json}' );
    is( $bad_json->{status}, 400, 'server rejects invalid JSON prompt submissions' );
    my $missing = _http_get( $port, '/missing' );
    is( $missing->{status}, 404, 'server returns 404 for unknown routes' );

    kill 'TERM', $pid;
    waitpid $pid, 0;
}

{
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => 6789,
        workspace_ref    => 'foobar',
        codex_session_id => 'session-direct',
        sender           => Even::Codex::Sender->new(
            ps_lines_provider => sub { return ["pts/5 /opt/codex-cli/bin/codex resume session-direct\n"]; },
            tty_writer        => sub { return 1; },
        ),
    );
    is( $server->prompt_payload( query => 'direct prompt' )->{queued_query}, 'direct prompt', 'server prompt_payload exposes queued query data directly' );
    my $empty_query = eval {
        $server->prompt_payload( query => q{} );
        1;
    };
    ok( !$empty_query, 'server prompt_payload rejects an empty query' );
    like( $@, qr/Query is required/, 'server prompt_payload explains an empty query' );
    is( Even::Codex::Server::_status_text(202), 'Accepted', 'server status helper labels HTTP 202' );
    is( Even::Codex::Server::_status_text(400), 'Bad Request', 'server status helper labels HTTP 400' );
    is( Even::Codex::Server::_status_text(404), 'Not Found', 'server status helper labels HTTP 404' );
    my @session_route = $server->_response_for_request( 'GET', '/session', q{} );
    my @plugin_route = $server->_response_for_request( 'GET', '/plugin/', q{} );
    my @manifest_route = $server->_response_for_request( 'GET', '/plugin/manifest.json', q{} );
    my @app_route = $server->_response_for_request( 'GET', '/plugin/app.js', q{} );
    my @style_route = $server->_response_for_request( 'GET', '/plugin/styles.css', q{} );
    is( scalar @session_route, 3, 'server direct session route returns a full response tuple' );
    is( scalar @plugin_route, 3, 'server direct plugin-slash route returns a full response tuple' );
    is( scalar @manifest_route, 3, 'server direct manifest route returns a full response tuple' );
    is( scalar @app_route, 3, 'server direct JavaScript route returns a full response tuple' );
    is( scalar @style_route, 3, 'server direct stylesheet route returns a full response tuple' );

    my @empty_prompt_route;
    my $empty_prompt_ok = eval {
        @empty_prompt_route = $server->_response_for_request( 'POST', '/prompt', q{} );
        1;
    };
    ok( !$empty_prompt_ok, 'server direct prompt route rejects an empty request body once prompt validation runs' );
    like( $@, qr/Query is required/, 'server direct prompt route reports an empty-body query error' );

    my $undef_prompt_ok = eval {
        $server->_response_for_request( 'POST', '/prompt', undef );
        1;
    };
    ok( !$undef_prompt_ok, 'server direct prompt route rejects an undefined request body once prompt validation runs' );
    like( $@, qr/Query is required/, 'server direct prompt route reports an undefined-body query error' );

    my $array_prompt_ok = eval {
        $server->_response_for_request( 'POST', '/prompt', '[]' );
        1;
    };
    ok( !$array_prompt_ok, 'server direct prompt route rejects non-hash JSON payloads' );
    like( $@, qr/Query is required/, 'server direct prompt route reports non-hash JSON payloads clearly' );
}

{
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => 6791,
        workspace_ref    => 'defaults',
        codex_session_id => 'defaults-session',
    );
    isa_ok( $server->{sender}, 'Even::Codex::Sender', 'server constructor creates a default sender when one is not supplied' );
    ok( ref $server->{env} eq 'HASH', 'server constructor falls back to a default env hash when one is not supplied' );
}

{
    my $custom_env = { HOME => '/tmp/even-codex-server-cover' };
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => 6792,
        advertised_host  => q{},
        workspace_ref    => 'env-cover',
        codex_session_id => 'env-session',
        env              => $custom_env,
    );
    is( $server->{advertised_host}, '127.0.0.1', 'server constructor falls back when advertised_host is defined but empty' );
    is( $server->{env}, $custom_env, 'server constructor keeps an explicit env hash when one is supplied' );
}

{
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub { return ["? xterm -e codex resume uncovered\n"]; },
        tty_writer        => sub { return 1; },
    );
    my $missing_tty = eval {
        $sender->find_session_tty( session_id => 'uncovered' );
        1;
    };
    ok( !$missing_tty, 'sender fails when only non-interactive Codex lines are present' );
    like( $@, qr/Unable to find an interactive Codex tty/, 'sender missing-tty error stays explicit' );

    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => 6793,
        workspace_ref    => 'prompt-cover',
        codex_session_id => 'prompt-session',
        sender           => $sender,
    );
    my $missing_query = eval {
        $server->prompt_payload();
        1;
    };
    ok( !$missing_query, 'server prompt_payload rejects an undefined query' );
    like( $@, qr/Query is required/, 'server prompt_payload explains an undefined query' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $env = { EVEN_CODEX_CONFIG_ROOT => $config_root };
    Even::Codex::State::save_pairing(
        env              => $env,
        workspace_ref    => 'existing-dir',
        codex_session_id => 'session-1',
    );
    Even::Codex::State::save_pairing(
        env              => $env,
        workspace_ref    => 'existing-dir',
        codex_session_id => 'session-2',
    );
    is(
        Even::Codex::State::load_pairing(
            env           => $env,
            workspace_ref => 'existing-dir',
        ),
        'session-2',
        'save_pairing also works when the config directory already exists'
    );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path($bin_dir);
    my $dashboard_bin = write_fake_dashboard_api(
        bin_dir => $bin_dir,
        payload => qq|{"action":"add","changed":1,"file":"@{[ File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ) ]}","key":"even-codex-connector"}|,
    );
    Even::Codex::State::save_pairing(
        env              => { EVEN_CODEX_CONFIG_ROOT => $config_root },
        workspace_ref    => 'ticket-only',
        codex_session_id => 'session-ticket',
    );

    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    HOME                     => $tmp,
                    TICKET_REF               => 'ticket-only',
                    EVEN_CODEX_CONFIG_ROOT   => $config_root,
                    EVEN_CODEX_START_CAPTURE => 1,
                    EVEN_CODEX_DASHBOARD_BIN => $dashboard_bin,
                },
            );
            return $manager->main_start(undef);
        }
    );
    is( $rc, 0, 'main_start accepts TICKET_REF fallback when WORKSPACE_REF is absent' );
    is( $stderr, q{}, 'main_start with TICKET_REF fallback leaves stderr empty' );
    my $payload = decode_json($stdout);
    is( $payload->{workspace_ref}, 'ticket-only', 'main_start uses TICKET_REF as the workspace ref' );
    is( $payload->{bind_host}, '0.0.0.0', 'main_start falls back to the default bind host' );
    is( $payload->{port}, 6789, 'main_start falls back to the default port' );
    is( $payload->{advertised_host}, '127.0.0.1', 'main_start falls back to the default advertised host' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path($bin_dir);
    my $dashboard_bin = write_fake_dashboard_api(
        bin_dir => $bin_dir,
        payload => qq|{"action":"add","changed":1,"file":"@{[ File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ) ]}","key":"even-codex-connector"}|,
    );
    Even::Codex::State::save_pairing(
        env              => { EVEN_CODEX_CONFIG_ROOT => $config_root },
        workspace_ref    => 'ticket-fallback',
        codex_session_id => 'session-ticket-fallback',
    );

    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    HOME                     => $tmp,
                    WORKSPACE_REF            => q{},
                    TICKET_REF               => 'ticket-fallback',
                    EVEN_CODEX_CONFIG_ROOT   => $config_root,
                    EVEN_CODEX_START_CAPTURE => 1,
                    EVEN_CODEX_DASHBOARD_BIN => $dashboard_bin,
                },
            );
            return $manager->main_start();
        }
    );
    is( $rc, 0, 'main_start falls back from an empty WORKSPACE_REF to TICKET_REF' );
    is( $stderr, q{}, 'main_start empty WORKSPACE_REF fallback leaves stderr empty' );
    is( decode_json($stdout)->{workspace_ref}, 'ticket-fallback', 'main_start uses TICKET_REF when WORKSPACE_REF is empty' );
}

{
    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {},
            );
            return $manager->main_start('add');
        }
    );
    is( $rc, 2, 'main_start add rejects a missing session id argument' );
    is( $stdout, q{}, 'main_start add usage failure keeps stdout empty' );
    like( $stderr, qr/Usage: dashboard even-codex\.start add <codex-session-id>/, 'main_start add prints usage for a missing session id' );
}

{
    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    WORKSPACE_REF => q{},
                },
            );
            return $manager->main_start( 'add', 'session-empty-workspace' );
        }
    );
    is( $rc, 2, 'main_start rejects an empty WORKSPACE_REF' );
    is( $stdout, q{}, 'main_start empty workspace failure keeps stdout empty' );
    like( $stderr, qr/WORKSPACE_REF or TICKET_REF is required/, 'main_start explains an empty WORKSPACE_REF' );
}

{
    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    WORKSPACE_REF => q{},
                    TICKET_REF    => q{},
                },
            );
            return $manager->main_start( 'add', 'session-empty-fallback' );
        }
    );
    is( $rc, 2, 'main_start rejects an empty fallback TICKET_REF' );
    is( $stdout, q{}, 'main_start empty fallback failure keeps stdout empty' );
    like( $stderr, qr/WORKSPACE_REF or TICKET_REF is required/, 'main_start explains an empty fallback TICKET_REF' );
}

{
    local $ENV{WORKSPACE_REF} = 'class-call';
    my $tmp = tempdir( CLEANUP => 1 );
    local $ENV{EVEN_CODEX_CONFIG_ROOT} = File::Spec->catdir( $tmp, 'config' );
    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            local *STDOUT = $out_fh;
            local *STDERR = $err_fh;
            return Even::Codex::Manager->main_start( 'add', 'session-class' );
        }
    );
    is( $rc, 0, 'main_start also works through the class entrypoint' );
    is( $stderr, q{}, 'class main_start add leaves stderr empty' );
    is( decode_json($stdout)->{codex_session_id}, 'session-class', 'class main_start add prints the saved session id' );
}

{
    my $manager = Even::Codex::Manager->new();
    ok( defined $manager->env_value('PATH'), 'manager default constructor keeps access to process env vars' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    make_path($config_root);
    my $pairings = File::Spec->catfile( $config_root, 'workspace-pairings.json' );
    open my $fh, '>', $pairings or die $!;
    print {$fh} '{"empty-pair":""}';
    close $fh or die $!;
    my ( $rc, $stdout, $stderr ) = capture_run(
        sub {
            my ( $out_fh, $err_fh ) = @_;
            my $manager = Even::Codex::Manager->new(
                stdout_fh => $out_fh,
                stderr_fh => $err_fh,
                env       => {
                    WORKSPACE_REF            => 'empty-pair',
                    EVEN_CODEX_CONFIG_ROOT   => $config_root,
                    EVEN_CODEX_START_CAPTURE => 1,
                },
            );
            return $manager->main_start('status');
        }
    );
    is( $rc, 2, 'main_start rejects an empty stored pairing' );
    is( $stdout, q{}, 'main_start empty stored pairing keeps stdout empty' );
    like( $stderr, qr/No even-codex pairing exists for workspace empty-pair/, 'main_start explains an empty stored pairing' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path($bin_dir);
    my $dashboard_bin = write_fake_dashboard_api(
        bin_dir => $bin_dir,
        payload => qq|{"action":"add","changed":1,"file":"@{[ File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ) ]}","key":"even-codex-connector"}|,
    );
    Even::Codex::State::save_pairing(
        env              => { EVEN_CODEX_CONFIG_ROOT => $config_root },
        workspace_ref    => 'serve-live',
        codex_session_id => 'session-live',
    );
    my $port = _reserve_port();
    my $pid = fork();
    die "Unable to fork manager live server: $!" if !defined $pid;

    if ( $pid == 0 ) {
        my $manager = Even::Codex::Manager->new(
            env => {
                HOME                         => $tmp,
                WORKSPACE_REF                 => 'serve-live',
                EVEN_CODEX_CONFIG_ROOT        => $config_root,
                EVEN_CODEX_DASHBOARD_BIN      => $dashboard_bin,
                EVEN_CODEX_HOST               => '127.0.0.1',
                EVEN_CODEX_ADVERTISE_HOST     => '127.0.0.1',
                EVEN_CODEX_PORT               => $port,
                EVEN_CODEX_SERVER_MAX_REQUESTS => 3,
            },
        );
        exit $manager->main_start();
    }

    _wait_for_port($port);
    my $health = _http_get( $port, '/health' );
    is( $health->{status}, 200, 'manager non-capture start serves health on the configured port' );
    my $bootstrap = _http_get( $port, '/bootstrap' );
    is( $bootstrap->{status}, 200, 'manager non-capture start also serves bootstrap' );
    waitpid $pid, 0;
    is( $? >> 8, 0, 'manager non-capture start exits cleanly after the configured max requests' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path($bin_dir);
    my $dashboard_bin = write_fake_dashboard_api(
        bin_dir => $bin_dir,
        payload => qq|{"action":"add","changed":1,"file":"@{[ File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ) ]}","key":"even-codex-connector"}|,
    );
    Even::Codex::State::save_pairing(
        env              => { EVEN_CODEX_CONFIG_ROOT => $config_root },
        workspace_ref    => 'serve-term',
        codex_session_id => 'session-term',
    );
    my $port = _reserve_port();
    my $pid = fork();
    die "Unable to fork manager TERM server: $!" if !defined $pid;

    if ( $pid == 0 ) {
        my $manager = Even::Codex::Manager->new(
            env => {
                HOME                      => $tmp,
                WORKSPACE_REF             => 'serve-term',
                EVEN_CODEX_CONFIG_ROOT    => $config_root,
                EVEN_CODEX_DASHBOARD_BIN  => $dashboard_bin,
                EVEN_CODEX_HOST           => '127.0.0.1',
                EVEN_CODEX_ADVERTISE_HOST => '127.0.0.1',
                EVEN_CODEX_PORT           => $port,
                EVEN_CODEX_SERVER_MAX_REQUESTS => q{},
            },
        );
        exit $manager->main_start();
    }

    _wait_for_port($port);
    my $health = _http_get( $port, '/health' );
    is( $health->{status}, 200, 'manager serves normally even when the max-request env is empty' );
    kill 'TERM', $pid;
    waitpid $pid, 0;
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $config_root = File::Spec->catdir( $tmp, 'config' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path($bin_dir);
    my $dashboard_bin = write_fake_dashboard_api(
        bin_dir => $bin_dir,
        payload => qq|{"action":"add","changed":1,"file":"@{[ File::Spec->catfile( $tmp, '.developer-dashboard', 'config', 'api.json' ) ]}","key":"even-codex-connector"}|,
    );
    Even::Codex::State::save_pairing(
        env              => { EVEN_CODEX_CONFIG_ROOT => $config_root },
        workspace_ref    => 'serve-term-undef',
        codex_session_id => 'session-term-undef',
    );
    my $port = _reserve_port();
    my $pid = fork();
    die "Unable to fork manager undefined-max server: $!" if !defined $pid;

    if ( $pid == 0 ) {
        my $manager = Even::Codex::Manager->new(
            env => {
                HOME                      => $tmp,
                WORKSPACE_REF             => 'serve-term-undef',
                EVEN_CODEX_CONFIG_ROOT    => $config_root,
                EVEN_CODEX_DASHBOARD_BIN  => $dashboard_bin,
                EVEN_CODEX_HOST           => '127.0.0.1',
                EVEN_CODEX_ADVERTISE_HOST => '127.0.0.1',
                EVEN_CODEX_PORT           => $port,
            },
        );
        exit $manager->main_start();
    }

    _wait_for_port($port);
    my $health = _http_get( $port, '/health' );
    is( $health->{status}, 200, 'manager also serves normally when the max-request env is undefined' );
    kill 'TERM', $pid;
    waitpid $pid, 0;
}

done_testing;

sub _http_get {
    my ( $port, $path ) = @_;
    return _http_request( $port, 'GET', $path );
}

sub _http_request {
    my ( $port, $method, $path, $body, $raw_headers ) = @_;
    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Unable to connect to test server: $!";

    my $payload = defined $body ? $body : q{};
    print {$socket} "$method $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nConnection: close\r\n";
    print {$socket} $raw_headers if defined $raw_headers;
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
    return { status => 0 + $status, body => defined $response_body ? $response_body : q{} };
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

    my ( $head, $response_body ) = split /\r?\n\r?\n/, $raw, 2;
    my ($status) = $head =~ m{\AHTTP/1\.1\s+(\d+)};
    return { status => 0 + $status, body => defined $response_body ? $response_body : q{} };
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
