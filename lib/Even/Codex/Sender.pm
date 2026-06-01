package Even::Codex::Sender;

use strict;
use warnings;

use IO::Handle ();
use IPC::Open3 ();
use Symbol qw(gensym);

our $VERSION = '0.28';

sub new {
    my ( $class, %args ) = @_;
    return bless {
        ps_lines_provider => $args{ps_lines_provider},
        tty_writer        => $args{tty_writer},
        command_runner    => $args{command_runner},
        command_capture   => $args{command_capture},
        display           => $args{display},
        env               => $args{env} || \%ENV,
    }, $class;
}

sub submit_prompt {
    my ( $self, %args ) = @_;
    my $session_id = $args{session_id};
    my $prompt = $args{prompt};

    die "Codex session id is required\n" if !defined $session_id || $session_id eq q{};
    die "Prompt is required\n" if !defined $prompt || $prompt eq q{};

    my $launcher = $self->{env}{EVEN_CODEX_QUERY_LAUNCHER};
    if ( defined $launcher && $launcher ne q{} ) {
        return $self->_launch_prompt(
            launcher   => $launcher,
            session_id => $session_id,
            prompt     => $prompt,
        );
    }

    my $target = $self->find_session_target( session_id => $session_id );
    my $tty = $target->{tty};

    if ( defined $target->{xterm_pid} ) {
        my $window_id = $self->find_xterm_window_id( xterm_pid => $target->{xterm_pid} );
        if ( defined $window_id ) {
            $self->_type_into_window(
                window_id => $window_id,
                prompt    => $prompt,
            );
            return {
                ok         => 1,
                tty        => $tty,
                window_id  => $window_id,
                session_id => $session_id,
                prompt     => $prompt,
            };
        }
    }

    $self->_write_to_tty( $tty, $prompt );

    return {
        ok         => 1,
        tty        => $tty,
        session_id => $session_id,
        prompt     => $prompt,
    };
}

sub _launch_prompt {
    my ( $self, %args ) = @_;
    my $launcher = $args{launcher};
    my $session_id = $args{session_id};
    my $prompt = $args{prompt};

    my $tty = q{};
    my $target = eval { $self->find_session_target( session_id => $session_id ) };
    if ( $target && ref $target eq 'HASH' ) {
        $tty = $target->{tty} || q{};
    }

    $self->_run_command( $launcher, $session_id, $prompt );

    return {
        ok          => 1,
        tty         => $tty,
        launch_mode => 'resume_xterm',
        session_id  => $session_id,
        prompt      => $prompt,
    };
}

sub find_session_tty {
    my ( $self, %args ) = @_;
    return $self->find_session_target(%args)->{tty};
}

sub find_session_target {
    my ( $self, %args ) = @_;
    my $session_id = $args{session_id};
    die "Codex session id is required\n" if !defined $session_id || $session_id eq q{};

    my @lines = $self->_ps_lines();
    my $tty;
    my $xterm_pid;

    for my $line (@lines) {
        chomp $line;
        next if $line !~ /\Q$session_id\E/;
        if ( !defined $tty && $line =~ m{\A\s*(\d+)\s+(\S+)\s+(.+)\z} ) {
            my ( $pid, $candidate_tty, $args_text ) = ( $1, $2, $3 );
            if ( $candidate_tty ne '?' && $args_text =~ m{(?:^|\s)(?:codex|node\s+\S*codex)(?:\s|$)|/codex(?:\s|$)} ) {
                $tty = $candidate_tty;
            }
            if ( !defined $xterm_pid && $args_text =~ /(?:^|\s)xterm(?:\s|$)/ ) {
                $xterm_pid = $pid;
            }
            next;
        }
        if ( !defined $tty ) {
            next if $line !~ m{(?:^|\s)(?:codex|node\s+\S*codex)(?:\s|$)|/codex(?:\s|$)};
            my ( $candidate_tty ) = split /\s+/, $line, 2;
            if ( $candidate_tty ne '?' && $candidate_tty ne q{} ) {
                $tty = $candidate_tty;
            }
        }
    }

    die "Unable to find an interactive Codex tty for session $session_id\n"
      if !defined $tty;

    return {
        tty       => $tty,
        xterm_pid => $xterm_pid,
    };
}

sub _ps_lines {
    my ($self) = @_;
    if ( $self->{ps_lines_provider} ) {
        my $lines = $self->{ps_lines_provider}->();
        return @{$lines} if ref $lines eq 'ARRAY';
        return split /\n/, $lines;
    }

    return qx(ps -eo pid=,tty=,args=);
}

sub find_xterm_window_id {
    my ( $self, %args ) = @_;
    my $xterm_pid = $args{xterm_pid};
    return undef if !defined $xterm_pid || $xterm_pid eq q{};

    my $output = $self->_capture_command( 'xdotool', 'search', '--pid', $xterm_pid );
    return undef if !defined $output || $output eq q{};

    my @window_ids = grep { $_ ne q{} } split /\n/, $output;
    return $window_ids[-1];
}

sub _type_into_window {
    my ( $self, %args ) = @_;
    my $window_id = $args{window_id};
    my $prompt = $args{prompt};

    $self->_run_command( 'xdotool', 'windowactivate', '--sync', $window_id );
    $self->_run_command( 'xdotool', 'key', '--window', $window_id, 'ctrl+u' );
    $self->_run_command( 'xdotool', 'type', '--delay', '1', '--window', $window_id, '--', $prompt );
    $self->_run_command( 'xdotool', 'key', '--window', $window_id, 'Return' );
    return 1;
}

sub _run_command {
    my ( $self, @command ) = @_;
    if ( $self->{command_runner} ) {
        return $self->{command_runner}->(@command);
    }

    local $ENV{DISPLAY} = $self->{display} || $ENV{DISPLAY} || ':1';
    my $status = system @command;
    die "Command failed (@command): $!\n" if $status == -1;
    my $exit_code = $status >> 8;
    die "Command failed (@command) with exit code $exit_code\n" if $exit_code != 0;
    return 1;
}

sub _capture_command {
    my ( $self, @command ) = @_;
    if ( $self->{command_capture} ) {
        return $self->{command_capture}->(@command);
    }

    local $ENV{DISPLAY} = $self->{display} || $ENV{DISPLAY} || ':1';
    my $stderr = gensym;
    my $pid = IPC::Open3::open3( undef, my $stdout, $stderr, @command );
    my $output = do { local $/; <$stdout> };
    my $error = do { local $/; <$stderr> };
    waitpid $pid, 0;
    my $exit_code = $? >> 8;
    die "Command failed (@command) with exit code $exit_code: $error\n" if $exit_code != 0;
    return $output;
}

sub _write_to_tty {
    my ( $self, $tty, $prompt ) = @_;
    if ( $self->{tty_writer} ) {
        return $self->{tty_writer}->( $tty, $prompt );
    }

    my $tty_path = $tty;
    if ( $tty !~ m{\A/} ) {
        $tty_path = "/dev/$tty";
    }
    open my $tty_fh, '>', $tty_path
      or die "Unable to write to Codex tty $tty_path: $!";
    $tty_fh->autoflush(1);
    print {$tty_fh} $prompt . "\n";
    close $tty_fh;
    return 1;
}

1;
