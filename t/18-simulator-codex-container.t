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
like( $dockerfile, qr/EVEN_CODEX_REAL_CODEX_BIN=\/opt\/codex-cli\/lib\/node_modules\/\@openai\/codex\/node_modules\/\@openai\/codex-linux-x64\/vendor\/x86_64-unknown-linux-musl\/bin\/codex/, 'simulator Dockerfile publishes the packaged native Codex binary path' );
unlike( $dockerfile, qr/EVEN_CODEX_REAL_CODEX_BIN=\/opt\/codex-cli\/bin\/codex/, 'simulator Dockerfile no longer points the real Codex binary path at the Node launcher wrapper' );
like( $dockerfile, qr/\buseradd\b/, 'simulator Dockerfile creates a dedicated desktop runtime user' );
like( $dockerfile, qr/if ! getent passwd "\$\{EVEN_CODEX_HOST_UID\}" >/ , 'simulator Dockerfile only creates a user when the host uid does not already exist' );
like( $dockerfile, qr/^USER \$\{EVEN_CODEX_HOST_UID\}:\$\{EVEN_CODEX_HOST_GID\}$/m, 'simulator Dockerfile runs the container as the host uid and gid by default' );
like( $dockerfile, qr/\bxterm\b/, 'simulator Dockerfile installs xterm for the visible Codex TUI window' );
like( $dockerfile, qr/\bscrot\b/, 'simulator Dockerfile installs a desktop screenshot tool for gated visual checks' );
like( $dockerfile, qr/\bxdotool\b/, 'simulator Dockerfile installs xdotool for desktop-driven E2E automation' );
like( $dockerfile, qr/\blibwebkit2gtk-4\.1-0\b/, 'simulator Dockerfile installs the Even simulator WebKit runtime' );
like( $dockerfile, qr/mkdir -p \/tmp\/\.X11-unix; \\/, 'simulator Dockerfile precreates the X11 socket directory before dropping privileges' );
like( $dockerfile, qr/chmod 1777 \/tmp\/\.X11-unix; \\/, 'simulator Dockerfile makes the X11 socket directory world-writable with the sticky bit for non-root Xvfb' );

my $compose = slurp('docker-compose.simulator.yml');
like( $compose, qr/args:\s+.*EVEN_CODEX_RUNTIME_USER.*EVEN_CODEX_HOST_UID.*EVEN_CODEX_HOST_GID/s, 'simulator compose passes runtime user and host ids into the image build' );
like( $compose, qr/EVEN_CODEX_CONNECTOR_MODE:\s+\$\{EVEN_CODEX_CONNECTOR_MODE\}/, 'simulator compose passes the connector mode into the runtime container' );
like( $compose, qr/EVEN_CODEX_CONNECTOR_API_KEY:\s+\$\{EVEN_CODEX_CONNECTOR_API_KEY\}/, 'simulator compose passes the fixed DD API key into the runtime container when API mode is selected' );
like( $compose, qr/EVEN_CODEX_CONNECTOR_API_SECRET:\s+\$\{EVEN_CODEX_CONNECTOR_API_SECRET\}/, 'simulator compose passes the DD API secret into the runtime container when API mode is selected' );
like( $compose, qr/\$\{HOME\}\/\.codex:\/home\/\$\{EVEN_CODEX_RUNTIME_USER\}\/\.codex/, 'simulator compose mounts the host Codex config into the non-root runtime home' );
like( $compose, qr/\$\{EVEN_CODEX_WORKSPACE_PATH\}:\$\{EVEN_CODEX_WORKSPACE_PATH\}/, 'simulator compose mounts the active workspace path into the container' );

my $entrypoint = slurp('docker/simulator/entrypoint.sh');
unlike( $entrypoint, qr/\b(usermod|groupmod)\b/, 'simulator entrypoint does not mutate ids at runtime' );
unlike( $entrypoint, qr/\bsu\b/, 'simulator entrypoint does not need a runtime su hop' );
like( $entrypoint, qr/HOME="\$\{EVEN_CODEX_RUNTIME_HOME\}"/, 'simulator entrypoint exports a stable runtime home for the mounted Codex config' );
like( $entrypoint, qr/EVEN_CODEX_REAL_CODEX_BIN="\$\{EVEN_CODEX_REAL_CODEX_BIN:-\/opt\/codex-cli\/lib\/node_modules\/\@openai\/codex\/node_modules\/\@openai\/codex-linux-x64\/vendor\/x86_64-unknown-linux-musl\/bin\/codex\}"/, 'simulator entrypoint defaults the real Codex path to the packaged native binary' );

my $runtime = slurp('docker/simulator/runtime.sh');
like( $runtime, qr/command -v codex/, 'simulator runtime verifies the Codex binary is present' );
like( $runtime, qr/EVEN_CODEX_REAL_CODEX_BIN/, 'simulator runtime carries the stable real Codex binary path through the desktop runtime' );
like( $runtime, qr/EVEN_CODEX_REAL_CODEX_BIN.+--version/s, 'simulator runtime records the Codex version through the stable real binary path' );
like( $runtime, qr/EVEN_CODEX_QUERY_LAUNCHER/, 'simulator runtime exports the dedicated query launcher path' );
like( $runtime, qr/even-codex-query-launcher/, 'simulator runtime seeds the visible Codex window through the dedicated launcher' );
my $launcher = slurp('docker/simulator/query-launcher.sh');
like( $launcher, qr/\bxterm\b/, 'query launcher opens a visible xterm window for the paired Codex session' );
like( $launcher, qr/\bresume\b/, 'query launcher resumes the paired Codex session' );
like( $launcher, qr/codex-xterm\.pid/, 'query launcher records the active xterm pid for later replacement and cleanup' );
like( $launcher, qr/\-\-no-alt-screen\b/, 'query launcher preserves inline Codex output for VNC inspection' );
like( $launcher, qr/dangerously-bypass-hook-trust/, 'query launcher bypasses the workspace trust interstitial for the external Docker sandbox' );
like( $launcher, qr/codex_bin="\$\{EVEN_CODEX_REAL_CODEX_BIN:-\/opt\/codex-cli\/lib\/node_modules\/\@openai\/codex\/node_modules\/\@openai\/codex-linux-x64\/vendor\/x86_64-unknown-linux-musl\/bin\/codex\}"/, 'query launcher defaults the real Codex path to the packaged native binary' );
unlike( $launcher, qr/codex_bin="\$\{EVEN_CODEX_REAL_CODEX_BIN:-\/opt\/codex-cli\/bin\/codex\}"/, 'query launcher no longer defaults to the Node launcher wrapper path' );

my $simulator_cli = slurp('cli/simulator');
like( $simulator_cli, qr/EVEN_CODEX_WORKSPACE_PATH=/, 'simulator CLI writes the workspace path into the compose env file' );
like( $simulator_cli, qr/EVEN_CODEX_HOST_UID=/, 'simulator CLI writes the caller uid into the compose env file' );
like( $simulator_cli, qr/EVEN_CODEX_HOST_GID=/, 'simulator CLI writes the caller gid into the compose env file' );

done_testing;
