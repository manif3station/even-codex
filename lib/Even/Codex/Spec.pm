package Even::Codex::Spec;

use strict;
use warnings;

our $VERSION = '0.01';

sub skill_name {
    return 'even-codex';
}

sub spec_path {
    return 'SPEC.md';
}

sub installation_status {
    return 'spec-only';
}

sub required_sections {
    return (
        'Purpose',
        'Scope',
        'Production Architecture',
        'Functional Requirements',
        'Interface Contract',
        'Security Requirements',
        'Reliability Requirements',
        'Testing Strategy',
        'Delivery Plan',
    );
}

1;
