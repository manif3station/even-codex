package Even::Codex::Transcript;

use strict;
use warnings;

use autodie qw(open close);
use File::Find qw(find);
use File::Spec;
use JSON::PP qw(decode_json);

our $VERSION = '0.24';

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
        last_assistant_progress_message => q{},
        last_assistant_message => q{},
        recent_turns           => [],
    } if !defined $session_file;

    open my $fh, '<', $session_file;
    my $snapshot = {
        ok                     => 1,
        session_id             => $session_id,
        session_file           => $session_file,
        title                  => q{},
        last_user_message      => q{},
        last_assistant_progress_message => q{},
        last_assistant_message => q{},
        pending_user_message   => q{},
        pending_progress_message => q{},
        recent_turns           => [],
    };

    while ( my $line = <$fh> ) {
        chomp $line;
        next if $line eq q{};
        my $entry = eval { decode_json($line) };
        next if !$entry || ref $entry ne 'HASH';
        _merge_entry_into_snapshot( $snapshot, $entry );
    }

    close $fh;
    delete $snapshot->{pending_user_message};
    delete $snapshot->{pending_progress_message};
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
        if ( $entry->{payload}{type} && $entry->{payload}{type} eq 'user_message' ) {
            my $message = $entry->{payload}{message};
            if ( defined $message && $message ne q{} ) {
                $snapshot->{last_user_message} = $message;
                $snapshot->{pending_user_message} = $message;
                $snapshot->{pending_progress_message} = q{};
            }
        }
        elsif ( $entry->{payload}{type} && $entry->{payload}{type} eq 'agent_message' ) {
            my $message = $entry->{payload}{message};
            if ( defined $message && $message ne q{} ) {
                $snapshot->{last_assistant_progress_message} = $message;
                $snapshot->{pending_progress_message} = $message;
            }
        }
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

    return if !@parts;

    my $message = join q{ }, @parts;
    if ( defined $entry->{payload}{phase} && $entry->{payload}{phase} eq 'commentary' ) {
        $snapshot->{last_assistant_progress_message} = $message;
        $snapshot->{pending_progress_message} = $message;
        return;
    }

    $snapshot->{last_assistant_message} = $message;
    _record_recent_turn(
        $snapshot,
        prompt   => $snapshot->{pending_user_message},
        progress => $snapshot->{pending_progress_message},
        reply    => $message,
    );
    $snapshot->{pending_progress_message} = q{};
    return;
}

sub _record_recent_turn {
    my ( $snapshot, %args ) = @_;
    return if !defined $args{prompt} || $args{prompt} eq q{};
    return if !defined $args{reply} || $args{reply} eq q{};

    push @{ $snapshot->{recent_turns} }, {
        prompt   => $args{prompt},
        progress => $args{progress} || q{},
        reply    => $args{reply},
    };

    shift @{ $snapshot->{recent_turns} } while @{ $snapshot->{recent_turns} } > 3;
    return;
}

1;
