package Configd::Language::opendmarc;

#ABSTRACT: opendmarc.conf, which has never had a conf.d.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use parent qw{Configd::Language};

use Configd::Syntax::Spaced();

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

=head2 units()

=head2 parse($text)

=head2 emit($directives)

=cut

sub files {
    return ( { path => '/etc/opendmarc.conf', mode => 0o600, owner => 'opendmarc:opendmarc' } );
}

sub units {
    return ('opendmarc.service');
}

sub parse {
    my ( $self, $text ) = @_;
    return Configd::Syntax::Spaced::parse($text);
}

sub emit {
    my ( $self, $directives ) = @_;
    return Configd::Syntax::Spaced::emit($directives);
}

1;
