use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json);
use Test::More;

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return $text;
}

sub run_cli {
    my ( $root, $env, @argv ) = @_;
    my @pairs = map { $_ . '=' . _shell_quote( $env->{$_} ) } sort keys %{$env};
    my $command = join q{ }, @pairs, _shell_quote('./cli/compile'), map { _shell_quote($_) } @argv;
    my $output = qx{cd . && env -i PATH="$ENV{PATH}" HOME="$ENV{HOME}" sh -lc 'cd "$root" && $command' 2>&1};
    my $rc = $? >> 8;
    return ( $rc, $output );
}

sub _shell_quote {
    my ($value) = @_;
    $value = q{} if !defined $value;
    $value =~ s/'/'"'"'/g;
    return "'$value'";
}

sub write_stub_npm {
    my ($path) = @_;
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} <<'PL';
#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);

my $capture = $ENV{EVEN_CODEX_COMPILE_CAPTURE_FILE} or die "capture file missing\n";
open my $log, '>>', $capture or die "Unable to open $capture: $!";
print {$log} join( q{ }, @ARGV ), "\n";
close $log or die "Unable to close $capture: $!";

if (@ARGV && $ARGV[0] eq 'ci') {
    make_path(
        'node_modules/vite/bin',
        'node_modules/@evenrealities/evenhub-cli',
    );
    open my $vite, '>', 'node_modules/vite/bin/vite.js' or die $!;
    print {$vite} "// vite stub\n";
    close $vite or die $!;
    open my $evenhub, '>', 'node_modules/@evenrealities/evenhub-cli/main.js' or die $!;
    print {$evenhub} "// evenhub stub\n";
    close $evenhub or die $!;
    exit 0;
}

die "Unexpected npm args: @ARGV\n";
PL
    close $fh or die "Unable to close $path: $!";
    chmod 0755, $path or die "Unable to chmod $path: $!";
}

sub write_stub_node {
    my ($path) = @_;
    open my $fh, '>', $path or die "Unable to write $path: $!";
    print {$fh} <<'PL';
#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);

my $capture = $ENV{EVEN_CODEX_COMPILE_CAPTURE_FILE} or die "capture file missing\n";
open my $log, '>>', $capture or die "Unable to open $capture: $!";
print {$log} 'NODE ' . join( q{ }, @ARGV ) . "\n";
close $log or die "Unable to close $capture: $!";

if ( @ARGV >= 1 && $ARGV[0] =~ m{/scripts/build-even-hub\.mjs\z} ) {
    make_path('.even-hub-build');
    open my $manifest, '>', '.even-hub-build/app.json' or die $!;
    print {$manifest} "{}\n";
    close $manifest or die $!;
    exit 0;
}

if ( @ARGV >= 2 && $ARGV[0] =~ m{/vite/bin/vite\.js\z} && $ARGV[1] eq 'build' ) {
    make_path('dist');
    open my $html, '>', 'dist/index.html' or die $!;
    print {$html} "<!doctype html>\n";
    close $html or die $!;
    exit 0;
}

if ( @ARGV >= 5 && $ARGV[0] =~ m{/\@evenrealities/evenhub-cli/main\.js\z} && $ARGV[1] eq 'pack' ) {
    make_path('dist');
    open my $artifact, '>', 'dist/d2-codex.ehpk' or die $!;
    print {$artifact} $ENV{EVEN_CODEX_HUB_ORIGIN} // q{};
    close $artifact or die $!;
    exit 0;
}

die "Unexpected node args: @ARGV\n";
PL
    close $fh or die "Unable to close $path: $!";
    chmod 0755, $path or die "Unable to chmod $path: $!";
}

sub write_toolchain {
    my ($root) = @_;
    make_path(
        File::Spec->catdir( $root, 'vite', 'bin' ),
        File::Spec->catdir( $root, '@evenrealities', 'evenhub-cli' ),
    );
    open my $vite, '>', File::Spec->catfile( $root, 'vite', 'bin', 'vite.js' ) or die $!;
    print {$vite} "// vite stub\n";
    close $vite or die $!;
    open my $evenhub, '>', File::Spec->catfile( $root, '@evenrealities', 'evenhub-cli', 'main.js' ) or die $!;
    print {$evenhub} "// evenhub stub\n";
    close $evenhub or die $!;
}

sub setup_repo {
    my ($tmp) = @_;
    my $root = File::Spec->catdir( $tmp, 'repo' );
    my $cli_dir = File::Spec->catdir( $root, 'cli' );
    my $scripts_dir = File::Spec->catdir( $root, 'scripts' );
    my $bin_dir = File::Spec->catdir( $tmp, 'bin' );
    make_path( $cli_dir, $scripts_dir, $bin_dir );

    copy( 'cli/compile', File::Spec->catfile( $cli_dir, 'compile' ) )
      or die "Unable to copy compile CLI: $!";
    chmod 0755, File::Spec->catfile( $cli_dir, 'compile' )
      or die "Unable to chmod compile CLI: $!";

    open my $build_fh, '>', File::Spec->catfile( $scripts_dir, 'build-even-hub.mjs' ) or die $!;
    print {$build_fh} "// build stub\n";
    close $build_fh or die $!;

    my $capture_file = File::Spec->catfile( $tmp, 'npm.log' );
    write_stub_npm( File::Spec->catfile( $bin_dir, 'npm' ) );
    write_stub_node( File::Spec->catfile( $bin_dir, 'node' ) );

    return ( $root, $bin_dir, $capture_file );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my ( $root, $bin_dir, $capture_file ) = setup_repo($tmp);

    my %env = (
        HOME                            => $tmp,
        PATH                            => "${bin_dir}:$ENV{PATH}",
        EVEN_CODEX_COMPILE_CAPTURE_FILE => $capture_file,
    );

    my ( $rc, $output ) = run_cli( $root, \%env );
    is( $rc, 0, 'compile exits cleanly when neither repo-local nor shared node toolchains exist' );

    my $payload = decode_json($output);
    is( $payload->{action}, 'compile', 'compile reports the action' );
    is( $payload->{status}, 'compiled', 'compile reports compiled status' );
    is(
        $payload->{origin},
        'https://192.168.1.20:7890/ajax/even-codex',
        'compile uses the default DD HTTPS connector origin',
    );
    is( $payload->{install_status}, 'installed', 'compile reports it installed dependencies' );
    ok( -f $payload->{artifact_path}, 'compile writes the packaged artifact path' );
    ok( -f $payload->{generated_manifest}, 'compile writes the generated manifest path' );

    my $log = slurp($capture_file);
    like( $log, qr/^ci$/m, 'compile runs npm ci when no reusable toolchain exists' );
    like( $log, qr{^NODE .*/scripts/build-even-hub\.mjs$}m, 'compile runs the governed build script through node' );
    like( $log, qr{^NODE .*/node_modules/vite/bin/vite\.js build$}m, 'compile runs Vite through the resolved package entrypoint' );
    like( $log, qr{^NODE .*/\@evenrealities/evenhub-cli/main\.js pack \.even-hub-build/app\.json dist -o dist/d2-codex\.ehpk$}m, 'compile runs the Even Hub packer through the resolved package entrypoint' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my ( $root, $bin_dir, $capture_file ) = setup_repo($tmp);
    write_toolchain( File::Spec->catdir( $root, 'node_modules' ) );

    my %env = (
        PATH                            => "${bin_dir}:$ENV{PATH}",
        EVEN_CODEX_COMPILE_CAPTURE_FILE => $capture_file,
        EVEN_CODEX_HUB_ORIGIN           => 'https://192.168.1.44:7890/ajax/even-codex',
    );

    my ( $rc, $output ) = run_cli( $root, \%env, 'https://10.0.0.55:7890/ajax/even-codex' );
    is( $rc, 0, 'compile exits cleanly when repo-local node_modules already exists' );

    my $payload = decode_json($output);
    is(
        $payload->{origin},
        'https://10.0.0.55:7890/ajax/even-codex',
        'compile prefers the explicit CLI DD HTTPS origin',
    );
    is( $payload->{install_status}, 'reused', 'compile reports reused repo-local dependencies' );

    my $log = slurp($capture_file);
    unlike( $log, qr/^ci$/m, 'compile skips npm ci when repo-local node_modules already exists' );
    like( $log, qr{^NODE .*/repo/node_modules/vite/bin/vite\.js build$}m, 'compile uses the repo-local Vite package entrypoint' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my ( $root, $bin_dir, $capture_file ) = setup_repo($tmp);
    my $home = File::Spec->catdir( $tmp, 'home' );
    write_toolchain( File::Spec->catdir( $home, 'node_modules' ) );

    my %env = (
        HOME                            => $home,
        PATH                            => "${bin_dir}:$ENV{PATH}",
        EVEN_CODEX_COMPILE_CAPTURE_FILE => $capture_file,
    );

    my ( $rc, $output ) = run_cli( $root, \%env );
    is( $rc, 0, 'compile exits cleanly when the dashboard HOME node toolchain already exists' );

    my $payload = decode_json($output);
    is( $payload->{install_status}, 'dashboard-home', 'compile reports shared dashboard HOME node tools were reused' );

    my $log = slurp($capture_file);
    unlike( $log, qr/^ci$/m, 'compile skips npm ci when dashboard HOME node tools already satisfy the wrapper' );
    like( $log, qr{^NODE .*/home/node_modules/vite/bin/vite\.js build$}m, 'compile uses the dashboard HOME Vite package entrypoint' );
}

{
    my $tmp = tempdir( CLEANUP => 1 );
    my ( $root, $bin_dir, $capture_file ) = setup_repo($tmp);

    my %env = (
        PATH                            => "${bin_dir}:$ENV{PATH}",
        EVEN_CODEX_COMPILE_CAPTURE_FILE => $capture_file,
    );

    my ( $rc, $output ) = run_cli( $root, \%env, 'http://one', 'http://two' );
    is( $rc, 2, 'compile rejects too many positional arguments' );
    like( $output, qr/^Usage: dashboard even-codex\.compile \[bridge-origin\]$/m, 'compile reports the CLI usage text' );
}

done_testing;
