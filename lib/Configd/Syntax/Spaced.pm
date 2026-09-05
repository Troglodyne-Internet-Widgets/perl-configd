package Configd::Syntax::Spaced;

#ABSTRACT: Config files that are a directive, some whitespace and a value.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

=head1 NAME

Configd::Syntax::Spaced - config files that are a directive, some whitespace and
a value.

=head1 SYNOPSIS

    package Configd::Language::example;

    use parent qw{Configd::Language};
    use Configd::Syntax::Spaced();

    sub parse { my ( $self, $text ) = @_; return Configd::Syntax::Spaced::parse($text) }
    sub emit  { my ( $self, $d )    = @_; return Configd::Syntax::Spaced::emit($d) }

=head1 DESCRIPTION

Four of the files here are the same shape:

    Syslog                  yes
    Canonicalization        relaxed/simple

opendkim, opendmarc, redis and chrony all write configuration this way -- a
directive, whitespace, and the rest of the line -- and differ only in which
directives may be said twice.  One reader and one writer between them, rather
than four that drift apart.

Not a base class, because L<Configd> finds languages by looking for modules
under C<Configd::Language::>, and anything put there to be inherited from would
be offered as a language somebody could adopt.

=head1 FUNCTIONS

=head2 parse($text)

The directives in a fragment.  Comments and blank lines come back as text with
no key, so they keep their place in a file that is not merged.

=cut

sub parse {
    my ($text) = @_;

    my @directives;
    foreach my $line ( split( qq{\n}, $text ) ) {
        if ( $line =~ m/\A\s*(?:#.*)?\z/ ) {
            push @directives, { text => $line };
            next;
        }

        # Tabs as often as spaces in these files, and a value that runs to the
        # end of the line: opendkim's Canonicalization is one word, its
        # InternalHosts is a list, and neither is quoted.
        my ( $key, $value ) = $line =~ m/\A\s*(\S+)\s+(.*?)\s*\z/;

        # A directive on its own is legal in some of these -- redis has bare
        # flags -- and means itself.
        ( $key, $value ) = ( $line =~ s/\A\s+|\s+\z//gr, q{} ) if !defined $key;

        push @directives, { key => $key, value => $value };
    }

    return \@directives;
}

=head2 emit($directives)

The file those directives make.

Written as C<directive value>, one space, rather than reproducing whatever
column alignment the original had.  Alignment is a property of a file somebody
maintained by hand, and this file is generated from several of them.

=cut

sub emit {
    my ($directives) = @_;

    my $out = q{};
    foreach my $directive (@$directives) {
        if ( !defined $directive->{key} ) {
            $out .= ( $directive->{text} // q{} ) . "\n";
            next;
        }

        $out .= length $directive->{value}
          ? "$directive->{key} $directive->{value}\n"
          : "$directive->{key}\n";
    }

    return $out;
}

=head1 SEE ALSO

L<Configd::Language>

=cut

1;
