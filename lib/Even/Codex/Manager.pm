package Even::Codex::Manager;

use strict;
use warnings;

use JSON::PP qw(encode_json);

use Even::Codex::Server ();
use Even::Codex::State ();

our $VERSION = '0.30';

sub new {
    my ( $class, %args ) = @_;
    return bless {
        stdout_fh => $args{stdout_fh} || \*STDOUT,
        stderr_fh => $args{stderr_fh} || \*STDERR,
        env       => $args{env} || \%ENV,
    }, $class;
}

sub main_start {
    my ( $class, @argv ) = @_;
    my $self = ref($class) ? $class : $class->new;

    my $code = eval {
        if ( @argv && defined $argv[0] && $argv[0] eq 'add' ) {
            my $result = $self->execute_start_add( @argv[ 1 .. $#argv ] );
            print { $self->{stdout_fh} } encode_json($result) . "\n";
            return 0;
        }

        my $plan = $self->start_plan;
        print { $self->{stdout_fh} } encode_json($plan) . "\n";
        return 0 if $self->env_value('EVEN_CODEX_START_CAPTURE');

        my $server = Even::Codex::Server->new(
            host             => $plan->{bind_host},
            port             => $plan->{port},
            advertised_host  => $plan->{advertised_host},
            workspace_ref    => $plan->{workspace_ref},
            codex_session_id => $plan->{codex_session_id},
        );
        my $max_requests = $self->env_value('EVEN_CODEX_SERVER_MAX_REQUESTS');
        $server->serve(
            defined $max_requests && $max_requests ne q{}
              ? ( max_requests => 0 + $max_requests )
              : ()
        );
        return 0;
    };
    if ( my $error = $@ ) {
        chomp $error;
        print { $self->{stderr_fh} } "$error\n";
        return 2;
    }
    return $code;
}

sub execute_start_add {
    my ( $self, @argv ) = @_;
    die "Usage: dashboard even-codex.start add <codex-session-id>\n" if @argv != 1;
    my $workspace_ref = $self->workspace_ref;
    my $codex_session_id = $argv[0];

    Even::Codex::State::save_pairing(
        env              => $self->{env},
        workspace_ref    => $workspace_ref,
        codex_session_id => $codex_session_id,
    );

    return {
        mode             => 'start',
        action           => 'add',
        workspace_ref    => $workspace_ref,
        codex_session_id => $codex_session_id,
    };
}

sub start_plan {
    my ($self) = @_;
    my $workspace_ref = $self->workspace_ref;
    my $codex_session_id = Even::Codex::State::load_pairing(
        env           => $self->{env},
        workspace_ref => $workspace_ref,
    );

    die "No even-codex pairing exists for workspace $workspace_ref\n"
      if !defined $codex_session_id || $codex_session_id eq q{};

    my $bind_host = $self->env_value('EVEN_CODEX_HOST') || '0.0.0.0';
    my $port = $self->env_value('EVEN_CODEX_PORT') || 6789;
    my $advertised_host = $self->env_value('EVEN_CODEX_ADVERTISE_HOST') || '127.0.0.1';

    return {
        mode             => 'start',
        action           => 'serve',
        workspace_ref    => $workspace_ref,
        codex_session_id => $codex_session_id,
        bind_host        => $bind_host,
        advertised_host  => $advertised_host,
        port             => 0 + $port,
        health_url       => 'http://' . $advertised_host . q{:} . $port . '/health',
        bootstrap_url    => 'http://' . $advertised_host . q{:} . $port . '/bootstrap',
        plugin_url       => 'http://' . $advertised_host . q{:} . $port . '/plugin/',
    };
}

sub workspace_ref {
    my ($self) = @_;
    my $workspace_ref = $self->env_value('WORKSPACE_REF');
    if ( !defined $workspace_ref || $workspace_ref eq q{} ) {
        $workspace_ref = $self->env_value('TICKET_REF');
    }
    die "WORKSPACE_REF or TICKET_REF is required\n" if !defined $workspace_ref || $workspace_ref eq q{};
    return $workspace_ref;
}

sub env_value {
    my ( $self, $key ) = @_;
    return $self->{env}->{$key};
}

1;
