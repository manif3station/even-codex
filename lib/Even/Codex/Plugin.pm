package Even::Codex::Plugin;

use strict;
use warnings;
use autodie qw(open close);

use File::Basename qw(dirname);
use File::Spec;
use JSON::PP qw(decode_json);

our $VERSION = '0.12';

sub plugin_root {
    return File::Spec->rel2abs(
        File::Spec->catdir( dirname(__FILE__), File::Spec->updir(), File::Spec->updir(), File::Spec->updir(), 'plugin' )
    );
}

sub asset_path {
    my ($name) = @_;
    die "Plugin asset name is required\n" if !defined $name || $name eq q{};
    return File::Spec->catfile( plugin_root(), $name );
}

sub asset_text {
    my ($name) = @_;
    my $path = asset_path($name);
    open my $fh, '<', $path;
    local $/;
    my $text = <$fh>;
    close $fh;
    return $text;
}

sub manifest_hash {
    return decode_json( asset_text('manifest.json') );
}

sub index_html     { return asset_text('index.html') }
sub app_js         { return asset_text('app.js') }
sub styles_css     { return asset_text('styles.css') }

1;
