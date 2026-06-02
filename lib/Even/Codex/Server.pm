package Even::Codex::Server;

use strict;
use warnings;

use IO::Socket::INET;
use JSON::PP qw(decode_json encode_json);

use Even::Codex::Connector ();
use Even::Codex::Plugin ();
use Even::Codex::Sender ();

our $VERSION = '0.45';

sub new {
    my ( $class, %args ) = @_;
    die "Host is required\n" if !defined $args{host} || $args{host} eq q{};
    die "Port is required\n" if !defined $args{port} || $args{port} eq q{};
    die "Workspace ref is required\n" if !defined $args{workspace_ref} || $args{workspace_ref} eq q{};
    die "Codex session id is required\n" if !defined $args{codex_session_id} || $args{codex_session_id} eq q{};

    my $advertised_host = '127.0.0.1';
    if ( defined $args{advertised_host} && $args{advertised_host} ne q{} ) {
        $advertised_host = $args{advertised_host};
    }

    my $env = \%ENV;
    if ( $args{env} ) {
        $env = $args{env};
    }

    my $sender = Even::Codex::Sender->new();
    if ( $args{sender} ) {
        $sender = $args{sender};
    }

    return bless {
        host             => $args{host},
        port             => $args{port},
        advertised_host  => $advertised_host,
        workspace_ref    => $args{workspace_ref},
        codex_session_id => $args{codex_session_id},
        env              => $env,
        sender           => $sender,
    }, $class;
}

sub bootstrap_payload {
    my ($self) = @_;
    my $payload = Even::Codex::Connector::bootstrap_payload(
        env              => $self->{env},
        workspace_ref    => $self->{workspace_ref},
        codex_session_id => $self->{codex_session_id},
        base_url         => $self->base_url,
        bind_host        => $self->{host},
        advertised_host  => $self->{advertised_host},
        port             => $self->{port},
    );
    $payload->{plugin_url} =~ s{(?<!/)\z}{/};
    return $payload;
}

sub health_payload {
    my ($self) = @_;
    return Even::Codex::Connector::health_payload(
        env             => $self->{env},
        workspace_ref   => $self->{workspace_ref},
        codex_session_id => $self->{codex_session_id},
        base_url        => $self->base_url,
        bind_host       => $self->{host},
        advertised_host => $self->{advertised_host},
        port            => $self->{port},
    );
}

sub base_url {
    my ($self) = @_;
    return 'http://' . $self->{advertised_host} . q{:} . $self->{port};
}

sub session_payload {
    my ($self) = @_;
    return Even::Codex::Connector::session_payload(
        env           => $self->{env},
        workspace_ref => $self->{workspace_ref},
        codex_session_id => $self->{codex_session_id},
    );
}

sub prompt_payload {
    my ( $self, %args ) = @_;
    my $query = $args{query};
    die "Query is required\n" if !defined $query || $query eq q{};

    return Even::Codex::Connector::prompt_payload(
        env              => $self->{env},
        sender           => $self->{sender},
        workspace_ref    => $self->{workspace_ref},
        codex_session_id => $self->{codex_session_id},
        query            => $query,
    );
}

sub serve {
    my ( $self, %args ) = @_;
    my $max_requests = $args{max_requests};
    $max_requests = 0 if !defined $max_requests;
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
    my $method = 'GET';
    my $path = '/';
    if ( defined $request ) {
        if ( $request =~ m{\A([A-Z]+)\s+(\S+) } ) {
            $method = $1;
            $path = $2;
        }
    }

    my %headers;
    while ( defined( my $line = <$client> ) ) {
        last if $line =~ /^\r?\n\z/;
        my ( $name, $value ) = split /:\s*/, $line, 2;
        next if !defined $value;
        $value =~ s/\r?\n\z//;
        $headers{ lc $name } = $value;
    }

    my $body = q{};
    if ( defined $headers{'content-length'} ) {
        if ( $headers{'content-length'} =~ /\A\d+\z/ ) {
            read $client, $body, $headers{'content-length'};
        }
    }

    my ( $status, $content_type, $response_body ) = eval { $self->_response_for_request( $method, $path, $body ) };
    if ( my $error = $@ ) {
        chomp $error;
        $status = 400;
        $content_type = 'application/json';
        $response_body = encode_json( { ok => 0, error => $error } );
    }

    print {$client} "HTTP/1.1 $status " . _status_text($status) . "\r\n";
    print {$client} "Content-Type: $content_type\r\n";
    print {$client} "Access-Control-Allow-Origin: *\r\n";
    print {$client} "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n";
    print {$client} "Access-Control-Allow-Headers: Content-Type\r\n";
    print {$client} "Content-Length: " . length($response_body) . "\r\n";
    print {$client} "Connection: close\r\n\r\n";
    print {$client} $response_body;
    close $client;
    return 1;
}

sub _response_for_request {
    my ( $self, $method, $path, $body ) = @_;

    if ( $method eq 'OPTIONS' ) {
        return ( 204, 'text/plain; charset=utf-8', q{} ) if $path eq '/prompt';
    }

    if ( $method eq 'POST' && $path eq '/prompt' ) {
        my $payload = {};
        if ( defined $body && $body ne q{} ) {
            $payload = decode_json($body);
        }
        die "Query is required\n" if ref $payload ne 'HASH';
        return ( 202, 'application/json', encode_json( $self->prompt_payload( query => $payload->{query} ) ) );
    }

    return ( 404, 'text/plain; charset=utf-8', 'not found' ) if $method ne 'GET';

    return ( 200, 'application/json', encode_json( $self->health_payload ) )
      if $path eq '/health';

    return ( 200, 'application/json', encode_json( $self->bootstrap_payload ) )
      if $path eq '/bootstrap';

    return ( 200, 'application/json', encode_json( $self->session_payload ) )
      if $path eq '/session';

    return ( 200, 'text/html; charset=utf-8', Even::Codex::Plugin::index_html() )
      if $path eq '/plugin';

    return ( 200, 'text/html; charset=utf-8', Even::Codex::Plugin::index_html() )
      if $path eq '/plugin/';

    return ( 200, 'application/json', Even::Codex::Plugin::asset_text('manifest.json') )
      if $path eq '/plugin/manifest.json';

    return ( 200, 'application/javascript; charset=utf-8', Even::Codex::Plugin::app_js() )
      if $path eq '/plugin/app.js';

    return ( 200, 'text/css; charset=utf-8', Even::Codex::Plugin::styles_css() )
      if $path eq '/plugin/styles.css';

    return ( 404, 'text/plain; charset=utf-8', 'not found' );
}

sub _status_text {
    my ($status) = @_;
    return 'OK' if $status == 200;
    return 'Accepted' if $status == 202;
    return 'No Content' if $status == 204;
    return 'Bad Request' if $status == 400;
    return 'Not Found';
}

1;
