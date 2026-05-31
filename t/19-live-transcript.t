use strict;
use warnings FATAL => 'all';

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Socket::INET;
use JSON::PP qw(decode_json);
use Test::More;
use Time::HiRes qw(sleep);

use lib 'lib';
use Even::Codex::Server;
use Even::Codex::Transcript;

my $tmp = tempdir( CLEANUP => 1 );
my $codex_home = File::Spec->catdir( $tmp, '.codex' );
my $session_dir = File::Spec->catdir( $codex_home, 'sessions', '2026', '05', '31' );
make_path($session_dir);
my $session_id = '019e-live-transcript';
my $session_path = File::Spec->catfile( $session_dir, 'rollout-2026-05-31T17-10-00-' . $session_id . '.jsonl' );
open my $session_fh, '>', $session_path or die "Unable to open $session_path: $!";
print {$session_fh} <<'JSONL';
{"timestamp":"2026-05-31T17:10:00.000Z","type":"session_meta","payload":{"id":"019e-live-transcript","cwd":"/tmp/foobar","title":"hi"}}
{"timestamp":"2026-05-31T17:10:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"hi"}}
{"timestamp":"2026-05-31T17:10:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hello from codex"}],"phase":"final_answer"}}
JSONL
close $session_fh or die "Unable to close $session_path: $!";

my %transcript_env = (
    HOME                  => $tmp,
    EVEN_CODEX_CODEX_HOME => $codex_home,
);

my $snapshot = Even::Codex::Transcript::session_snapshot(
    env        => \%transcript_env,
    session_id => $session_id,
);
ok( $snapshot->{ok}, 'transcript snapshot reports ok for a present session' );
is( $snapshot->{session_id}, $session_id, 'transcript snapshot reports the session id' );
is( $snapshot->{last_user_message}, 'hi', 'transcript snapshot reads the latest user message' );
is( $snapshot->{last_assistant_message}, 'hello from codex', 'transcript snapshot reads the latest assistant message' );
is( $snapshot->{session_file}, $session_path, 'transcript snapshot reports the matching session file path' );

my $port = _reserve_port();
my $pid = fork();
die "Unable to fork even-codex transcript test server: $!" if !defined $pid;

if ( $pid == 0 ) {
    my $server = Even::Codex::Server->new(
        host             => '127.0.0.1',
        port             => $port,
        advertised_host  => '127.0.0.1',
        workspace_ref    => 'foobar',
        codex_session_id => $session_id,
        env              => \%transcript_env,
    );
    $server->serve( max_requests => 2 );
    exit 0;
}

eval {
    _wait_for_port($port);
    my $session = _http_get( $port, '/session' );
    is( $session->{status}, 200, '/session returns HTTP 200 for a present transcript' );
    my $payload = decode_json( $session->{body} );
    is( $payload->{last_user_message}, 'hi', '/session returns the latest user message' );
is( $payload->{last_assistant_message}, 'hello from codex', '/session returns the latest assistant message' );
};
my $error = $@;

kill 'TERM', $pid;
waitpid $pid, 0;

die $error if $error;

my $coverage_root = tempdir( CLEANUP => 1 );
my $coverage_codex_home = File::Spec->catdir( $coverage_root, '.codex' );
my $coverage_session_dir = File::Spec->catdir( $coverage_codex_home, 'sessions', '2026', '05', '31' );
make_path($coverage_session_dir);

my $coverage_session_id = '019e-live-transcript-coverage';
my $coverage_session_path = File::Spec->catfile(
    $coverage_session_dir,
    'rollout-2026-05-31T17-20-00-' . $coverage_session_id . '.jsonl'
);
my $other_session_path = File::Spec->catfile(
    $coverage_session_dir,
    'rollout-2026-05-31T17-20-00-019e-someone-else.jsonl'
);
open my $other_fh, '>', $other_session_path;
print {$other_fh} "{\"type\":\"session_meta\",\"payload\":{\"title\":\"other\"}}\n";
close $other_fh;

open my $coverage_fh, '>', $coverage_session_path;
print {$coverage_fh} "\n";
print {$coverage_fh} "{not json}\n";
print {$coverage_fh} "[]\n";
print {$coverage_fh} "{\"payload\":{\"title\":\"missing type\"}}\n";
print {$coverage_fh} "{\"type\":\"session_meta\",\"payload\":\"not-a-hash\"}\n";
print {$coverage_fh} "{\"type\":\"session_meta\",\"payload\":{}}\n";
print {$coverage_fh} "{\"type\":\"session_meta\",\"payload\":{\"title\":\"\"}}\n";
print {$coverage_fh} "{\"type\":\"session_meta\",\"payload\":{\"title\":\"Coverage title\"}}\n";
print {$coverage_fh} "{\"type\":\"event_msg\",\"payload\":\"not-a-hash\"}\n";
print {$coverage_fh} "{\"type\":\"event_msg\",\"payload\":{}}\n";
print {$coverage_fh} "{\"type\":\"event_msg\",\"payload\":{\"type\":\"status\",\"message\":\"ignore\"}}\n";
print {$coverage_fh} "{\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\"}}\n";
print {$coverage_fh} "{\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\",\"message\":\"\"}}\n";
print {$coverage_fh} "{\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\",\"message\":\"hi\"}}\n";
print {$coverage_fh} "{\"type\":\"response_item\"}\n";
print {$coverage_fh} "{\"type\":\"response_item\",\"payload\":[]}\n";
print {$coverage_fh} "{\"type\":\"response_item\",\"payload\":{}}\n";
print {$coverage_fh} "{\"type\":\"response_item\",\"payload\":{\"type\":\"tool_call\"}}\n";
print {$coverage_fh} "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\"}}\n";
print {$coverage_fh} "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\"}}\n";
print {$coverage_fh} "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":{}}}\n";
print {$coverage_fh} "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[\"raw\",{}, {\"type\":\"output_text\"}]}}\n";
print {$coverage_fh} "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"hello from codex\"}]}}\n";
close $coverage_fh;

my %coverage_env = (
    HOME                  => $coverage_root,
    EVEN_CODEX_CODEX_HOME => $coverage_codex_home,
);

my $coverage_snapshot = Even::Codex::Transcript::session_snapshot(
    env        => \%coverage_env,
    session_id => $coverage_session_id,
);
ok( $coverage_snapshot->{ok}, 'coverage transcript snapshot reports ok for a present session with mixed entries' );
is( $coverage_snapshot->{title}, 'Coverage title', 'coverage transcript keeps the last non-empty session title' );
is( $coverage_snapshot->{last_user_message}, 'hi', 'coverage transcript keeps the last non-empty user message' );
is( $coverage_snapshot->{last_assistant_message}, 'hello from codex', 'coverage transcript keeps the last assistant text' );
is( dirname( $coverage_snapshot->{session_file} ), $coverage_session_dir, 'coverage transcript resolves the matching session file inside the sessions tree' );

my $missing_snapshot = Even::Codex::Transcript::session_snapshot(
    env        => \%coverage_env,
    session_id => '019e-missing-transcript',
);
ok( !$missing_snapshot->{ok}, 'missing transcript snapshot reports not-ok when the paired session file is absent' );
is( $missing_snapshot->{last_user_message}, q{}, 'missing transcript snapshot leaves the user message blank' );
is( $missing_snapshot->{last_assistant_message}, q{}, 'missing transcript snapshot leaves the assistant message blank' );

my $fallback_root = tempdir( CLEANUP => 1 );
my $fallback_codex_home = File::Spec->catdir( $fallback_root, '.codex' );
my $fallback_session_dir = File::Spec->catdir( $fallback_codex_home, 'sessions', '2026', '05', '31' );
make_path($fallback_session_dir);
my $fallback_session_id = '019e-live-transcript-fallback';
my $fallback_session_path = File::Spec->catfile(
    $fallback_session_dir,
    'rollout-2026-05-31T17-30-00-' . $fallback_session_id . '.jsonl'
);
open my $fallback_fh, '>', $fallback_session_path;
print {$fallback_fh} "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"fallback reply\"}]}}\n";
close $fallback_fh;

{
    local $ENV{EVEN_CODEX_CODEX_HOME} = $fallback_codex_home;
    local $ENV{HOME} = $fallback_root;
    my $fallback_snapshot = Even::Codex::Transcript::session_snapshot(
        session_id => $fallback_session_id,
    );
    ok( $fallback_snapshot->{ok}, 'transcript snapshot falls back to the process environment when no explicit env hash is passed' );
    is( $fallback_snapshot->{last_assistant_message}, 'fallback reply', 'env-fallback transcript reads the mounted session reply' );
}

{
    local $ENV{EVEN_CODEX_CODEX_HOME} = q{};
    local $ENV{HOME} = q{};
    my $missing_session_error = eval {
        Even::Codex::Transcript::session_snapshot( env => {}, session_id => q{} );
        1;
    } ? q{} : $@;
    like( $missing_session_error, qr/Codex session id is required/, 'session_snapshot fails explicitly when the session id is missing' );

    my $undefined_session_error = eval {
        Even::Codex::Transcript::session_snapshot( env => {} );
        1;
    } ? q{} : $@;
    like( $undefined_session_error, qr/Codex session id is required/, 'session_snapshot fails explicitly when the session id is undefined' );

    my $missing_home_error = eval {
        Even::Codex::Transcript::session_snapshot(
            env        => {},
            session_id => '019e-needs-home',
        );
        1;
    } ? q{} : $@;
    like( $missing_home_error, qr/HOME is required/, 'session_snapshot fails explicitly when no Codex home or HOME is available' );
}

{
    my $empty_override_root = tempdir( CLEANUP => 1 );
    my $empty_override_home = File::Spec->catdir( $empty_override_root, '.codex' );
    my $empty_override_session_dir = File::Spec->catdir( $empty_override_home, 'sessions', '2026', '05', '31' );
    make_path($empty_override_session_dir);
    my $empty_override_session_id = '019e-live-transcript-empty-override';
    my $empty_override_path = File::Spec->catfile(
        $empty_override_session_dir,
        'rollout-2026-05-31T17-40-00-' . $empty_override_session_id . '.jsonl'
    );
    open my $empty_override_fh, '>', $empty_override_path;
    print {$empty_override_fh} "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"empty override reply\"}]}}\n";
    close $empty_override_fh;

    my $empty_override_snapshot = Even::Codex::Transcript::session_snapshot(
        env => {
            HOME                  => $empty_override_root,
            EVEN_CODEX_CODEX_HOME => q{},
        },
        session_id => $empty_override_session_id,
    );
    ok( $empty_override_snapshot->{ok}, 'transcript snapshot falls back to HOME when EVEN_CODEX_CODEX_HOME is defined but empty' );
    is( $empty_override_snapshot->{last_assistant_message}, 'empty override reply', 'HOME fallback still reads the assistant reply when the explicit codex home override is empty' );
}

done_testing;

sub _http_get {
    my ( $port, $path ) = @_;
    my $socket = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
        Proto    => 'tcp',
    ) or die "Unable to connect to test server: $!";

    print {$socket} "GET $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\nConnection: close\r\n\r\n";
    my $raw = do { local $/; <$socket> };
    close $socket;

    my ( $head, $body ) = split /\r?\n\r?\n/, $raw, 2;
    my ($status) = $head =~ m{\AHTTP/1\.1\s+(\d+)};
    return {
        status => 0 + $status,
        body   => defined $body ? $body : q{},
    };
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
