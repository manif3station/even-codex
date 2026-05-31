package Even::Codex::Spec;

use strict;
use warnings;

our $VERSION = '0.24';

sub skill_name {
    return 'even-codex';
}

sub spec_path {
    return 'SPEC.md';
}

sub installation_status {
    return 'lan-bridge-runtime';
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
        'Local-Network Deployment Mode',
        'Testing Strategy',
        'Delivery Plan',
    );
}

1;
