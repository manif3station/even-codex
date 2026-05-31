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
        );
        $server->serve();
        exit 0;
    }

    _wait_for_port($port);
    my $plugin = _http_get( $port, '/plugin' );
    is( $plugin->{status}, 200, 'server also serves the plugin HTML on /plugin without a trailing slash' );
    my $post = _http_request( $port, 'POST', '/health' );
    is( $post->{status}, 404, 'server treats non-GET requests as unmatched routes' );
    my $missing = _http_get( $port, '/missing' );
    is( $missing->{status}, 404, 'server returns 404 for unknown routes' );

    kill 'TERM', $pid;
    waitpid $pid, 0;
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
                    TICKET_REF               => 'ticket-only',
                    EVEN_CODEX_CONFIG_ROOT   => $config_root,
                    EVEN_CODEX_START_CAPTURE => 1,
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
                    WORKSPACE_REF            => q{},
                    TICKET_REF               => 'ticket-fallback',
                    EVEN_CODEX_CONFIG_ROOT   => $config_root,
                    EVEN_CODEX_START_CAPTURE => 1,
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
                WORKSPACE_REF                 => 'serve-live',
                EVEN_CODEX_CONFIG_ROOT        => $config_root,
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
                WORKSPACE_REF             => 'serve-term',
                EVEN_CODEX_CONFIG_ROOT    => $config_root,
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
                WORKSPACE_REF             => 'serve-term-undef',
                EVEN_CODEX_CONFIG_ROOT    => $config_root,
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
    my ( $port, $method, $path ) = @_;
    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Unable to connect to test server: $!";

    print {$socket} "$method $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nConnection: close\r\n\r\n";
    my $raw = do { local $/; <$socket> };
    close $socket;

    my ( $head, $body ) = split /\r?\n\r?\n/, $raw, 2;
    my ($status) = $head =~ m{\AHTTP/1\.1\s+(\d+)};
    return { status => 0 + $status, body => defined $body ? $body : q{} };
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
