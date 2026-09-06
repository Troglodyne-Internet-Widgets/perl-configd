package Configd::Language::postfix;

#ABSTRACT: main.cf and master.cf, which postfix has never had a conf.d for.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use parent qw{Configd::Language};

=head1 NAME

Configd::Language::postfix - main.cf and master.cf, which postfix has never had
a conf.d for.

=head1 SYNOPSIS

    use Configd();

    Configd->adopt('postfix');    # main.cf and master.cf become generated
    Configd->build('postfix');    # which is what the systemd drop-in then runs

From a shell, which is how it is actually used:

=over 4

=item C<configd adopt postfix>

=item C<< printf 'mydestination = example.com\n' > /etc/postfix/main.cf.d/50-example.cf >>

=item C<systemctl restart postfix>

=back

=head1 DESCRIPTION

Postfix has C<postconf -e> and nothing else.  It sets a parameter by rewriting
C<main.cf>, which is fine for a person at a terminal and wrong for anything
automated: two things configuring the same server cannot both set
C<mydestination>, because the second one to run replaces what the first wrote
rather than adding to it.  Hosting two domains on one mail server is enough to
hit it, and the failure is quiet -- mail for the first domain simply stops being
local.

So C<main.cf> and C<master.cf> become generated files with C<main.cf.d> and
C<master.cf.d> beside them, and each domain drops in a fragment naming itself.
The parameters that are lists are merged as lists; see L</ACCUMULATING PARAMETERS>.

=head2 What the fragments look like

Exactly like the file they add to, because that is the point -- anything you
would have written in C<main.cf> is a fragment:

    # /etc/postfix/main.cf.d/50-example.com.cf
    mydestination = example.com
    virtual_mailbox_domains = example.com
    virtual_mailbox_maps = hash:/etc/postfix/virtual/maps

=head1 ACCUMULATING PARAMETERS

=cut

# The parameters where two fragments each naming something both meant it.  This
# is the list postfix's own documentation describes as taking "a comma and/or
# space separated list of domain names" and friends -- setting one of these from
# two places is the case this whole distribution exists for.
#
# Deliberately not here: the *_restrictions parameters.  They are lists too, but
# ordered ones where the meaning depends on which check comes first and a
# permit_ in the wrong place opens a relay.  Joining two of them end to end
# produces something that parses and is not what either fragment meant, so they
# stay a value a later fragment replaces, and disagreeing about one is something
# somebody should have to notice.
my %ACCUMULATES = map { $_ => 1 } qw{
  mydestination
  myhostname_aliases
  masquerade_domains
  mynetworks
  relay_domains
  virtual_alias_domains
  virtual_mailbox_domains
  local_recipient_maps
  virtual_alias_maps
  virtual_mailbox_maps
  transport_maps
  sender_bcc_maps
  recipient_bcc_maps
  header_checks
  body_checks
  mime_header_checks
  nested_header_checks
  alias_maps
  alias_database
  smtpd_milters
  non_smtpd_milters
  inet_interfaces
  proxy_read_maps
};

=pod

The parameters postfix documents as comma-or-space separated lists, where two
fragments each naming a domain, a map or a milter both meant it:
C<mydestination>, C<mynetworks>, C<relay_domains>, the C<virtual_*> family, the
C<*_maps> and C<*_checks> families, C<smtpd_milters> and C<inet_interfaces>
among them.  Anything else is a value, and a later fragment replaces it.

The C<*_restrictions> parameters are deliberately B<not> accumulated even though
they are lists.  They are ordered, the order is what they mean, and joining two
of them end to end gives something that parses and that neither fragment asked
for -- a C<permit_> landing ahead of a check that was supposed to run first is
an open relay.  Two fragments disagreeing about a restriction list is something
a person should look at.

=head1 METHODS

=head2 files()

C<main.cf> and C<master.cf>.

=head2 units()

C<postfix@.service>, the templated unit.

=head2 services()

C<postfix.service>, which is what can actually be restarted.

=cut

sub files {
    return (
        { path => '/etc/postfix/main.cf',   owner => 'root:root', mode => 0o644 },
        { path => '/etc/postfix/master.cf', owner => 'root:root', mode => 0o644 },
    );
}

sub units {

    # The templated unit rather than postfix.service: on Debian and Ubuntu
    # postfix.service is a oneshot whose ExecStart is /bin/true, and the daemon
    # that actually reads these files is an instance of postfix@.service --
    # postfix@-.service being the default one.  Naming the template covers every
    # instance, including ones somebody adds later.
    return ('postfix@.service');
}

sub services {

    # Not the template: systemctl refuses to restart one, because a template is
    # not a thing that runs.  postfix.service is the wrapper the package enables
    # and every instance is PartOf it, so restarting it takes the instances with
    # it -- which is what the packaging intends you to do.
    return ('postfix.service');
}

=head2 accumulates($key)

True for the list parameters above.  Never true of a master.cf entry, which is a
row rather than a list: two fragments configuring one service disagree about it,
and the later one wins.  The base class's comma is therefore the only separator
this language ever needs.

=cut

sub accumulates {
    my ( $self, $key ) = @_;
    return $ACCUMULATES{$key} // 0;
}

=head2 parse($text)

Read a fragment of either file.

Which one is worked out from the text rather than from a filename, because a
C<main.cf> line and a C<master.cf> line cannot be mistaken for each other: the
first has an C<=> and the second is a row of columns.

=cut

sub parse {
    my ( $self, $text ) = @_;
    return $self->_is_master($text) ? $self->_parse_master($text) : $self->_parse_main($text);
}

# A master.cf row is a service name followed by its type, and nothing in main.cf
# looks like that -- every setting there is `name = value`.
sub _is_master {
    my ( $self, $text ) = @_;

    foreach my $line ( split( qq{\n}, $text ) ) {
        next     if $line =~ m/\A\s*(?:#|\z)/;
        return 0 if $line =~ m/\A\S+\s*=/;
        return 1 if $line =~ m/\A\S+\s+(?:inet|unix|unix-dgram|fifo|pass)\s/;
    }

    return 0;
}

sub _parse_main {
    my ( $self, $text ) = @_;

    my @directives;
    foreach my $line ( split( qq{\n}, $text ) ) {

        # Postfix continues a value onto any following line that begins with
        # whitespace.  It belongs to the parameter above it, so it cannot be
        # merged on its own and has to travel with it.
        if ( $line =~ m/\A\s+\S/ && @directives && defined $directives[-1]{key} ) {
            my $continued = $line =~ s/\A\s+|\s+\z//gr;

            # `param =` with the value on the lines below it is how postfix's
            # own main.cf writes the long ones, so the first continuation of an
            # empty value must not arrive with a space in front of it.
            $directives[-1]{value} =
              length $directives[-1]{value}
              ? "$directives[-1]{value} $continued"
              : $continued;
            next;
        }

        if ( $line =~ m/\A\s*(?:#.*)?\z/ ) {
            push @directives, { text => $line };
            next;
        }

        if ( $line =~ m/\A(\S+?)\s*=\s*(.*?)\s*\z/ ) {
            push @directives, { key => $1, value => $2 };
            next;
        }

        # Not a comment, not a setting, and postfix would refuse to start on it.
        die "Cannot parse postfix main.cf line: $line\n";
    }

    return \@directives;
}

sub _parse_master {
    my ( $self, $text ) = @_;

    my @directives;
    foreach my $line ( split( qq{\n}, $text ) ) {

        # Same continuation rule, and here it is how a service's command line
        # gets its -o overrides, one per line.
        if ( $line =~ m/\A\s+\S/ && @directives && defined $directives[-1]{key} ) {
            push @{ $directives[-1]{continuation} }, ( $line =~ s/\s+\z//r );
            next;
        }

        if ( $line =~ m/\A\s*(?:#.*)?\z/ ) {
            push @directives, { text => $line };
            next;
        }

        my @columns = split( /\s+/, $line );
        die "Cannot parse postfix master.cf line (wanted 8 columns, got " . scalar(@columns) . "): $line\n"
          if @columns < 8;

        # A service is identified by its name and its type together: smtp has
        # both an inet entry and a unix one, and they are different services.
        my ( $service, $type ) = @columns[ 0, 1 ];
        push @directives, {
            key          => "$service/$type",
            columns      => [ @columns[ 0 .. 6 ] ],
            value        => join( q{ }, @columns[ 7 .. $#columns ] ),
            continuation => [],
        };
    }

    return \@directives;
}

=head2 emit($directives)

Write the file back.  Which file, again, from what is in it.

=cut

sub emit {
    my ( $self, $directives ) = @_;

    my $is_master = scalar( grep { _is_master_key( $_->{key} ) } @$directives );
    return $is_master ? $self->_emit_master($directives) : $self->_emit_main($directives);
}

# A master.cf directive is keyed on the service and its type together, which is
# the one key in either file with a slash in it: main.cf parameter names are
# word characters and underscores.
sub _is_master_key {
    my ($key) = @_;
    return defined $key && index( $key, q{/} ) >= 0;
}

sub _emit_main {
    my ( $self, $directives ) = @_;

    my $out = q{};
    foreach my $directive (@$directives) {
        if ( !defined $directive->{key} ) {
            $out .= ( $directive->{text} // q{} ) . "\n";
            next;
        }
        $out .= "$directive->{key} = $directive->{value}\n";
    }

    return $out;
}

sub _emit_master {
    my ( $self, $directives ) = @_;

    my $out = q{};
    foreach my $directive (@$directives) {
        if ( !defined $directive->{key} ) {
            $out .= ( $directive->{text} // q{} ) . "\n";
            next;
        }

        # master.cf is read by column position, so the columns are padded to the
        # widths postfix's own file uses rather than joined with single spaces.
        my @columns = @{ $directive->{columns} };
        $out .= sprintf( "%-14s %-6s %-7s %-7s %-7s %-7s %-7s %s\n", @columns, $directive->{value} );
        $out .= "$_\n" for @{ $directive->{continuation} // [] };
    }

    return $out;
}

=head1 SEE ALSO

L<Configd::Language>

L<https://www.postfix.org/postconf.5.html>, L<https://www.postfix.org/master.5.html>

=cut

1;
