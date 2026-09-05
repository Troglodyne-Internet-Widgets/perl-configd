package Configd::Language::opendkim;

#ABSTRACT: opendkim.conf, which has never had a conf.d.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use parent qw{Configd::Syntax::Spaced};

=head1 NAME

Configd::Language::opendkim - opendkim.conf, which has never had a conf.d.

=head1 SYNOPSIS

    use Configd();

    Configd->adopt('opendkim');
    Configd->build('opendkim');

=head1 DESCRIPTION

opendkim reads one file and offers nothing to add to it. Signing for a second
domain on a host that already signs for one means editing that file, and two
things editing it cannot both win.

The file is 0600 and stays that way: it names the key table and the signing
key, and configd keeps whatever mode it found.

=head1 METHODS

=head2 files()

F</etc/opendkim.conf>, 0600 opendkim:opendkim if it has to be created.

=head2 units()

C<opendkim.service>.

=cut

sub files {
    return ( { path => '/etc/opendkim.conf', mode => 0o600, owner => 'opendkim:opendkim' } );
}

sub units {
    return ('opendkim.service');
}

=head1 SEE ALSO

L<Configd::Language>, L<Configd::Syntax::Spaced>

=cut

1;
