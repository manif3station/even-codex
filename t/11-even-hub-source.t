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

my $package = slurp('package.json');
like( $package, qr/\@evenrealities\/even_hub_sdk/, 'package.json includes the Even Hub SDK dependency' );
like( $package, qr/\@evenrealities\/evenhub-cli/, 'package.json includes the Even Hub CLI dependency' );
like( $package, qr/"build:hub"/, 'package.json exposes a build script for the Even Hub app' );
like( $package, qr/"pack:hub"/, 'package.json exposes a packaging script for the Even Hub app' );
like( $package, qr/"capture:hub-screens"/, 'package.json exposes a screenshot capture script for the Even Hub app' );

my $source = slurp('even-hub/src/main.ts');
like( $source, qr/waitForEvenAppBridge/, 'Even Hub source waits for the Even app bridge' );
like( $source, qr/createStartUpPageContainer/, 'Even Hub source creates a startup page container' );
like( $source, qr/shutDownPageContainer\(1\)/, 'Even Hub source uses the documented root exit confirmation flow' );
like( $source, qr/OsEventTypeList\.DOUBLE_CLICK_EVENT/, 'Even Hub source handles root double-click exit' );
like( $source, qr/OsEventTypeList\.FOREGROUND_ENTER_EVENT/, 'Even Hub source handles foreground enter' );
like( $source, qr/OsEventTypeList\.FOREGROUND_EXIT_EVENT/, 'Even Hub source handles foreground exit' );
like( $source, qr/OsEventTypeList\.ABNORMAL_EXIT_EVENT/, 'Even Hub source handles abnormal exit' );
like( $source, qr/OsEventTypeList\.SYSTEM_EXIT_EVENT/, 'Even Hub source handles system exit' );
like( $source, qr/getLocalStorage/, 'Even Hub source remembers setup through SDK local storage' );
like( $source, qr/setLocalStorage/, 'Even Hub source persists setup through SDK local storage' );

my $style = slurp('even-hub/src/style.css');
unlike( $style, qr/background(?:-color)?\s*:/i, 'Even Hub source styles avoid background fill declarations' );
like( $style, qr/border:/i, 'Even Hub source styles use borders for structure' );

done_testing;
