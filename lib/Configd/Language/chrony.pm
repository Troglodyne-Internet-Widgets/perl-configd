package Configd::Language::chrony;

#ABSTRACT: chrony.conf, where every time source is its own line.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use parent qw{Configd::Language};

use Configd::Syntax::Spaced();

=head1 NAME

Configd::Language::chrony - chrony.conf, where every time source is its own
line.

=head1 SYNOPSIS

    use Configd();

    Configd->adopt('chrony');
    Configd->build('chrony');

=head1 DESCRIPTION

Newer chrony has a C<confdir> directive and Debian points it at
F</etc/chrony/conf.d>.  Where that exists, use it -- this is for the versions
and the images where it does not, which is most of what is deployed.

Check before adopting:

    ls -d /etc/chrony/conf.d

=head1 REPEATED DIRECTIVES

Time sources are the point of the file and there is one line per source:
C<server>, C<pool> and C<peer> all mean every occurrence, as do the C<allow> and
C<deny> lines that say who may ask this host the time.

Everything else is a value a later fragment replaces -- two fragments disagreeing
about C<makestep> disagree, and the later one wins.

=head1 METHODS

=head2 files()

=head2 units()

=head2 reloads()

=head2 repeats($key)

=head2 parse($text)

=head2 emit($directives)

=cut

my %REPEATS = map { $_ => 1 } qw{
  server
  pool
  peer
  allow
  deny
  refclock
  initstepslew
  broadcast
  sourcedir
  confdir
  include
  hwtimestamp
};

sub files {
    return ( { path => '/etc/chrony/chrony.conf', mode => 0o644, owner => 'root:root' } );
}

# chrony.service on Debian and Ubuntu, chronyd.service on Red Hat -- and on
# Ubuntu both names resolve, because chrony.service declares
# Alias=chronyd.service and enabling it drops a symlink under
# /etc/systemd/system.  Following that symlink is how this ended up writing a
# drop-in systemd never reads and restarting the same daemon twice.
my @SPELLINGS = qw{chrony.service chronyd.service};

sub _real_units {
    my ($self) = @_;

    my @found;
    foreach my $name (@SPELLINGS) {
        foreach my $dir (qw{/lib/systemd/system /usr/lib/systemd/system /etc/systemd/system}) {
            my $path = $self->path("$dir/$name");
            next unless -e $path;

            # An alias, pointing at a unit we have already named.
            next if -l $path;

            push @found, $name;
            last;
        }
    }

    return @found;
}

sub units {
    my ($self) = @_;

    # Nothing installed means we are building for a machine that is not this
    # one -- a --root somewhere -- and both spellings are the honest answer.
    my @real = $self->_real_units();
    return @real ? @real : @SPELLINGS;
}

sub reloads {

    # chronyd has no way to re-read its configuration, which is why the packaged
    # unit has no ExecReload.  Adding one would make `systemctl reload chrony`
    # start reporting success while the daemon carries on with the configuration
    # it started with.
    return 0;
}

sub repeats {
    my ( $self, $key ) = @_;
    return $REPEATS{$key} // 0;
}

sub parse {
    my ( $self, $text ) = @_;
    return Configd::Syntax::Spaced::parse($text);
}

sub emit {
    my ( $self, $directives ) = @_;
    return Configd::Syntax::Spaced::emit($directives);
}

=head1 SEE ALSO

L<Configd::Language>, L<Configd::Syntax::Spaced>

=cut

1;
