package Even::Codex::Connector;

use strict;
use warnings;

use JSON::PP qw(decode_json encode_json);

use Even::Codex::Sender ();
use Even::Codex::State ();
use Even::Codex::Transcript ();

our $VERSION = '0.48';

sub request_params_from_env {
    my (%args) = @_;
    my $env = _effective_env( \%args );

    my $ajax_params_json = _load_env_or_file(
        $env,
        'DEVELOPER_DASHBOARD_AJAX_PARAMS',
        'DEVELOPER_DASHBOARD_AJAX_PARAMS_FILE',
    );
    if ( $ajax_params_json ne q{} ) {
        my $payload = eval { decode_json($ajax_params_json) };
        return %{$payload} if ref $payload eq 'HASH';
    }

    my $query = _load_env_or_file(
        $env,
        'QUERY_STRING',
        'DEVELOPER_DASHBOARD_AJAX_QUERY_STRING_FILE',
    );
    my %params;
    for my $pair ( split /[&;]/, $query ) {
        next if $pair eq q{};
        my ( $key, $value ) = split /=/, $pair, 2;
        next if $key eq q{};
        $key = _url_decode($key);
        $value = defined $value ? _url_decode($value) : q{};
        $params{$key} = $value;
    }

    return %params;
}

sub resolve_workspace_ref {
    my (%args) = @_;
    my $env = _effective_env( \%args );
    my $params = $args{params} || {};

    for my $candidate (
        $args{workspace_ref},
        $params->{workspace_ref},
        $env->{WORKSPACE_REF},
        $env->{TICKET_REF},
    ) {
        next if !defined $candidate;
        return $candidate if $candidate ne q{};
    }

    my $pairings = Even::Codex::State::load_pairings( env => $env );
    my @workspace_refs = sort keys %{$pairings};
    return $workspace_refs[0] if @workspace_refs == 1;

    die "workspace_ref is required when even-codex has zero or multiple saved pairings\n";
}

sub paired_session_id {
    my (%args) = @_;
    my $env = _effective_env( \%args );
    my $workspace_ref = resolve_workspace_ref(%args);
    my $explicit_session_id = $args{codex_session_id};
    if ( defined $explicit_session_id ) {
        return ( $workspace_ref, $explicit_session_id ) if $explicit_session_id ne q{};
    }
    my $codex_session_id = Even::Codex::State::load_pairing(
        env           => $env,
        workspace_ref => $workspace_ref,
    );

    die "No even-codex pairing exists for workspace $workspace_ref\n"
      if !defined $codex_session_id || $codex_session_id eq q{};

    return ( $workspace_ref, $codex_session_id );
}

sub session_payload {
    my (%args) = @_;
    my $env = _effective_env( \%args );
    my ( $workspace_ref, $codex_session_id ) = paired_session_id(%args);
    my $session = Even::Codex::Transcript::session_snapshot(
        env        => $env,
        session_id => $codex_session_id,
    );
    $session->{workspace_ref} = $workspace_ref;
    return $session;
}

sub bootstrap_payload {
    my (%args) = @_;
    my $workspace_ref = resolve_workspace_ref(%args);
    my $session = session_payload(%args);
    my $route_base_input = $args{route_base};
    $route_base_input = q{} if !defined $route_base_input;
    my $route_base = _normalized_route_base($route_base_input);
    my $base_url = defined $args{base_url} ? $args{base_url} : q{};
    my $port = 0;
    if ( defined $args{port} ) {
        $port = 0 + $args{port};
    }
    my $bind_host = $args{bind_host};
    $bind_host = 'dashboard-serve' if !defined $bind_host || $bind_host eq q{};
    my $advertised_host = $args{advertised_host};
    $advertised_host = 'dashboard-serve' if !defined $advertised_host || $advertised_host eq q{};

    return {
        ok                              => 1,
        workspace_ref                   => $workspace_ref,
        codex_session_id                => $session->{session_id},
        bind_host                       => $bind_host,
        advertised_host                 => $advertised_host,
        port                            => $port,
        health_url                      => _route_url( $base_url, $route_base, 'health' ),
        bootstrap_url                   => _route_url( $base_url, $route_base, 'bootstrap' ),
        plugin_url                      => _route_url( $base_url, $route_base, 'plugin' ),
        session_url                     => _route_url( $base_url, $route_base, 'session' ),
        prompt_url                      => _route_url( $base_url, $route_base, 'prompt' ),
        last_user_message               => $session->{last_user_message},
        last_assistant_progress_message => $session->{last_assistant_progress_message},
        last_assistant_message          => $session->{last_assistant_message},
        recent_turns                    => $session->{recent_turns},
    };
}

sub health_payload {
    my (%args) = @_;
    my $bootstrap = bootstrap_payload(%args);
    return {
        ok               => 1,
        service          => 'even-codex',
        workspace_ref    => $bootstrap->{workspace_ref},
        codex_session_id => $bootstrap->{codex_session_id},
        port             => $bootstrap->{port},
    };
}

sub prompt_payload {
    my (%args) = @_;
    my $env = _effective_env( \%args );
    my $query = $args{query};
    die "Query is required\n" if !defined $query || $query eq q{};

    my ( undef, $codex_session_id ) = paired_session_id(%args);
    my $sender = $args{sender};
    if ( !$sender ) {
        $sender = Even::Codex::Sender->new( env => $env );
    }
    my $submission = $sender->submit_prompt(
        session_id => $codex_session_id,
        prompt     => $query,
    );

    return {
        ok               => 1,
        workspace_ref    => resolve_workspace_ref(%args),
        codex_session_id => $codex_session_id,
        queued_query     => $query,
        tty              => $submission->{tty},
    };
}

sub _normalized_route_base {
    my ($value) = @_;
    return q{} if !defined $value || $value eq q{};
    $value =~ s{/+\z}{};
    return $value =~ m{\A/} ? $value : '/' . $value;
}

sub _route_url {
    my ( $base_url, $route_base, $tail ) = @_;
    my $path = $route_base . '/' . $tail;
    if ( defined $base_url ) {
        return $base_url . $path if $base_url ne q{};
    }
    return $path;
}

sub _url_decode {
    my ($value) = @_;
    $value =~ tr/+/ /;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $value;
}

sub _load_env_or_file {
    my ( $env, $env_key, $file_key ) = @_;
    if ( defined $env->{$env_key} ) {
        return $env->{$env_key} if $env->{$env_key} ne q{};
    }

    my $path = $env->{$file_key};
    return q{} if !defined $path || $path eq q{};

    open my $fh, '<:raw', $path or die "Unable to read $path: $!";
    local $/;
    my $value = join q{}, <$fh>;
    close $fh;
    return $value;
}

sub _effective_env {
    my ($args) = @_;
    return $args->{env} if exists $args->{env};
    return \%ENV;
}

1;
