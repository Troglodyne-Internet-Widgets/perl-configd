package Configd::Language::ossec;

#ABSTRACT: ossec.conf, which is one XML file that every daemon of OSSEC reads, with no directory beside it.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use parent qw{Configd::Language};

=head1 NAME

Configd::Language::ossec - ossec.conf, which is one XML file that every daemon
of OSSEC reads, with no directory beside it.

=head1 SYNOPSIS

    use Configd();

    Configd->adopt('ossec');
    Configd->build('ossec');

A fragment is XML in the form of F<ossec.conf> itself:

    <ossec_config>
      <global>
        <email_notification>no</email_notification>
      </global>
      <localfile/>
      <remote>
        <connection>syslog</connection>
        <port>10514</port>
      </remote>
    </ossec_config>

=head1 DESCRIPTION

Every daemon of OSSEC reads F</var/ossec/etc/ossec.conf>, and nothing else.  Its
one include is for rule files, inside C<< <rules> >>.  So the file becomes
generated, and a fragment is a file of its own.

=head2 How the file is merged

The file is a root element C<< <ossec_config> >> holding sections, and the
sections are of two kinds.

A section that appears once, such as C<< <global> >>, is a set of settings.
Each child element is a directive, keyed by the section and its own name, as
C<global/email_notification>, and the later fragment wins.  Some children are
lists, such as each C<< <include> >> of C<< <rules> >> and each
C<< <white_list> >> of C<< <global> >>: each fragment adds to them, in the
order that they were first seen, so the rule files of the package keep their
order and the includes of a fragment come after them.

A section that can appear many times, such as C<< <localfile> >> or
C<< <remote> >>, is a list of whole blocks, and each fragment adds blocks to it.
So is a section that this language does not know, so that nothing in it is lost.

Two blocks or children that say the same thing are one, so a fragment can repeat
what is already there.  An empty element clears its list, as an empty value
does in every language: an empty C<< <localfile/> >> drops every
C<< <localfile> >> of the fragments before it, and anything after it adds to
nothing.  The package's example configuration is the case: it watches log
files that a distribution does not have, and whitelists addresses of the
network of its author.

Comments are left out of the generated file, as in every language.

=head2 What it reads

Elements, attributes in quotes, text and comments.  It is not a general XML
parser, because configd runs on the core modules of the perl of the guest,
which have none.  F<ossec.conf> uses nothing more, and a fragment that does,
such as one with a CDATA section, dies with the place that it could not read.

=head1 METHODS

=head2 files()

F</var/ossec/etc/ossec.conf>, 0660 root:ossec as the package ships it, if it has
to be created.

=head2 units()

C<ossec.service>.  The package ships an init script, and systemd generates the
unit from it.  A drop-in applies to a generated unit as to any other.

=head2 reloads()

False.  C<ossec-control> has no reload, so a change wants a restart.

=cut

sub files {
    return ( { path => '/var/ossec/etc/ossec.conf', mode => 0o660, owner => 'root:ossec' } );
}

sub units {
    return ('ossec.service');
}

sub reloads {
    return 0;
}

# The sections that appear once, each with the children that are lists.  Every
# other section is a list of blocks.
my %SINGLE = (
    global    => { map { $_ => 1 } qw{white_list email_to} },
    rules     => { map { $_ => 1 } qw{include list decoder} },
    syscheck  => { map { $_ => 1 } qw{directories ignore nodiff registry_ignore windows_registry} },
    rootcheck => { map { $_ => 1 } qw{system_audit windows_audit windows_apps windows_malware} },
    alerts    => {},
    client    => {},
);

# An element, an attribute in quotes, and a tag: what this reads of XML.
my $NAME = qr/[[:alpha:]_][\w.-]*/;
my $ATTR = qr/\s+$NAME\s*=\s*(?:"[^"<]*"|'[^'<]*')/;
my $TAG  = qr{<(/?)($NAME)((?:$ATTR)*)\s*(/?)>};

=head2 accumulates($key)

True for a section that can appear many times, and for a child that is a list,
as L</How the file is merged> says.

=cut

sub accumulates {
    my ( $self, $key ) = @_;

    my ( $section, $child ) = sections($key);
    return $SINGLE{$section}         ? 0 : 1 unless defined $child;
    return $SINGLE{$section}{$child} ? 1 : 0;
}

=head2 separator($key)

A line break, between the elements of a list.

=cut

sub separator {
    return "\n";
}

=head2 @items = $language->items($key, $value)

The elements in C<$value>, each as one line.

=cut

sub items {
    my ( $self, $key, $value ) = @_;
    return () unless defined $value;
    return map { $_->{text} } elements($value);
}

=head2 parse($text)

The directives of a fragment, as L</How the file is merged> says.  Dies on text
that it cannot read, or on a root element other than C<< <ossec_config> >>.

=cut

sub parse {
    my ( $self, $text ) = @_;

    my @directives;
    foreach my $root ( elements($text) ) {
        die "<$root->{name}> is not <ossec_config>, which is the root of ossec.conf.\n" unless $root->{name} eq 'ossec_config';
        foreach my $section ( elements( $root->{inner} ) ) {
            if ( !$SINGLE{ $section->{name} } ) {
                push @directives, { key => $section->{name}, value => $section->{empty} ? q{} : $section->{text} };
                next;
            }
            foreach my $child ( elements( $section->{inner} ) ) {
                push @directives, { key => "$section->{name}/$child->{name}", value => $child->{empty} ? q{} : $child->{text} };
            }
        }
    }
    return \@directives;
}

=head2 emit($directives)

One C<< <ossec_config> >> holding every section, in the order that each was
first seen, with the children of a section that appears once together in it.

=cut

sub emit {
    my ( $self, $directives ) = @_;

    my ( @order, %lines );
    foreach my $directive (@$directives) {
        my ($section) = sections( $directive->{key} );
        push @order, $section unless $lines{$section};
        my @items = $self->accumulates( $directive->{key} ) ? $self->items( $directive->{key}, $directive->{value} ) : grep { length } $directive->{value};
        push @{ $lines{$section} }, @items;
    }

    my $xml = "<ossec_config>\n";
    foreach my $section (@order) {
        my @lines = @{ $lines{$section} };
        next unless @lines;
        if ( !$SINGLE{$section} ) {
            $xml .= join( q{}, map { "  $_\n" } @lines );
            next;
        }
        $xml .= "  <$section>\n" . join( q{}, map { "    $_\n" } @lines ) . "  </$section>\n";
    }
    return $xml . "</ossec_config>\n";
}

=head2 header($file)

The header of every language, as an XML comment.

=cut

sub header {
    my ( $self, $file ) = @_;

    # An XML comment cannot hold two hyphens in a row.
    my $text = $self->SUPER::header($file) =~ s/^#[ ]?//gmr =~ s/-{2,}/-/gr;
    return "<!--\n$text-->\n";
}

=head1 FUNCTIONS

=head2 ($section, $child) = sections($key)

The section of a directive's key, and the child, or undef for a key that names a
whole section.

=cut

sub sections {
    my ($key) = @_;

    my $slash = index( $key, q{/} );
    return ($key) if $slash < 0;
    return ( substr( $key, 0, $slash ), substr( $key, $slash + 1 ) );
}

=head2 @elements = elements($xml)

The elements at the top level of C<$xml>, in order, each a hashref of C<name>,
C<inner>, the text between its tags, C<text>, the whole element on one line
with the space between tags taken out, and C<empty>, true for an element with
no content and no attributes.  Comments and processing instructions are left
out.  Dies on text outside an element, and on a tag that does not close.

=cut

sub elements {
    my ($xml) = @_;

    $xml =~ s/<!--.*?-->//gs;
    $xml =~ s/<\?.*?\?>//gs;

    my ( @elements, @stack );
    my ( $start, $name, $attrs );
    pos($xml) = 0;
    while ( pos($xml) < length $xml ) {
        if ( $xml =~ m/\G([^<]+)/gc ) {
            my $text = $1;
            die "Text outside of an element: '" . substr( $text, 0, 40 ) . "'\n" if !@stack && $text =~ m/\S/;
            next;
        }
        my $at = pos($xml);
        $xml =~ m/\G$TAG/gc or die "Cannot read the XML at '" . substr( $xml, $at, 40 ) . "'\n";
        my ( $close, $tag, $tag_attrs, $self_closing ) = ( $1, $2, $3, $4 );

        if ($close) {
            my $open = pop @stack;
            die "</$tag> closes <" . ( $open // 'nothing' ) . ">\n" unless defined $open && $open eq $tag;
            next if @stack;
            my $inner = substr( $xml, $start->[1], $at - $start->[1] );
            push @elements, element( $name, $attrs, $inner );
            next;
        }

        if ( !@stack ) {
            ( $name, $attrs ) = ( $tag, $tag_attrs );
            $start = [ $at, pos($xml) ];
        }
        if ($self_closing) {
            push @elements, element( $tag, $tag_attrs, q{} ) unless @stack;
            next;
        }
        push @stack, $tag;
    }
    die "<$stack[0]> does not close\n" if @stack;
    return @elements;
}

=head2 $element = element($name, $attrs, $inner)

One element, as C<elements> returns it.

=cut

sub element {
    my ( $name, $attrs, $inner ) = @_;

    $attrs =~ s/\s+/ /g;
    my $content = $inner =~ s/>\s+</></gr =~ s/\A\s+|\s+\z//gr;
    my $text    = length $content ? "<$name$attrs>$content</$name>" : "<$name$attrs/>";
    return { name => $name, inner => $inner, text => $text, empty => !length($content) && !length($attrs) };
}

=head1 SEE ALSO

L<Configd::Language>

=cut

1;
