use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(encode_json);
use Cwd qw(abs_path);
use Test::More;

use lib 'lib';
use Even::Codex::Connector ();
use Even::Codex::State ();

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return $text;
}

sub write_session_file {
    my ( $home, $session_id ) = @_;
    my $dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '06', '02' );
    make_path($dir);
    my $path = File::Spec->catfile( $dir, "session-$session_id.jsonl" );
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} qq|{"type":"session_meta","payload":{"title":"DD Route Session"}}\n|;
    print {$fh} qq|{"type":"event_msg","payload":{"type":"user_message","message":"hi from dd route"}}\n|;
    print {$fh} qq|{"type":"event_msg","payload":{"type":"agent_message","message":"working on it"}}\n|;
    print {$fh} qq|{"payload":{"type":"message","role":"assistant","content":[{"text":"hello from dd route"}]}}\n|;
    close $fh or die "Unable to close $path: $!";
    return $path;
}

sub run_dashboard_ajax_script {
    my ( $script, %env ) = @_;
    my $script_path = abs_path( File::Spec->catfile( 'dashboards', 'ajax', $script ) );
    my @pairs = map {
        sprintf q{%s="%s"}, $_, ( defined $env{$_} ? $env{$_} : q{} ) =~ s/"/\\"/gr
    } sort keys %env;
    my $command = join q{ }, @pairs, qq{perl "$script_path"};
    my $output = qx{$command};
    my $status = $? >> 8;
    return ( $status, $output );
}

{
    my $routes = slurp('config/routes.json');
    like( $routes, qr{/even-codex/plugin}, 'routes.json exposes the DD plugin route alias' );
    like( $routes, qr{/even-codex/bootstrap}, 'routes.json exposes the DD bootstrap ajax alias' );
    like( $routes, qr{/even-codex/prompt}, 'routes.json exposes the DD prompt ajax alias' );

    my $plugin_page = slurp('dashboards/plugin');
    like( $plugin_page, qr{/css/even-codex/dd-plugin\.css}, 'DD plugin page references the native DD smart stylesheet route' );
    like( $plugin_page, qr{/js/even-codex/dd-plugin\.js}, 'DD plugin page references the native DD smart script route' );

    my $plugin_js = slurp('dashboards/public/js/dd-plugin.js');
    like( $plugin_js, qr{/ajax/even-codex/}, 'DD plugin script targets the native DD smart ajax routes' );
    like( $plugin_js, qr/endpoint\('bootstrap'\)/, 'DD plugin script fetches the DD bootstrap route through the shared endpoint helper' );
    like( $plugin_js, qr/endpoint\('session'\)/, 'DD plugin script fetches the DD session route through the shared endpoint helper' );
    like( $plugin_js, qr/endpoint\('prompt'\)/, 'DD plugin script posts to the DD prompt route through the shared endpoint helper' );
    like( $plugin_js, qr{application/x-www-form-urlencoded}, 'DD plugin prompt submit uses the form-urlencoded ajax body DD parses' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my $params_file = File::Spec->catfile( $tmp, 'params.json' );
    my $query_file = File::Spec->catfile( $tmp, 'query.txt' );
    open my $params_fh, '>', $params_file or die "Unable to write $params_file: $!";
    print {$params_fh} encode_json( { query => 'from params file', workspace_ref => 'file-workspace' } );
    close $params_fh or die "Unable to close $params_file: $!";
    open my $query_fh, '>', $query_file or die "Unable to write $query_file: $!";
    print {$query_fh} "query=from+query+file&workspace_ref=query-workspace";
    close $query_fh or die "Unable to close $query_file: $!";

    my %json_params = Even::Codex::Connector::request_params_from_env(
        env => {
            DEVELOPER_DASHBOARD_AJAX_PARAMS_FILE => $params_file,
        },
    );
    is_deeply(
        \%json_params,
        { query => 'from params file', workspace_ref => 'file-workspace' },
        'request_params_from_env reads DD ajax params from the spill file when present',
    );

    my %query_params = Even::Codex::Connector::request_params_from_env(
        env => {
            DEVELOPER_DASHBOARD_AJAX_PARAMS_FILE       => $params_file,
            DEVELOPER_DASHBOARD_AJAX_PARAMS            => '{"broken":',
            DEVELOPER_DASHBOARD_AJAX_QUERY_STRING_FILE => $query_file,
        },
    );
    is_deeply(
        \%query_params,
        { query => 'from query file', workspace_ref => 'query-workspace' },
        'request_params_from_env falls back to the DD query spill file when inline ajax params are invalid',
    );

    my %inline_query_params = Even::Codex::Connector::request_params_from_env(
        env => {
            QUERY_STRING => '&workspace_ref=foo%20bar&query=slash%2Fstatus&empty&=ignored',
        },
    );
    is_deeply(
        \%inline_query_params,
        { workspace_ref => 'foo bar', query => 'slash/status', empty => q{} },
        'request_params_from_env decodes inline query strings with percent escapes, empty values, and blank segments',
    );

    my $empty_file = File::Spec->catfile( $tmp, 'empty.txt' );
    open my $empty_fh, '>', $empty_file or die "Unable to write $empty_file: $!";
    close $empty_fh or die "Unable to close $empty_file: $!";
    my %empty_params = Even::Codex::Connector::request_params_from_env(
        env => {
            DEVELOPER_DASHBOARD_AJAX_QUERY_STRING_FILE => $empty_file,
        },
    );
    is_deeply( \%empty_params, {}, 'request_params_from_env returns an empty param set when the DD query spill file is empty' );

    local %ENV = ( QUERY_STRING => 'workspace_ref=env-default' );
    my %default_env_params = Even::Codex::Connector::request_params_from_env();
    is_deeply( \%default_env_params, { workspace_ref => 'env-default' }, 'request_params_from_env uses the process env when no env override is supplied' );

    my $file_error = eval {
        Even::Codex::Connector::request_params_from_env(
            env => {
                DEVELOPER_DASHBOARD_AJAX_QUERY_STRING_FILE => File::Spec->catfile( $tmp, 'missing-query.txt' ),
            },
        );
        1;
    } ? q{} : $@;
    like( $file_error, qr/Unable to read .*missing-query\.txt/, 'request_params_from_env fails clearly when the DD spill file is missing' );

    my %array_payload_params = Even::Codex::Connector::request_params_from_env(
        env => {
            DEVELOPER_DASHBOARD_AJAX_PARAMS => '[]',
            QUERY_STRING                    => 'query=fallback-query',
        },
    );
    is_deeply(
        \%array_payload_params,
        { query => 'fallback-query' },
        'request_params_from_env ignores non-hash ajax json payloads and falls back to the query string',
    );

    is( Even::Codex::Connector::_normalized_route_base(undef), q{}, '_normalized_route_base returns empty for undef' );
    is( Even::Codex::Connector::_normalized_route_base(q{}), q{}, '_normalized_route_base returns empty for an empty route base' );
    is( Even::Codex::Connector::_normalized_route_base('even-codex///'), '/even-codex', '_normalized_route_base trims trailing slashes and prefixes a leading slash' );

    is( Even::Codex::Connector::_route_url( undef, '/even-codex', 'health' ), '/even-codex/health', '_route_url works without a base url' );
    is( Even::Codex::Connector::_route_url( q{}, '/even-codex', 'health' ), '/even-codex/health', '_route_url works with an empty base url' );
    is( Even::Codex::Connector::_route_url( 'https://dd.test', '/even-codex', 'health' ), 'https://dd.test/even-codex/health', '_route_url prefixes the DD base url when present' );

    is(
        Even::Codex::Connector::_load_env_or_file(
            { INLINE => q{}, FILE => $query_file },
            'INLINE',
            'FILE',
        ),
        'query=from+query+file&workspace_ref=query-workspace',
        '_load_env_or_file falls back to the file path when the inline env payload is empty',
    );
    is(
        Even::Codex::Connector::_load_env_or_file(
            { INLINE => 'inline-value', FILE => $query_file },
            'INLINE',
            'FILE',
        ),
        'inline-value',
        '_load_env_or_file prefers the inline env payload when present',
    );
    is(
        Even::Codex::Connector::_load_env_or_file(
            { FILE => q{} },
            'INLINE',
            'FILE',
        ),
        q{},
        '_load_env_or_file returns empty when the DD spill-file path is present but blank',
    );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my %env = ( HOME => $tmp, QUERY_STRING => 'workspace_ref=proof' );
    write_session_file( $tmp, 'codex-dd-ajax' );
    Even::Codex::State::save_pairing(
        env              => \%env,
        workspace_ref    => 'proof',
        codex_session_id => 'codex-dd-ajax',
    );

    my ( $bootstrap_status, $bootstrap_output ) = run_dashboard_ajax_script( 'bootstrap', %env );
    is( $bootstrap_status, 0, 'bootstrap ajax script runs from the dashboards/ajax path' );
    like( $bootstrap_output, qr/"workspace_ref":"proof"/, 'bootstrap ajax script returns the paired workspace payload' );
    like( $bootstrap_output, qr{"plugin_url":"/app/even-codex/plugin"}, 'bootstrap ajax script publishes the DD smart plugin route' );
    like( $bootstrap_output, qr{"prompt_url":"/ajax/even-codex/prompt"}, 'bootstrap ajax script publishes the DD smart prompt route' );

    my ( $session_status, $session_output ) = run_dashboard_ajax_script( 'session', %env );
    is( $session_status, 0, 'session ajax script runs from the dashboards/ajax path' );
    like( $session_output, qr/"last_assistant_message":"hello from dd route"/, 'session ajax script returns the live assistant transcript' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my %env = ( HOME => $tmp );
    write_session_file( $tmp, 'codex-dd-1' );
    Even::Codex::State::save_pairing(
        env              => \%env,
        workspace_ref    => 'foobar',
        codex_session_id => 'codex-dd-1',
    );

    my $bootstrap = Even::Codex::Connector::bootstrap_payload(
        env        => \%env,
        route_base => '/even-codex',
    );
    is( $bootstrap->{workspace_ref}, 'foobar', 'bootstrap payload falls back to the sole saved workspace pairing' );
    is( $bootstrap->{bootstrap_url}, '/even-codex/bootstrap', 'bootstrap payload points at the DD bootstrap route' );
    is( $bootstrap->{prompt_url}, '/even-codex/prompt', 'bootstrap payload points at the DD prompt route' );
    is( $bootstrap->{last_user_message}, 'hi from dd route', 'bootstrap payload carries the latest user message' );
    is( $bootstrap->{last_assistant_message}, 'hello from dd route', 'bootstrap payload carries the latest assistant reply' );

    my $health = Even::Codex::Connector::health_payload(
        env        => \%env,
        route_base => '/even-codex',
    );
    is( $health->{workspace_ref}, 'foobar', 'health payload resolves the same workspace' );
    is( $health->{service}, 'even-codex', 'health payload keeps the service name' );

    my $session = Even::Codex::Connector::session_payload( env => \%env );
    is( $session->{workspace_ref}, 'foobar', 'session payload keeps the resolved workspace ref' );
    is( $session->{last_assistant_progress_message}, 'working on it', 'session payload carries the latest assistant progress message' );

    {
        local %ENV = %env;
        my $default_env_session = Even::Codex::Connector::session_payload(
            workspace_ref    => 'foobar',
            codex_session_id => 'codex-dd-1',
        );
        is( $default_env_session->{workspace_ref}, 'foobar', 'session payload can use the process env when no env override is supplied' );
    }

    my $explicit_bootstrap = Even::Codex::Connector::bootstrap_payload(
        env              => \%env,
        workspace_ref    => 'argument-first',
        codex_session_id => 'codex-dd-1',
        route_base       => 'even-codex/',
        base_url         => 'https://dashboard.example.test',
        bind_host        => q{},
        advertised_host  => q{},
    );
    is( $explicit_bootstrap->{workspace_ref}, 'argument-first', 'bootstrap payload prefers the explicit workspace ref argument' );
    is( $explicit_bootstrap->{bind_host}, 'dashboard-serve', 'bootstrap payload defaults bind_host when the caller leaves it empty' );
    is( $explicit_bootstrap->{advertised_host}, 'dashboard-serve', 'bootstrap payload defaults advertised_host when the caller leaves it empty' );
    is( $explicit_bootstrap->{plugin_url}, 'https://dashboard.example.test/even-codex/plugin', 'bootstrap payload normalizes the route base and joins it to the base url' );
    is( $explicit_bootstrap->{health_url}, 'https://dashboard.example.test/even-codex/health', 'bootstrap payload exposes the DD health endpoint' );

    my $portful_bootstrap = Even::Codex::Connector::bootstrap_payload(
        env              => \%env,
        workspace_ref    => 'foobar',
        codex_session_id => 'codex-dd-1',
        bind_host        => '0.0.0.0',
        advertised_host  => '192.168.1.20',
        port             => 6789,
    );
    is( $portful_bootstrap->{bind_host}, '0.0.0.0', 'bootstrap payload keeps an explicit bind_host' );
    is( $portful_bootstrap->{advertised_host}, '192.168.1.20', 'bootstrap payload keeps an explicit advertised_host' );
    is( $portful_bootstrap->{port}, 6789, 'bootstrap payload keeps an explicit port' );
    is( $portful_bootstrap->{bootstrap_url}, '/bootstrap', 'bootstrap payload defaults the DD route base to the root path when none is supplied' );

    my %params_workspace = ( workspace_ref => 'params-workspace' );
    is(
        Even::Codex::Connector::resolve_workspace_ref(
            env    => \%env,
            params => \%params_workspace,
        ),
        'params-workspace',
        'resolve_workspace_ref prefers the DD ajax params workspace when present',
    );

    is(
        Even::Codex::Connector::resolve_workspace_ref(
            env => {
                %env,
                WORKSPACE_REF => 'env-workspace',
            },
        ),
        'env-workspace',
        'resolve_workspace_ref falls back to WORKSPACE_REF when no explicit workspace exists',
    );

    is(
        Even::Codex::Connector::resolve_workspace_ref(
            env => {
                %env,
                TICKET_REF => 'ticket-workspace',
            },
        ),
        'ticket-workspace',
        'resolve_workspace_ref falls back to TICKET_REF when WORKSPACE_REF is absent',
    );

    my ( $explicit_workspace, $explicit_session ) = Even::Codex::Connector::paired_session_id(
        env              => \%env,
        workspace_ref    => 'manual-workspace',
        codex_session_id => 'manual-session',
    );
    is( $explicit_workspace, 'manual-workspace', 'paired_session_id keeps the explicit workspace when a session id is forced' );
    is( $explicit_session, 'manual-session', 'paired_session_id keeps the explicit session id when supplied' );

    my ( $fallback_workspace, $fallback_session ) = Even::Codex::Connector::paired_session_id(
        env              => \%env,
        workspace_ref    => 'foobar',
        codex_session_id => q{},
    );
    is( $fallback_workspace, 'foobar', 'paired_session_id keeps the explicit workspace when the explicit session id is blank' );
    is( $fallback_session, 'codex-dd-1', 'paired_session_id falls back to the saved pairing when the explicit session id is blank' );

    is(
        Even::Codex::Connector::resolve_workspace_ref(
            env           => \%env,
            workspace_ref => q{},
            params        => { workspace_ref => 'params-after-blank-arg' },
        ),
        'params-after-blank-arg',
        'resolve_workspace_ref skips a blank explicit workspace and falls through to the DD ajax params workspace',
    );

    my @submitted;
    my $prompt = Even::Codex::Connector::prompt_payload(
        env    => \%env,
        query  => 'what is the year today?',
        sender => bless(
            {
                callback => sub {
                    my (%args) = @_;
                    push @submitted, \%args;
                    return { tty => 'pts/9' };
                },
            },
            'Local::Sender'
        ),
    );
    is( $prompt->{queued_query}, 'what is the year today?', 'prompt payload keeps the submitted query' );
    is( $prompt->{tty}, 'pts/9', 'prompt payload returns the sender tty' );
    is_deeply(
        \@submitted,
        [ { session_id => 'codex-dd-1', prompt => 'what is the year today?' } ],
        'prompt payload submits to the paired Codex session',
    );

    my $prompt_error = eval {
        Even::Codex::Connector::prompt_payload(
            env   => \%env,
            query => q{},
        );
        1;
    } ? q{} : $@;
    like( $prompt_error, qr/Query is required/, 'prompt payload rejects an empty query' );

    my $missing_query_error = eval {
        Even::Codex::Connector::prompt_payload(
            env => \%env,
        );
        1;
    } ? q{} : $@;
    like( $missing_query_error, qr/Query is required/, 'prompt payload rejects a missing query' );

    my $missing_pairing_error = eval {
        Even::Codex::Connector::paired_session_id(
            env           => \%env,
            workspace_ref => 'missing-workspace',
        );
        1;
    } ? q{} : $@;
    like( $missing_pairing_error, qr/No even-codex pairing exists for workspace missing-workspace/, 'paired_session_id fails clearly when no saved DD pairing exists for the workspace' );

    {
        local *Even::Codex::State::load_pairing = sub { return q{}; };
        my $blank_pairing_error = eval {
            Even::Codex::Connector::paired_session_id(
                env           => \%env,
                workspace_ref => 'foobar',
            );
            1;
        } ? q{} : $@;
        like( $blank_pairing_error, qr/No even-codex pairing exists for workspace foobar/, 'paired_session_id treats a blank saved pairing as missing' );
    }

    my @default_sender_calls;
    local *Even::Codex::Sender::new = sub {
        my ( $class, %args ) = @_;
        push @default_sender_calls, \%args;
        return bless {}, 'Local::DefaultSender';
    };

    my $default_sender_prompt = Even::Codex::Connector::prompt_payload(
        env           => \%env,
        workspace_ref => 'foobar',
        query         => 'status',
    );
    is( $default_sender_prompt->{tty}, 'pts/77', 'prompt payload can instantiate the default sender when none is provided' );
    is_deeply( \@default_sender_calls, [ { env => \%env } ], 'prompt payload passes the connector env to the default sender constructor' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my %env = ( HOME => $tmp );
    Even::Codex::State::save_pairing(
        env              => \%env,
        workspace_ref    => 'one',
        codex_session_id => 'session-one',
    );
    Even::Codex::State::save_pairing(
        env              => \%env,
        workspace_ref    => 'two',
        codex_session_id => 'session-two',
    );

    my $error = eval { Even::Codex::Connector::resolve_workspace_ref( env => \%env ); 1 } ? q{} : $@;
    like( $error, qr/workspace_ref is required/, 'connector requires an explicit workspace when multiple pairings exist' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my %env = ( HOME => $tmp );
    my $error = eval { Even::Codex::Connector::resolve_workspace_ref( env => \%env ); 1 } ? q{} : $@;
    like( $error, qr/workspace_ref is required/, 'connector requires an explicit workspace when no DD pairing exists yet' );
}

done_testing;

package Local::Sender;

sub submit_prompt {
    my ( $self, %args ) = @_;
    return $self->{callback}->(%args);
}

package Local::DefaultSender;

sub submit_prompt {
    my ( $self, %args ) = @_;
    return { tty => 'pts/77', %args };
}
