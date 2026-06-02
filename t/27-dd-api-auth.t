use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use Encode qw(decode FB_CROAK);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use HTTP::Request::Common qw(POST);
use JSON::PP qw(decode_json);
use Test::More;
use URI::Escape qw(uri_escape);

plan skip_all => 'Developer Dashboard modules are not available in this environment'
  if !eval {
      require Developer::Dashboard::Auth;
      require Developer::Dashboard::Config;
      require Developer::Dashboard::FileRegistry;
      require Developer::Dashboard::PageRuntime;
      require Developer::Dashboard::PageStore;
      require Developer::Dashboard::PathRegistry;
      require Developer::Dashboard::SessionStore;
      require Developer::Dashboard::SkillManager;
      require Developer::Dashboard::Web::App;
      require Developer::Dashboard::Web::DancerApp;
      require Local::PSGITest;
      1;
  };

use lib 'lib';
use Even::Codex::State ();

sub decode_body_text {
    my ($body) = @_;
    return $body if !defined $body || utf8::is_utf8($body);
    return decode( 'UTF-8', $body, FB_CROAK );
}

sub drain_stream_body {
    my ($body) = @_;
    return $body if ref($body) ne 'HASH' || ref( $body->{stream} ) ne 'CODE';
    my $output = '';
    $body->{stream}->( sub { $output .= $_[0] if defined $_[0] } );
    return $output;
}

sub form_body {
    my (@pairs) = @_;
    my @encoded;
    while (@pairs) {
        my ( $name, $value ) = splice @pairs, 0, 2;
        push @encoded, uri_escape($name) . '=' . uri_escape( defined $value ? $value : '' );
    }
    return join '&', @encoded;
}

sub write_session_file {
    my ( $home, $session_id ) = @_;
    my $dir = File::Spec->catdir( $home, '.codex', 'sessions', '2026', '06', '02' );
    make_path($dir);
    my $path = File::Spec->catfile( $dir, "session-$session_id.jsonl" );
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} qq|{"type":"session_meta","payload":{"title":"DD API Session"}}\n|;
    print {$fh} qq|{"type":"event_msg","payload":{"type":"user_message","message":"hi from dd api"}}\n|;
    print {$fh} qq|{"type":"event_msg","payload":{"type":"agent_message","message":"working from dd api"}}\n|;
    print {$fh} qq|{"payload":{"type":"message","role":"assistant","content":[{"text":"hello from dd api"}]}}\n|;
    close $fh or die "Unable to close $path: $!";
    return $path;
}

my $home = tempdir( CLEANUP => 1 );
local $ENV{HOME} = $home;
make_path( File::Spec->catdir( $home, '.developer-dashboard', 'config' ) );

open my $api_fh, '>', File::Spec->catfile( $home, '.developer-dashboard', 'config', 'api.json' )
  or die "Unable to write runtime api.json: $!";
print {$api_fh} qq|{
  "even-codex-connector": {
    "secret": "@{[ sha256_hex('proof-secret') ]}",
    "ajax": [
      "/ajax/even-codex/bootstrap",
      "/ajax/even-codex/health",
      "/ajax/even-codex/session",
      "/ajax/even-codex/prompt"
    ]
  }
}|;
close $api_fh or die "Unable to close runtime api.json: $!";

my $session_id = 'codex-dd-api-1';
write_session_file( $home, $session_id );
Even::Codex::State::save_pairing(
    env              => { HOME => $home },
    workspace_ref    => 'foobar',
    codex_session_id => $session_id,
);

my $launcher_log = File::Spec->catfile( $home, 'prompt-launcher.log' );
open my $launcher_fh, '>', $launcher_log or die "Unable to write launcher log: $!";
close $launcher_fh or die "Unable to close launcher log: $!";
my $launcher = File::Spec->catfile( $home, 'fake-launcher.sh' );
open my $script_fh, '>', $launcher or die "Unable to write fake launcher: $!";
print {$script_fh} <<"SH";
#!/usr/bin/env bash
set -eu
printf '%s|%s\\n' "\$1" "\$2" >> "$launcher_log"
SH
close $script_fh or die "Unable to close fake launcher: $!";
chmod 0755, $launcher or die "Unable to chmod fake launcher: $!";
local $ENV{EVEN_CODEX_QUERY_LAUNCHER} = $launcher;

my $paths = Developer::Dashboard::PathRegistry->new( home => $home );
my $files = Developer::Dashboard::FileRegistry->new( paths => $paths );
my $config = Developer::Dashboard::Config->new( files => $files, paths => $paths );
my $store = Developer::Dashboard::PageStore->new( paths => $paths );
my $runtime = Developer::Dashboard::PageRuntime->new( paths => $paths );
my $auth = Developer::Dashboard::Auth->new( files => $files, paths => $paths );
my $sessions = Developer::Dashboard::SessionStore->new( paths => $paths );
my $skill_manager = Developer::Dashboard::SkillManager->new( paths => $paths );
my $install = $skill_manager->install( 'file://' . File::Spec->rel2abs('.') );
ok( !$install->{error}, 'even-codex installs into the temporary DD home for backend auth proof' )
  or diag $install->{error};

my $app = Developer::Dashboard::Web::App->new(
    auth     => $auth,
    config   => $config,
    pages    => $store,
    runtime  => $runtime,
    sessions => $sessions,
);

my $helper_host = 'dashboard-helper.example:7890';

my ( $missing_code, $missing_type, $missing_body ) = @{ $app->handle(
    path        => '/ajax/even-codex/bootstrap',
    query       => 'workspace_ref=foobar',
    remote_addr => '127.0.0.1',
    headers     => { host => $helper_host },
) };
is( $missing_code, 403, 'registered even-codex bootstrap route rejects missing API credentials on helper hosts' );
like( $missing_type, qr/application\/json/, 'missing API credentials return JSON' );
is_deeply( decode_json( decode_body_text($missing_body) ), { status => 'forbidden' }, 'missing API credentials return the forbidden payload' );

my ( $wrong_code, undef, $wrong_body ) = @{ $app->handle(
    path        => '/ajax/even-codex/session',
    query       => 'workspace_ref=foobar',
    remote_addr => '127.0.0.1',
    headers     => {
        host              => $helper_host,
        'x-dd-api-key'    => 'even-codex-connector',
        'x-dd-api-secret' => 'wrong-secret',
    },
) };
is( $wrong_code, 403, 'registered even-codex session route rejects wrong API credentials' );
is_deeply( decode_json( decode_body_text($wrong_body) ), { status => 'forbidden' }, 'wrong API credentials keep the forbidden payload' );

my ( $bootstrap_code, $bootstrap_type, $bootstrap_body ) = @{ $app->handle(
    path        => '/ajax/even-codex/bootstrap',
    query       => 'workspace_ref=foobar',
    remote_addr => '127.0.0.1',
    headers     => {
        host              => $helper_host,
        'x-dd-api-key'    => 'even-codex-connector',
        'x-dd-api-secret' => 'proof-secret',
    },
) };
is( $bootstrap_code, 200, 'registered even-codex bootstrap route accepts matching DD API credentials' );
like( $bootstrap_type, qr/application\/json/, 'bootstrap keeps its JSON content type under DD API auth' );
like( decode_body_text( drain_stream_body($bootstrap_body) ), qr/"workspace_ref":"foobar"/, 'bootstrap returns the paired workspace payload under DD API auth' );

my ( $session_code, $session_type, $session_body ) = @{ $app->handle(
    path        => '/ajax/even-codex/session',
    query       => 'workspace_ref=foobar',
    remote_addr => '127.0.0.1',
    headers     => {
        host              => $helper_host,
        'x-dd-api-key'    => 'even-codex-connector',
        'x-dd-api-secret' => 'proof-secret',
    },
) };
is( $session_code, 200, 'registered even-codex session route accepts matching DD API credentials' );
like( $session_type, qr/application\/json/, 'session keeps its JSON content type under DD API auth' );
like( decode_body_text( drain_stream_body($session_body) ), qr/"last_assistant_message":"hello from dd api"/, 'session returns the transcript payload under DD API auth' );

my $helper_user = $auth->add_user( username => 'helper', password => 'helper-pass-123', role => 'helper' );
ok( $helper_user->{username} eq 'helper', 'temporary helper user was created for helper-session proof' );

my ( $login_code, undef, undef, $login_headers ) = @{ $app->handle(
    path        => '/login',
    method      => 'POST',
    body        => form_body( username => 'helper', password => 'helper-pass-123' ),
    remote_addr => '127.0.0.1',
    headers     => { host => $helper_host },
) };
is( $login_code, 302, 'helper login succeeds on the DD login route' );
like( $login_headers->{'Set-Cookie'}, qr/^dashboard_session=/, 'helper login returns a DD session cookie' );

my ( $helper_session_code, undef, $helper_session_body ) = @{ $app->handle(
    path        => '/ajax/even-codex/bootstrap',
    query       => 'workspace_ref=foobar',
    remote_addr => '127.0.0.1',
    headers     => {
        host   => $helper_host,
        cookie => $login_headers->{'Set-Cookie'},
    },
) };
is( $helper_session_code, 200, 'registered even-codex bootstrap route still works by helper session without API headers' );
like( decode_body_text( drain_stream_body($helper_session_body) ), qr/"codex_session_id":"codex-dd-api-1"/, 'helper session receives the paired session payload' );

my $psgi_app = Developer::Dashboard::Web::DancerApp->build_psgi_app( app => $app );
Local::PSGITest::test_psgi( $psgi_app, sub {
    my ($cb) = @_;

    my $bootstrap_res = $cb->(
        POST(
            'http://127.0.0.1/ajax/even-codex/prompt?workspace_ref=foobar',
            Host              => $helper_host,
            'X-DD-API-Key'    => 'even-codex-connector',
            'X-DD-API-Secret' => 'proof-secret',
            Content_Type      => 'application/x-www-form-urlencoded',
            Content           => 'query=ship+status',
        )
    );

    is( $bootstrap_res->code, 200, 'PSGI adapter forwards DD API-auth headers to the even-codex prompt route' );
    like( decode_body_text( $bootstrap_res->content ), qr/"queued_query":"ship status"/, 'prompt route queues the submitted prompt through the DD API-auth path' );
} );

my $launcher_output = do {
    open my $fh, '<', $launcher_log or die "Unable to read launcher log: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close launcher log: $!";
    $text;
};
like( $launcher_output, qr/\Q$session_id\E\|ship status/, 'prompt route uses the disposable runtime launcher when DD API auth succeeds' );

done_testing;
