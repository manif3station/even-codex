package Even::Codex::Transcript;

use strict;
use warnings;

use autodie qw(open close);
use File::Find qw(find);
use File::Spec;
use JSON::PP qw(decode_json);

our $VERSION = '0.15';

sub session_snapshot {
    my (%args) = @_;
    my $session_id = $args{session_id};
    die "Codex session id is required\n" if !defined $session_id || $session_id eq q{};

    my $env = $args{env} || \%ENV;
    my $codex_home = _codex_home($env);
    my $session_file = _session_file_for_id( $codex_home, $session_id );

    return {
        ok                     => 0,
        session_id             => $session_id,
        session_file           => q{},
        title                  => q{},
        last_user_message      => q{},
        last_assistant_message => q{},
    } if !defined $session_file;

    open my $fh, '<', $session_file;
    my $snapshot = {
        ok                     => 1,
        session_id             => $session_id,
        session_file           => $session_file,
        title                  => q{},
        last_user_message      => q{},
        last_assistant_message => q{},
    };

    while ( my $line = <$fh> ) {
        chomp $line;
        next if $line eq q{};
        my $entry = eval { decode_json($line) };
        next if !$entry || ref $entry ne 'HASH';
        _merge_entry_into_snapshot( $snapshot, $entry );
    }

    close $fh;
    return $snapshot;
}

sub _codex_home {
    my ($env) = @_;
    return $env->{EVEN_CODEX_CODEX_HOME}
      if defined $env->{EVEN_CODEX_CODEX_HOME} && $env->{EVEN_CODEX_CODEX_HOME} ne q{};

    my $home = $env->{HOME} || die "HOME is required\n";
    return File::Spec->catdir( $home, '.codex' );
}

sub _session_file_for_id {
    my ( $codex_home, $session_id ) = @_;
    my $sessions_root = File::Spec->catdir( $codex_home, 'sessions' );
    return if !-d $sessions_root;

    my $match;
    find(
        {
            no_chdir => 1,
            wanted   => sub {
                return if !-f $_;
                return if $_ !~ /\Q$session_id\E\.jsonl\z/;
                $match = $_;
            },
        },
        $sessions_root,
    );

    return $match;
}

sub _merge_entry_into_snapshot {
    my ( $snapshot, $entry ) = @_;

    if ( $entry->{type} && $entry->{type} eq 'session_meta' && ref $entry->{payload} eq 'HASH' ) {
        my $title = $entry->{payload}{title};
        $snapshot->{title} = $title if defined $title && $title ne q{};
        return;
    }

    if ( $entry->{type} && $entry->{type} eq 'event_msg' && ref $entry->{payload} eq 'HASH' ) {
        return if !$entry->{payload}{type} || $entry->{payload}{type} ne 'user_message';
        my $message = $entry->{payload}{message};
        $snapshot->{last_user_message} = $message if defined $message && $message ne q{};
        return;
    }

    return if !$entry->{payload} || ref $entry->{payload} ne 'HASH';
    return if !$entry->{payload}{type} || $entry->{payload}{type} ne 'message';
    return if !$entry->{payload}{role} || $entry->{payload}{role} ne 'assistant';
    return if ref $entry->{payload}{content} ne 'ARRAY';

    my @parts;
    for my $content ( @{ $entry->{payload}{content} } ) {
        next if ref $content ne 'HASH';
        next if !$content->{text};
        push @parts, $content->{text};
    }

    $snapshot->{last_assistant_message} = join q{ }, @parts if @parts;
    return;
}

1;
