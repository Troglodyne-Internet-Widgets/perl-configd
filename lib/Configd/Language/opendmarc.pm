package Configd::Language::opendmarc;

#ABSTRACT: opendmarc.conf, which has never had a conf.d.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use parent qw{Configd::Syntax::Spaced};

=head1 NAME

Configd::Language::opendmarc - opendmarc.conf, which has never had a conf.d.

=head1 SYNOPSIS

    use Configd();

    Configd->adopt('opendmarc');
    Configd->build('opendmarc');

=head1 DESCRIPTION

The same file, the same problem, and the same shape as opendkim's: a
directive, some whitespace, and the rest of the line.

=head1 METHODS

=head2 files()

F</etc/opendmarc.conf>, 0600 opendmarc:opendmarc if it has to be created.

=head2 units()

C<opendmarc.service>.

=cut

sub files {
    return ( { path => '/etc/opendmarc.conf', mode => 0o600, owner => 'opendmarc:opendmarc' } );
}

sub units {
    return ('opendmarc.service');
}

=head2 accumulates($key)

True for C<TrustedAuthservIDs>, a comma-separated list.  One opendmarc
serves every domain on the host, and each domain can name the ids that it
trusts, so a later fragment adds to the list.  C<AuthservID> is one name, the
one that opendmarc writes its own verdicts under, so the later fragment wins.
The comma of the base class is the separator.

=cut

sub accumulates {
    my ( $self, $key ) = @_;
    return $key eq 'TrustedAuthservIDs';
}

=head1 SEE ALSO

L<Configd::Language>, L<Configd::Syntax::Spaced>

=cut

1;
