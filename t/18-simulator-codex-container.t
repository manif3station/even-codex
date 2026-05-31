use strict;
use warnings;

use Test::More;

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Unable to open $path: $!";
    local $/;
    my $text = <$fh>;
    close $fh or die "Unable to close $path: $!";
    return $text;
}

my $dockerfile = slurp('docker/simulator/Dockerfile');
like( $dockerfile, qr/\@openai\/codex\@0\.135\.0/, 'simulator Dockerfile installs the Codex CLI package' );
like( $dockerfile, qr/EVEN_CODEX_REAL_CODEX_BIN=\/opt\/codex-cli\/bin\/codex/, 'simulator Dockerfile publishes a stable real Codex binary path' );
like( $dockerfile, qr/\bxterm\b/, 'simulator Dockerfile installs xterm for the visible Codex TUI window' );
like( $dockerfile, qr/\bscrot\b/, 'simulator Dockerfile installs a desktop screenshot tool for gated visual checks' );
like( $dockerfile, qr/\bxdotool\b/, 'simulator Dockerfile installs xdotool for desktop-driven E2E automation' );
like( $dockerfile, qr/\blibwebkit2gtk-4\.1-0\b/, 'simulator Dockerfile installs the Even simulator WebKit runtime' );

my $compose = slurp('docker-compose.simulator.yml');
like( $compose, qr/\$\{HOME\}\/\.codex:\/root\/\.codex/, 'simulator compose mounts the host Codex config into the container' );
like( $compose, qr/\$\{EVEN_CODEX_WORKSPACE_PATH\}:\$\{EVEN_CODEX_WORKSPACE_PATH\}/, 'simulator compose mounts the active workspace path into the container' );

my $entrypoint = slurp('docker/simulator/entrypoint.sh');
like( $entrypoint, qr/command -v codex/, 'simulator entrypoint verifies the Codex binary is present' );
like( $entrypoint, qr/EVEN_CODEX_REAL_CODEX_BIN/, 'simulator entrypoint carries the stable real Codex binary path through the desktop runtime' );
like( $entrypoint, qr/EVEN_CODEX_REAL_CODEX_BIN.+--version/s, 'simulator entrypoint records the Codex version through the stable real binary path' );
like( $entrypoint, qr/\bxterm\b/, 'simulator entrypoint launches a visible terminal window' );
like( $entrypoint, qr/\-hold\b/, 'simulator entrypoint keeps the Codex terminal visible after seeded smoke sessions complete' );
like( $entrypoint, qr/\$2" resume/, 'simulator entrypoint resumes the paired Codex session through the stable real binary path in the visible terminal' );
like( $entrypoint, qr/\-\-no-alt-screen\b/, 'simulator entrypoint preserves inline Codex output for VNC inspection' );
like( $entrypoint, qr/dangerously-bypass-hook-trust/, 'simulator entrypoint bypasses the workspace trust interstitial for the external Docker sandbox' );

my $simulator_cli = slurp('cli/simulator');
like( $simulator_cli, qr/EVEN_CODEX_WORKSPACE_PATH=/, 'simulator CLI writes the workspace path into the compose env file' );

done_testing;
