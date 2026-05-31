package Even::Codex::Protocol;

use strict;
use warnings;

our $VERSION = '0.15';

sub event_types {
    return (
        'session.hello',
        'session.pair',
        'session.heartbeat',
        'session.resume',
        'codex.commentary',
        'codex.final',
        'codex.error',
        'even.command',
        'even.prompt',
        'delivery.ack',
        'delivery.retry',
    );
}

sub required_event_fields {
    return (
        'event_id',
        'event_type',
        'session_id',
        'source_role',
        'timestamp',
        'sequence',
        'payload',
    );
}

sub supported_even_commands {
    return (
        'Status',
        'Resume',
        'Retry',
        'Stop',
    );
}

sub deployment_modes {
    return (
        'lan-private',
        'public-relay',
    );
}

sub supports_event_type {
    my ($event_type) = @_;

    for my $known (event_types()) {
        return 1 if defined $event_type && $event_type eq $known;
    }

    return 0;
}

1;
