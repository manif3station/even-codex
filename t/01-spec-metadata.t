use strict;
use warnings;

use Test::More;

use lib 'lib';
use Even::Codex::Spec;

is(Even::Codex::Spec::skill_name(), 'even-codex', 'skill name matches repo name');
is(Even::Codex::Spec::spec_path(), 'SPEC.md', 'spec path is stable');
is(Even::Codex::Spec::installation_status(), 'lan-bridge-runtime', 'installation status reflects the first runnable bridge release');

my @sections = Even::Codex::Spec::required_sections();
is(scalar @sections, 10, 'required section list is complete');
is($sections[0], 'Purpose', 'first required section is Purpose');
is($sections[-1], 'Delivery Plan', 'last required section is Delivery Plan');

done_testing;
