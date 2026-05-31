package Even::Codex::Server;

use strict;
use warnings;

use IO::Socket::INET;
use JSON::PP qw(encode_json);

use Even::Codex::Plugin ();

our $VERSION = '0.07';

sub new {
    my ( $class, %args ) = @_;
    die "Host is required\n" if !defined $args{host} || $args{host} eq q{};
    die "Port is required\n" if !defined $args{port} || $args{port} eq q{};
    die "Workspace ref is required\n" if !defined $args{workspace_ref} || $args{workspace_ref} eq q{};
    die "Codex session id is required\n" if !defined $args{codex_session_id} || $args{codex_session_id} eq q{};

    return bless {
        host             => $args{host},
        port             => $args{port},
        advertised_host  => $args{advertised_host} || '127.0.0.1',
        workspace_ref    => $args{workspace_ref},
        codex_session_id => $args{codex_session_id},
    }, $class;
}

sub bootstrap_payload {
    my ($self) = @_;
    return {
        ok               => 1,
        workspace_ref    => $self->{workspace_ref},
        codex_session_id => $self->{codex_session_id},
        bind_host        => $self->{host},
        advertised_host  => $self->{advertised_host},
        port             => 0 + $self->{port},
        health_url       => $self->base_url . '/health',
        bootstrap_url    => $self->base_url . '/bootstrap',
        plugin_url       => $self->base_url . '/plugin/',
    };
}

sub health_payload {
    my ($self) = @_;
    my $bootstrap = $self->bootstrap_payload;
    return {
        ok               => 1,
        service          => 'even-codex',
        workspace_ref    => $bootstrap->{workspace_ref},
        codex_session_id => $bootstrap->{codex_session_id},
        port             => $bootstrap->{port},
    };
}

sub base_url {
    my ($self) = @_;
    return 'http://' . $self->{advertised_host} . q{:} . $self->{port};
}

sub serve {
    my ( $self, %args ) = @_;
    my $max_requests = $args{max_requests} || 0;
    my $handled = 0;

    my $server = IO::Socket::INET->new(
        LocalAddr => $self->{host},
        LocalPort => $self->{port},
        Listen    => 5,
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "Unable to start even-codex bridge on $self->{host}:$self->{port}: $!";

    local $SIG{TERM} = sub { close $server; exit 0 };
    local $SIG{PIPE} = 'IGNORE';

    while ( my $client = $server->accept ) {
        $handled += 1;
        $self->_handle_client($client);
        last if $max_requests && $handled >= $max_requests;
    }

    close $server;
    return 1;
}

sub _handle_client {
    my ( $self, $client ) = @_;
    my $request = <$client>;
    my $path = '/';
    if ( defined $request && $request =~ m{\AGET\s+(\S+) } ) {
        $path = $1;
    }

    while ( defined( my $line = <$client> ) ) {
        last if $line =~ /^\r?\n\z/;
    }

    my ( $status, $content_type, $body ) = $self->_response_for_path($path);
    print {$client} "HTTP/1.1 $status " . ( $status == 200 ? 'OK' : 'Not Found' ) . "\r\n";
    print {$client} "Content-Type: $content_type\r\n";
    print {$client} "Content-Length: " . length($body) . "\r\n";
    print {$client} "Connection: close\r\n\r\n";
    print {$client} $body;
    close $client;
    return 1;
}

sub _response_for_path {
    my ( $self, $path ) = @_;

    return ( 200, 'application/json', encode_json( $self->health_payload ) )
      if $path eq '/health';

    return ( 200, 'application/json', encode_json( $self->bootstrap_payload ) )
      if $path eq '/bootstrap';

    return ( 200, 'text/html; charset=utf-8', Even::Codex::Plugin::index_html() )
      if $path eq '/plugin' || $path eq '/plugin/';

    return ( 200, 'application/json', Even::Codex::Plugin::asset_text('manifest.json') )
      if $path eq '/plugin/manifest.json';

    return ( 200, 'application/javascript; charset=utf-8', Even::Codex::Plugin::app_js() )
      if $path eq '/plugin/app.js';

    return ( 200, 'text/css; charset=utf-8', Even::Codex::Plugin::styles_css() )
      if $path eq '/plugin/styles.css';

    return ( 404, 'text/plain; charset=utf-8', 'not found' );
}

1;
