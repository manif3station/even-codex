use strict;
use warnings;

use Test::More;

use lib 'lib';
use Even::Codex::Protocol;

my @event_types = Even::Codex::Protocol::event_types();
is(scalar @event_types, 11, 'event catalog count matches spec');
is($event_types[0], 'session.hello', 'first event type matches spec');
is($event_types[-1], 'delivery.retry', 'last event type matches spec');

my @fields = Even::Codex::Protocol::required_event_fields();
is_deeply(
    \@fields,
    [qw(event_id event_type session_id source_role timestamp sequence payload)],
    'required event fields match the contract'
);

my @commands = Even::Codex::Protocol::supported_even_commands();
is_deeply(
    \@commands,
    [qw(Status Resume Retry Stop)],
    'supported Even commands match the initial production slice'
);

my @modes = Even::Codex::Protocol::deployment_modes();
is_deeply(
    \@modes,
    [ 'lan-private', 'public-relay' ],
    'supported deployment modes cover LAN and public relay'
);

ok(Even::Codex::Protocol::supports_event_type('codex.final'), 'known event type is supported');
ok(!Even::Codex::Protocol::supports_event_type('codex.unknown'), 'unknown event type is rejected');
ok(!Even::Codex::Protocol::supports_event_type(undef), 'undefined event type is rejected');

done_testing;
