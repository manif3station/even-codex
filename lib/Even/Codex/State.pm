package Even::Codex::State;

use strict;
use warnings;
use autodie qw(open close);

use File::Path qw(make_path);
use File::Spec;
use JSON::PP qw(decode_json encode_json);

our $VERSION = '0.24';

sub config_root {
    my (%args) = @_;
    my $env = $args{env} || \%ENV;
    return $env->{EVEN_CODEX_CONFIG_ROOT}
      if defined $env->{EVEN_CODEX_CONFIG_ROOT} && $env->{EVEN_CODEX_CONFIG_ROOT} ne q{};

    my $home = $env->{HOME} || die "HOME is required\n";
    return File::Spec->catdir( $home, '.developer-dashboard', 'configs', 'even-codex' );
}

sub runtime_root {
    my (%args) = @_;
    my $env = $args{env} || \%ENV;
    return $env->{EVEN_CODEX_RUNTIME_ROOT}
      if defined $env->{EVEN_CODEX_RUNTIME_ROOT} && $env->{EVEN_CODEX_RUNTIME_ROOT} ne q{};

    my $home = $env->{HOME} || die "HOME is required\n";
    return File::Spec->catdir( $home, '.developer-dashboard', 'state', 'even-codex' );
}

sub pairing_file {
    my (%args) = @_;
    return File::Spec->catfile( config_root(%args), 'workspace-pairings.json' );
}

sub load_pairings {
    my (%args) = @_;
    my $path = pairing_file(%args);
    return {} if !-f $path;

    open my $fh, '<', $path;
    local $/;
    my $raw = <$fh>;
    close $fh;

    my $payload = decode_json($raw);
    return ref $payload eq 'HASH' ? $payload : {};
}

sub save_pairing {
    my (%args) = @_;
    my $workspace_ref = $args{workspace_ref};
    my $codex_session_id = $args{codex_session_id};

    die "Workspace ref is required\n" if !defined $workspace_ref || $workspace_ref eq q{};
    die "Codex session id is required\n" if !defined $codex_session_id || $codex_session_id eq q{};

    my $root = config_root(%args);
    make_path($root) if !-d $root;

    my $pairings = load_pairings(%args);
    $pairings->{$workspace_ref} = $codex_session_id;

    my $path = pairing_file(%args);
    open my $fh, '>', $path;
    print {$fh} encode_json($pairings);
    close $fh;

    return $codex_session_id;
}

sub load_pairing {
    my (%args) = @_;
    my $workspace_ref = $args{workspace_ref};
    die "Workspace ref is required\n" if !defined $workspace_ref || $workspace_ref eq q{};

    my $pairings = load_pairings(%args);
    return $pairings->{$workspace_ref};
}

1;
