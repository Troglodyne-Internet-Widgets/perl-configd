package Configd;

#ABSTRACT: Give software without a conf.d one anyway.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use File::Basename qw{basename};
use Module::Load   ();

use Configd::Unit();

=head1 NAME

Configd - give software without a conf.d one anyway.

=head1 SYNOPSIS

    use Configd();

    my @known = Configd->languages();
    my $postfix = Configd->language('postfix');

    Configd->adopt('postfix');    # take the files over, wrap the service
    Configd->build('postfix');    # regenerate, which the unit does for you
    Configd->release('postfix');  # give them back

=head1 DESCRIPTION

Some software takes its configuration from one file and offers no way to add to
it. Anything automating that software has to edit the file, and two things
editing the same file cannot both win: the second one either overwrites the
first or duplicates it.

Configd puts a fragment directory beside each such file, makes the file itself
generated output, and rebuilds it from the fragments whenever the service starts
or reloads. Adding to the configuration becomes writing a file, which two
things can do without knowing about each other.

L<Configd::Language> is where the design is written down and what you subclass
to teach it a new format.

=head1 CLASS METHODS

=head2 languages()

The languages this installation knows about, by name.

Found by looking through C<@INC> rather than by keeping a list, so a language
dropped in by a site -- or by a distribution that ships one -- is found without
anything here being edited.

=cut

sub languages {
    my ($class) = @_;

    my %seen;
    foreach my $dir (@INC) {
        my $path = "$dir/Configd/Language";
        opendir( my $dh, $path ) or next;
        foreach my $file ( readdir($dh) ) {
            next unless $file =~ m/\A(\w+)[.]pm\z/;
            $seen{$1} = 1;
        }
        closedir $dh;
    }

    return sort keys %seen;
}

=head2 language($name, %opts)

One language, loaded and instantiated. C<%opts> reaches its constructor, which
is how C<root> gets there.

Dies naming what is available when there is no such language, because the
alternative is a typo looking exactly like a language that does not handle the
file you expected.

=cut

sub language {
    my ( $class, $name, %opts ) = @_;

    die "Which language?\n" unless defined $name && length $name;

    # It becomes part of a module name, so it has to be a name and not a path.
    die "'$name' is not a language name\n" unless $name =~ m/\A\w+\z/;

    my $module = "Configd::Language::$name";
    eval { Module::Load::load($module); 1 } or do {
        my @known = $class->languages();
        die "No language '$name'. This installation knows: " . join( ', ', @known ) . "\n";
    };

    return $module->new(%opts);
}

=head2 build($name, %opts)

Regenerate every file a language manages, returning the paths that changed.

This is what the systemd drop-in runs, so it does exactly this and nothing else:
no C<systemctl>, which would deadlock against the start it is part of, and no
adopting, because a service starting is not the time to be taking files over.

=cut

sub build {
    my ( $class, $name, %opts ) = @_;

    my $language = $class->language( $name, %opts );

    my @changed;
    foreach my $file ( $language->files() ) {
        push @changed, $file->{path} if $language->write($file);
    }

    return @changed;
}

=head2 adopt($name, %opts)

Take a language's files over and wrap its service: move each file into its own
fragment directory as C<00-original>, generate it, and install the drop-in.

Returns a hashref of what happened, which is what the command line prints.
Safe to run again: a file already adopted is regenerated rather than adopted a
second time, and re-adopting is the one thing that would duplicate every setting
in it.

Reloading systemd and restarting the service are the caller's, so that a caller
building an image rather than configuring a running machine can skip them.

=cut

sub adopt {
    my ( $class, $name, %opts ) = @_;

    my $language = $class->language( $name, %opts );
    my @adopted  = $language->adopt();
    my $unit     = Configd::Unit->new( language => $language, %opts );

    return {
        adopted => \@adopted,
        dropins => [ $unit->install() ],
        units   => [ $language->services() ],
    };
}

=head2 release($name, %opts)

Give a language's files back: restore each C<00-original> and remove the
drop-in.

The fragment directories are left alone. They are somebody's configuration, and
throwing them away on the way out means a release followed by an adopt loses
everything that was ever added.

=cut

sub release {
    my ( $class, $name, %opts ) = @_;

    my $language = $class->language( $name, %opts );
    my $unit     = Configd::Unit->new( language => $language, %opts );

    return {
        dropins  => [ $unit->uninstall() ],
        released => [ $language->release() ],
        units    => [ $language->services() ],
    };
}

=head2 status($name, %opts)

What a language is doing right now: its files, whether each is adopted, how many
fragments it has, and whether the drop-in is in place.

=cut

sub status {
    my ( $class, $name, %opts ) = @_;

    my $language = $class->language( $name, %opts );
    my $unit     = Configd::Unit->new( language => $language, %opts );

    my @files;
    foreach my $file ( $language->files() ) {
        my @fragments = $language->fragments($file);
        push @files, {
            path      => $file->{path},
            adopted   => ( scalar grep { basename($_) eq '00-original' } @fragments ) ? 1 : 0,
            fragments => [ map { basename($_) } @fragments ],
        };
    }

    return {
        language => $language->name(),
        files    => \@files,
        units    => [ $language->units() ],
        wrapped  => $unit->installed(),
    };
}

=head1 SEE ALSO

L<Configd::Language>, L<Configd::Unit>, L<Configd::Language::postfix>

=cut

1;
