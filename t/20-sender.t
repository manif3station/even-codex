use strict;
use warnings FATAL => 'all';

use Test::More;

use lib 'lib';
use Even::Codex::Sender;

{
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub {
            return [
                "101 pts/3 codex unrelated-session\n",
                "102 pts/4 python session-a worker\n",
                "103 ? xterm -hold -T Codex session-a -e bash -lc codex resume session-a\n",
                "104 pts/0 /opt/codex-cli/bin/codex resume session-a --cd /tmp/demo\n",
            ];
        },
    );

    is(
        $sender->find_session_tty( session_id => 'session-a' ),
        'pts/0',
        'sender resolves the interactive tty for the paired Codex session'
    );

    is_deeply(
        $sender->find_session_target( session_id => 'session-a' ),
        {
            tty       => 'pts/0',
            xterm_pid => '103',
        },
        'sender resolves both the interactive tty and paired xterm pid'
    );
}

{
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub { return "105 pts/6 /opt/codex-cli/bin/codex resume session-string\n"; },
    );

    is(
        $sender->find_session_tty( session_id => 'session-string' ),
        'pts/6',
        'sender also accepts process listings returned as a single string'
    );
}

{
    my @commands;
    my $sender = Even::Codex::Sender->new(
        env => {
            EVEN_CODEX_QUERY_LAUNCHER => '/usr/local/bin/even-codex-query-launcher',
        },
        command_runner => sub {
            my (@command) = @_;
            push @commands, \@command;
            return 1;
        },
        ps_lines_provider => sub {
            return ["107 pts/7 node /opt/codex-cli/bin/codex resume session-launcher\n"];
        },
    );

    my $result = $sender->submit_prompt(
        session_id => 'session-launcher',
        prompt     => 'what is the month of today?',
    );
    ok( $result->{ok}, 'sender reports ok after delegating to the query launcher' );
    is( $result->{launch_mode}, 'resume_xterm', 'sender reports the resume-xterm launch mode' );
    is_deeply(
        \@commands,
        [
            [ '/usr/local/bin/even-codex-query-launcher', 'session-launcher', 'what is the month of today?' ],
        ],
        'sender delegates the prompt to the configured query launcher'
    );
}

{
    my @commands;
    my $sender = Even::Codex::Sender->new(
        env => {
            EVEN_CODEX_QUERY_LAUNCHER => '/usr/local/bin/even-codex-query-launcher',
        },
        command_runner => sub {
            my (@command) = @_;
            push @commands, \@command;
            return 1;
        },
        ps_lines_provider => sub {
            return ["111 pts/1 codex unrelated-session\n"];
        },
    );

    my $result = $sender->submit_prompt(
        session_id => 'session-no-target',
        prompt     => 'launcher without tty target',
    );
    ok( $result->{ok}, 'sender still reports ok when launcher mode cannot resolve a tty target first' );
    is( $result->{tty}, q{}, 'launcher mode leaves tty empty when no interactive target is found' );
    is_deeply(
        \@commands,
        [
            [ '/usr/local/bin/even-codex-query-launcher', 'session-no-target', 'launcher without tty target' ],
        ],
        'launcher mode still executes the configured launcher when tty discovery fails'
    );
}

{
    my @commands;
    my $sender = Even::Codex::Sender->new(
        env => {
            EVEN_CODEX_QUERY_LAUNCHER => q{},
        },
        ps_lines_provider => sub {
            return [
                "112 pts/2 /opt/codex-cli/bin/codex resume empty-launcher\n",
            ];
        },
        tty_writer => sub {
            my ( $tty, $prompt ) = @_;
            push @commands, [ $tty, $prompt ];
            return 1;
        },
    );

    my $result = $sender->submit_prompt(
        session_id => 'empty-launcher',
        prompt     => 'empty launcher falls back',
    );
    ok( $result->{ok}, 'sender falls back to the normal tty flow when the launcher env var is empty' );
    is_deeply(
        \@commands,
        [
            [ 'pts/2', 'empty launcher falls back' ],
        ],
        'empty launcher env does not trigger launcher mode'
    );
}

{
    my @commands;
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub {
            return [
                "106 ? xterm -hold -T Codex session-b -e bash -lc codex resume session-b\n",
                "107 pts/7 node /opt/codex-cli/bin/codex resume session-b\n",
            ];
        },
        command_capture => sub {
            my (@command) = @_;
            is_deeply(
                \@command,
                [ 'xdotool', 'search', '--pid', '106' ],
                'sender looks up the xterm window id by pid'
            );
            return "33030158\n";
        },
        command_runner => sub {
            my (@command) = @_;
            push @commands, \@command;
            return 1;
        },
    );

    my $result = $sender->submit_prompt(
        session_id => 'session-b',
        prompt     => 'what is the year today?',
    );
    ok( $result->{ok}, 'sender reports ok after driving the paired Codex xterm' );
    is( $result->{tty}, 'pts/7', 'sender reports the target tty used for prompt submission' );
    is( $result->{window_id}, '33030158', 'sender reports the target window used for prompt submission' );
    is_deeply(
        \@commands,
        [
            [ 'xdotool', 'windowactivate', '--sync', '33030158' ],
            [ 'xdotool', 'key', '--window', '33030158', 'ctrl+u' ],
            [ 'xdotool', 'type', '--delay', '1', '--window', '33030158', '--', 'what is the year today?' ],
            [ 'xdotool', 'key', '--window', '33030158', 'Return' ],
        ],
        'sender types the exact prompt into the resolved xterm window'
    );
}

{
    my $sender = Even::Codex::Sender->new;
    my @lines = $sender->_ps_lines();
    ok( @lines >= 1, 'sender can inspect the live process table when no test provider is injected' );
}

{
    my @writes;
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub {
            return ["108 pts/7 node /opt/codex-cli/bin/codex resume session-fallback\n"];
        },
        command_capture => sub { return q{}; },
        tty_writer => sub {
            my ( $tty, $prompt ) = @_;
            push @writes, { tty => $tty, prompt => $prompt };
            return 1;
        },
    );

    my $result = $sender->submit_prompt(
        session_id => 'session-fallback',
        prompt     => 'fallback prompt',
    );
    ok( $result->{ok}, 'sender still reports ok when it falls back to direct tty writing' );
    is_deeply(
        \@writes,
        [
            {
                tty    => 'pts/7',
                prompt => 'fallback prompt',
            }
        ],
        'sender falls back to direct tty writing when no xterm window is available'
    );
}

{
    my @writes;
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub {
            return [
                "116 ? xterm -hold -T Codex session-window-miss -e bash -lc codex resume session-window-miss\n",
                "115 pts/8 /opt/codex-cli/bin/codex resume session-window-miss\n",
            ];
        },
        command_capture => sub { return undef; },
        tty_writer => sub {
            my ( $tty, $prompt ) = @_;
            push @writes, { tty => $tty, prompt => $prompt };
            return 1;
        },
    );

    my $result = $sender->submit_prompt(
        session_id => 'session-window-miss',
        prompt     => 'window id missing',
    );
    ok( $result->{ok}, 'sender still succeeds when xterm lookup returns undef' );
    is_deeply(
        \@writes,
        [
            {
                tty    => 'pts/8',
                prompt => 'window id missing',
            }
        ],
        'sender falls back to tty writing when xterm lookup returns undef'
    );
}

{
    my $sender = Even::Codex::Sender->new(
        command_capture => sub { return q{}; },
    );
    ok( !defined $sender->find_xterm_window_id( xterm_pid => '555' ), 'sender returns undef when xdotool search finds no xterm window' );
    ok( !defined $sender->find_xterm_window_id(), 'sender returns undef when no xterm pid is supplied' );
    ok( !defined $sender->find_xterm_window_id( xterm_pid => q{} ), 'sender returns undef when an empty xterm pid is supplied' );
}

{
    my $sender = Even::Codex::Sender->new(
        command_capture => sub { return undef; },
    );
    ok( !defined $sender->find_xterm_window_id( xterm_pid => '556' ), 'sender also returns undef when xdotool search returns undef' );
}

{
    my $sender = Even::Codex::Sender->new(
        command_capture => sub { return "33030158\n\n"; },
    );
    is( $sender->find_xterm_window_id( xterm_pid => '557' ), '33030158', 'sender ignores blank xdotool search rows when selecting the xterm window id' );
}

{
    my $sender = Even::Codex::Sender->new(
        command_capture => sub { return "\n33030158\n"; },
    );
    is( $sender->find_xterm_window_id( xterm_pid => '558' ), '33030158', 'sender ignores leading blank xdotool search rows when selecting the xterm window id' );
}

{
    no warnings 'redefine';
    local *Even::Codex::Sender::find_session_target = sub {
        return { tty => undef };
    };

    my @commands;
    my $sender = Even::Codex::Sender->new(
        command_runner => sub {
            my (@command) = @_;
            push @commands, \@command;
            return 1;
        },
    );

    my $result = $sender->_launch_prompt(
        launcher   => '/tmp/launcher',
        session_id => 'session-direct-launch',
        prompt     => 'launch without tty in target hash',
    );
    ok( $result->{ok}, 'direct launch helper succeeds when the target hash has no tty' );
    is( $result->{tty}, q{}, 'direct launch helper normalizes an undefined tty to the empty string' );
}

{
    no warnings 'redefine';
    local *Even::Codex::Sender::find_session_target = sub {
        return 'not-a-hash';
    };

    my @commands;
    my $sender = Even::Codex::Sender->new(
        command_runner => sub {
            my (@command) = @_;
            push @commands, \@command;
            return 1;
        },
    );

    my $result = $sender->_launch_prompt(
        launcher   => '/tmp/launcher',
        session_id => 'session-nonhash-target',
        prompt     => 'launch with non-hash target',
    );
    ok( $result->{ok}, 'direct launch helper also succeeds when session lookup returns a non-hash value' );
    is( $result->{tty}, q{}, 'direct launch helper ignores non-hash lookup results' );
}

{
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub {
            return [
                "117 pts/9 /opt/codex-cli/bin/codex resume session-defined-first\n",
                "118 ? xterm -hold -T Codex session-defined-first -e bash -lc codex resume session-defined-first\n",
            ];
        },
    );

    is_deeply(
        $sender->find_session_target( session_id => 'session-defined-first' ),
        {
            tty       => 'pts/9',
            xterm_pid => undef,
        },
        'sender keeps the first resolved tty once set and does not re-enter the pid/tty parser branch on later matching rows'
    );
}

{
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub {
            return [
                "pts/6 /opt/codex-cli/bin/codex resume session-short-format\n",
                "pts/5 helper session-short-format unrelated\n",
            ];
        },
    );

    is(
        $sender->find_session_tty( session_id => 'session-short-format' ),
        'pts/6',
        'sender can resolve the tty from the fallback non-pid process-list format'
    );
}

{
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub {
            return [
                "session-empty-tty\n",
                " ? codex session-empty-tty\n",
            ];
        },
    );

    my $ok = eval {
        $sender->find_session_tty( session_id => 'session-empty-tty' );
        1;
    };
    ok( !$ok, 'sender ignores fallback process-list rows with empty or ? tty values' );
    like( $@, qr/Unable to find an interactive Codex tty/, 'sender still reports the missing tty after ignoring empty fallback rows' );
}

{
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub {
            return [
                "? codex session-question-tty\n",
            ];
        },
    );

    my $ok = eval {
        $sender->find_session_tty( session_id => 'session-question-tty' );
        1;
    };
    ok( !$ok, 'sender ignores fallback process-list rows whose tty field is ?' );
    like( $@, qr/Unable to find an interactive Codex tty/, 'sender reports the missing tty after rejecting fallback ? tty rows' );
}

{
    my $tmp_path = '/tmp/even-codex-sender-write.txt';
    unlink $tmp_path if -f $tmp_path;

    my $sender = Even::Codex::Sender->new;
    is( $sender->_write_to_tty( $tmp_path, 'typed through test' ), 1, 'sender can write to an absolute output path in the default writer path' );
    is( $sender->_write_to_tty( 'null', 'discarded through test' ), 1, 'sender can write through the default relative tty path via /dev/null' );

    open my $fh, '<', $tmp_path or die "Unable to open $tmp_path: $!";
    my $content = do { local $/; <$fh> };
    close $fh or die "Unable to close $tmp_path: $!";
    is( $content, "typed through test\n", 'default tty writer writes the prompt and a newline' );
    unlink $tmp_path or die "Unable to remove $tmp_path: $!";

    my $bad_path = eval {
        $sender->_write_to_tty( '/tmp/even-codex-missing/tty', 'fail' );
        1;
    };
    ok( !$bad_path, 'default tty writer reports an error when the target path cannot be opened' );
    like( $@, qr/Unable to write to Codex tty/, 'default tty writer explains the open failure' );
}

{
    local $ENV{DISPLAY};
    my $sender = Even::Codex::Sender->new;

    is( $sender->_run_command( 'perl', '-e', 'exit 0' ), 1, 'default command runner succeeds for a zero-exit command' );
    is( $sender->_capture_command( 'perl', '-e', 'print qq(default-capture\\n)' ), "default-capture\n", 'default command capture returns stdout for a successful command' );
    is( $sender->_capture_command( 'perl', '-e', 'print $ENV{DISPLAY}' ), ':1', 'default command capture falls back to DISPLAY=:1 when no other display is set' );
    is( $sender->_run_command( 'perl', '-e', 'exit($ENV{DISPLAY} eq q(:1) ? 0 : 9)' ), 1, 'default command runner falls back to DISPLAY=:1 when no other display is set' );

    my $run_failure = eval {
        $sender->_run_command( 'perl', '-e', 'exit 3' );
        1;
    };
    ok( !$run_failure, 'default command runner reports a non-zero exit code' );
    like( $@, qr/exit code 3/, 'default command runner includes the non-zero exit code' );

    my $capture_failure = eval {
        $sender->_capture_command( 'perl', '-e', 'print STDERR qq(bad-news); exit 4' );
        1;
    };
    ok( !$capture_failure, 'default command capture reports a non-zero exit code' );
    like( $@, qr/exit code 4: bad-news/, 'default command capture includes stderr on failure' );

    my $spawn_failure = eval {
        $sender->_run_command( '/definitely/missing/even-codex-command' );
        1;
    };
    ok( !$spawn_failure, 'default command runner reports an exec failure for a missing command' );
    like( $@, qr/Command failed/, 'default command runner explains the missing command failure' );
}

{
    local $ENV{DISPLAY} = ':77';
    my $sender = Even::Codex::Sender->new;
    is( $sender->_capture_command( 'perl', '-e', 'print $ENV{DISPLAY}' ), ':77', 'default command capture reuses DISPLAY from the environment when no explicit display is configured' );
    is( $sender->_run_command( 'perl', '-e', 'exit($ENV{DISPLAY} eq q(:77) ? 0 : 9)' ), 1, 'default command runner reuses DISPLAY from the environment when no explicit display is configured' );
}

{
    local $ENV{DISPLAY} = ':55';
    my $sender = Even::Codex::Sender->new(
        display => ':99',
    );
    is( $sender->_capture_command( 'perl', '-e', 'print $ENV{DISPLAY}' ), ':99', 'explicit display override wins over DISPLAY from the environment' );
    is( $sender->_run_command( 'perl', '-e', 'exit($ENV{DISPLAY} eq q(:99) ? 0 : 9)' ), 1, 'default command runner also exports the explicit display override' );
}

{
    my $sender = Even::Codex::Sender->new(
        ps_lines_provider => sub { return ["109 ? xterm -e codex resume missing\n"]; },
    );
    my $ok = eval {
        $sender->find_session_tty( session_id => 'missing' );
        1;
    };
    ok( !$ok, 'sender rejects session submissions when no interactive tty is found' );
    like( $@, qr/Unable to find an interactive Codex tty/, 'sender explains the missing tty case' );
}

{
    my $sender = Even::Codex::Sender->new;

    my $missing_session = eval {
        $sender->submit_prompt( prompt => 'hi' );
        1;
    };
    ok( !$missing_session, 'sender rejects a missing Codex session id' );
    like( $@, qr/Codex session id is required/, 'sender explains the missing Codex session id' );

    my $empty_session = eval {
        $sender->submit_prompt( session_id => q{}, prompt => 'hi' );
        1;
    };
    ok( !$empty_session, 'sender rejects an empty Codex session id' );
    like( $@, qr/Codex session id is required/, 'sender explains the empty Codex session id' );

    my $missing_prompt = eval {
        $sender->submit_prompt( session_id => 'session-c' );
        1;
    };
    ok( !$missing_prompt, 'sender rejects a missing prompt' );
    like( $@, qr/Prompt is required/, 'sender explains the missing prompt' );

    my $empty_prompt = eval {
        $sender->submit_prompt( session_id => 'session-c', prompt => q{} );
        1;
    };
    ok( !$empty_prompt, 'sender rejects an empty prompt' );
    like( $@, qr/Prompt is required/, 'sender explains the empty prompt' );

    my $missing_find_session = eval {
        $sender->find_session_tty();
        1;
    };
    ok( !$missing_find_session, 'sender rejects tty lookup without a session id' );
    like( $@, qr/Codex session id is required/, 'sender tty lookup explains the missing session id' );

    my $empty_find_session = eval {
        $sender->find_session_tty( session_id => q{} );
        1;
    };
    ok( !$empty_find_session, 'sender rejects tty lookup with an empty session id' );
    like( $@, qr/Codex session id is required/, 'sender tty lookup explains the empty session id' );
}

done_testing;
