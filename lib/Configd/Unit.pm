package Configd::Unit;

#ABSTRACT: The systemd drop-in that rebuilds a language's files before the daemon reads them.

use 5.041;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use File::Path        qw{make_path remove_tree};
use File::Slurper     ();
use File::Slurper::Temp();

=head1 NAME

Configd::Unit - the systemd drop-in that rebuilds a language's files before the
daemon reads them.

=head1 SYNOPSIS

    use Configd::Unit();

    my $unit = Configd::Unit->new( language => $postfix, configd => '/usr/bin/configd' );
    my @written = $unit->install();
    $unit->reload();

=head1 DESCRIPTION

A generated file is only true until somebody edits it, and the file Configd
generates is the one every piece of documentation on the internet tells people
to edit.  Rather than trying to stop that, Configd regenerates the file at the
moment it matters: a systemd drop-in on the units the language names, running
C<configd build> before the daemon starts and again before it is told to reload.

The daemon therefore always reads what the fragments say, and an edit to the
generated file survives exactly until the next restart -- which is long enough
to test something and short enough that nobody comes to rely on it.

=head2 Why a drop-in rather than a unit of our own

Replacing the packaged unit means owning it: every upgrade that changes it is a
conflict to resolve, and a distribution that reworks how the service starts
breaks a copy that was accurate when it was made.  A drop-in in
C</etc/systemd/system/E<lt>unitE<gt>.d/> adds to whatever the package ships and
keeps working across an upgrade that rewrites it.

=head2 Ordering

C<ExecStartPre> lines in a drop-in are B<appended> to the ones the packaged unit
already has, so ours runs after the package's own pre-start work and still
before C<ExecStart>.  That is the order we want: the package's script sets an
instance up, and we write the config the daemon is about to read.

Prepending would mean clearing the list with an empty C<ExecStartPre=> and
restating every line the package shipped, which is precisely the copy that goes
stale on upgrade.

=cut

our $DROPIN = '10-configd.conf';

=head1 METHODS

=head2 $class->new(%opts)

=over 4

=item * C<language> -- the L<Configd::Language> whose units these are.  Required.

=item * C<configd> -- the path to the C<configd> executable as the unit will
invoke it.  Defaults to C</usr/bin/configd>; systemd needs it absolute.

=item * C<root> -- write under here rather than C</>, for tests.  Taken from the
language when not given.

=back

=cut

sub new {
    my ( $class, %opts ) = @_;

    die "A Configd::Unit needs a language\n" unless $opts{language};

    $opts{configd} //= '/usr/bin/configd';
    $opts{root}    //= $opts{language}{root} // q{};
    $opts{root} =~ s{/\z}{};

    return bless { %opts }, $class;
}

=head2 $unit->dropin_dir($unit_name)

Where a unit's drop-ins live.

=cut

sub dropin_dir {
    my ( $self, $name ) = @_;
    return "$self->{root}/etc/systemd/system/$name.d";
}

=head2 $unit->render()

The drop-in's text.

=cut

sub render {
    my ($self) = @_;

    my $language = $self->{language}->name();
    my $configd  = $self->{configd};
    my @files    = map { $_->{path} } $self->{language}->files();
    my $list     = join( "\n", map { "#   $_" } @files );

    return <<"UNIT";
# Installed by configd.  Removing this file and running `systemctl daemon-reload`
# is all it takes to stop configd having anything to do with this service; the
# files below stay exactly as they were last generated.
#
$list
#
# Each of those is built from the directory of the same name with .d on the end.
# Edit the fragments, not the file: this rebuilds it on every start and reload.

[Service]
ExecStartPre=$configd build $language
ExecReload=$configd build $language
UNIT
}

=head2 $unit->install()

Write the drop-in for every unit the language names, returning the paths
written.

=cut

sub install {
    my ($self) = @_;

    my $wanted = $self->render();

    my @written;
    foreach my $name ( $self->{language}->units() ) {
        my $dir  = $self->dropin_dir($name);
        my $path = "$dir/$DROPIN";

        make_path($dir) unless -d $dir;

        my $current = -f $path ? File::Slurper::read_text($path) : undef;    ## no critic (ValuesAndExpressions::ProhibitFiletest_f)
        next if defined $current && $current eq $wanted;

        File::Slurper::Temp::write_text( $path, $wanted );
        push @written, $path;
    }

    return @written;
}

=head2 $unit->uninstall()

Take the drop-in back off every unit, returning the paths removed.

The generated files are left where they are, because the service is running on
them.  L<Configd::Language/release> is what puts the originals back.

=cut

sub uninstall {
    my ($self) = @_;

    my @removed;
    foreach my $name ( $self->{language}->units() ) {
        my $dir  = $self->dropin_dir($name);
        my $path = "$dir/$DROPIN";
        next unless -f $path;    ## no critic (ValuesAndExpressions::ProhibitFiletest_f)

        unlink $path or die "Could not remove $path: $!\n";
        push @removed, $path;

        # An empty .d directory is litter, but one holding somebody else's
        # drop-in is theirs.
        rmdir $dir;
    }

    return @removed;
}

=head2 $unit->installed()

Whether every unit this language names currently has the drop-in.

=cut

sub installed {
    my ($self) = @_;

    my @units = $self->{language}->units();
    return 0 unless @units;

    foreach my $name (@units) {
        return 0 unless -f $self->dropin_dir($name) . "/$DROPIN";    ## no critic (ValuesAndExpressions::ProhibitFiletest_f)
    }

    return 1;
}

=head1 SEE ALSO

L<Configd::Language>

=cut

1;
