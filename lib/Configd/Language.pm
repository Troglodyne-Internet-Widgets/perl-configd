package Configd::Language;

#ABSTRACT: Base class for the languages: how one config file format is read, merged and written back.

use 5.041;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use File::Path        qw{make_path};
use File::Slurper     ();
use File::Slurper::Temp();

=head1 NAME

Configd::Language - base class for the languages: how one config file format is
read, merged and written back.

=head1 SYNOPSIS

    package Configd::Language::example;
    use parent qw{Configd::Language};

    sub files {
        return ( { path => '/etc/example.conf', owner => 'root:root', mode => 0644 } );
    }

    sub units    { return ('example.service') }
    sub parse    { my ($self, $text) = @_; ... return \@directives }
    sub emit     { my ($self, $directives) = @_; ... return $text }

=head1 DESCRIPTION

Plenty of software has no C<conf.d>.  Its configuration is one file, and
anything wanting to add to it has to edit that file -- which works exactly once.
The second thing to try it either overwrites what the first did or appends a
duplicate, and neither is what anybody wanted.  Provisioning two domains onto
one mail server is the case that keeps coming up: both want to be in
C<mydestination>, and C<postconf -e> only knows how to set it.

Configd gives that software a C<conf.d> anyway.  For each file it manages there
is a directory beside it -- C</etc/postfix/main.cf> gets C</etc/postfix/main.cf.d>
-- holding fragments in the file's own syntax.  The file itself becomes
B<generated output>: Configd reads every fragment in order, merges them, and
writes the result.  Nothing edits the file any more, and two things adding to it
no longer have to know about each other.

A B<language> is one config file format, and what it has to know is how to read
that format, how two fragments of it combine, and how to write it back.

=head2 How it is kept honest

A generated file that anything else can edit will be edited, and the edit will
be lost the next time it is generated.  So the file is generated at the moment
the service reads it: Configd installs a systemd drop-in on the units the
language names, rebuilding the file before the daemon starts and again before it
is reloaded.  Whatever is in the fragments is what the running service has.

=head2 The first fragment is what was already there

Adopting a file moves it into its own fragment directory as C<00-original>
before anything else is written.  The distribution's defaults, and whatever the
administrator had done to it, become the first fragment and keep winning
wherever nothing later has an opinion.  That is also what makes adoption
reversible: put C<00-original> back and remove the drop-in.

=head1 METHODS TO OVERRIDE

=head2 files()

The files this language manages, as a list of hashrefs:

    { path => '/etc/postfix/main.cf', owner => 'root:root', mode => 0644 }

C<path> is the generated file; its fragment directory is C<path> with C<.d>
appended.  C<owner> and C<mode> are what the generated file is written as, and
default to C<root:root> and 0644.

=cut

sub files {
    return ();
}

=head2 units()

The systemd units that read these files, as a list of names.

A templated unit is named with the C<@> and no instance -- C<postfix@.service>
-- so the drop-in applies to every instance of it.

=cut

sub units {
    return ();
}

=head2 parse($text)

The directives in a fragment, as an arrayref, in the order they were written.

Each directive is a hashref.  What is in it is the language's business, but two
keys are common to all of them because C<merge> reads them:

=over 4

=item * C<key> -- what makes two directives the same directive.  Two with the
same key are the same setting said twice, and the later one wins unless the
language says otherwise.  A directive with no key is never merged with anything
and is kept in the order it arrived, which is what comments and blank lines are.

=item * C<value> -- what C<key> was set to.

=back

=cut

sub parse {
    my ( $self, $text ) = @_;
    die( ( ref $self || $self ) . " does not know how to parse anything\n" );
}

=head2 emit($directives)

The text of a config file holding those directives, ready to write.

=cut

sub emit {
    my ( $self, $directives ) = @_;
    die( ( ref $self || $self ) . " does not know how to write anything\n" );
}

=head2 accumulates($key)

Whether a directive is a list that fragments add to, rather than a value that a
later fragment replaces.

False by default, which is the right answer for most settings: two fragments
setting C<myhostname> disagree, and the later one wins.  It is the wrong answer
for the ones that are lists -- C<mydestination>, C<virtual_mailbox_domains> --
where two fragments each naming a domain both meant it, and replacing loses one
of them.  That distinction is the whole reason this exists.

=cut

sub accumulates {
    my ( $self, $key ) = @_;
    return 0;
}

=head2 separator($key)

What joins the parts of an accumulating directive.  A comma and a space by
default, which is what postfix uses; whitespace-separated languages override it.

=cut

sub separator {
    my ( $self, $key ) = @_;
    return ', ';
}

=head1 METHODS

=head2 $class->new(%opts)

C<root> relocates every path this language touches, so a test -- or a build for
a guest that is not this machine -- works against a directory rather than the
running system's C</etc>.

=cut

sub new {
    my ( $class, %opts ) = @_;
    $opts{root} //= q{};
    $opts{root} =~ s{/\z}{};
    return bless { %opts }, $class;
}

=head2 $language->name()

What this language is called on the command line: the last component of the
package name.

=cut

sub name {
    my ($self) = @_;
    my $class = ref $self || $self;
    return ( split( q{::}, $class ) )[-1];
}

=head2 $language->path($path)

C<$path> under this language's C<root>.  Every path in this class goes through
it, so that nothing writes outside the root it was given.

=cut

sub path {
    my ( $self, $path ) = @_;
    return $self->{root} . $path;
}

=head2 $language->fragment_dir($file)

The directory a file's fragments live in: the file's own path with C<.d> on the
end.

=cut

sub fragment_dir {
    my ( $self, $file ) = @_;
    return $self->path( $file->{path} ) . '.d';
}

=head2 $language->fragments($file)

The fragment files for one managed file, in the order they are merged.

Sorted by name, so the numeric prefixes everybody already writes on C<conf.d>
entries do what they look like they do.  Names starting with a dot are skipped,
and so is anything ending in C<.disabled>, C<.bak>, C<.dpkg-old> or C<~> --
editors and package managers leave those lying about, and a stray backup silently
taking part in the merge is a bad afternoon.

=cut

sub fragments {
    my ( $self, $file ) = @_;

    my $dir = $self->fragment_dir($file);
    opendir( my $dh, $dir ) or return ();
    my @names = sort grep { !m/\A[.]/ && !m/(?:[.](?:disabled|bak|dpkg-old|dpkg-new|dpkg-dist|rpmsave|rpmnew)|~)\z/ } readdir($dh);
    closedir $dh;

    return map { "$dir/$_" } grep { -f "$dir/$_" } @names;    ## no critic (ValuesAndExpressions::ProhibitFiletest_f)
}

=head2 $language->merge(@fragment_sets)

One list of directives out of several, applying C<accumulates> to decide which
of two directives for the same key wins and which of them join up.

Order is the order the keys were first seen, so a generated file reads like the
fragments that made it rather than like a hash.

Comments and blank lines are B<not> carried through.  A merged file cannot say
where a comment belongs -- the distribution's paragraph explaining a default sits
above a setting some later fragment has since replaced, and reproducing it there
tells the reader something that is no longer true.  They stay in the fragment
they were written in, which is where somebody editing will be looking, and
C<00-original> keeps every one the file arrived with.

=cut

sub merge {
    my ( $self, @sets ) = @_;

    my ( @order, %by_key );
    foreach my $set (@sets) {
        foreach my $directive (@$set) {
            my $key = $directive->{key};

            # Comments and blank lines.  Deliberately dropped rather than
            # collected: see the POD above.  A comment is anchored to the
            # setting under it, and once several fragments have had their say
            # there is no longer a setting for it to be anchored to.
            next if !defined $key;

            if ( !exists $by_key{$key} ) {
                push @order, $key;
                $by_key{$key} = { %$directive };
                next;
            }

            if ( $self->accumulates($key) ) {
                $by_key{$key}{value} = join(
                    $self->separator($key),
                    grep { defined && length } $by_key{$key}{value}, $directive->{value}
                );
                next;
            }

            # The later fragment is the one that meant it.
            $by_key{$key} = { %$directive };
        }
    }

    return [ map { $by_key{$_} } @order ];
}

=head2 $language->build($file)

Read every fragment for one file, merge them, and return the text to write.

=cut

sub build {
    my ( $self, $file ) = @_;

    my @sets;
    foreach my $fragment ( $self->fragments($file) ) {
        push @sets, $self->parse( File::Slurper::read_text($fragment) );
    }

    return $self->emit( $self->merge(@sets) );
}

=head2 $language->header($file)

The comment Configd puts at the top of a file it generates, saying so.

Somebody is going to edit the generated file -- it is where the settings are,
and it is where every piece of documentation on the internet says they live.
This is the one chance to tell them their edit will not survive the next restart
and where to put it instead.

=cut

sub header {
    my ( $self, $file ) = @_;

    my $dir = $file->{path} . '.d';
    return <<"HEADER";
# Generated by configd.  Do not edit: this file is rebuilt from
# $dir every time the service starts or reloads,
# and anything you change here will be gone the next time that happens.
#
# Add a file to that directory instead, in this file's own syntax.  They are
# read in order by name, and later ones win.  What was here when configd
# adopted this file is 00-original, comments and all -- those stay in the
# fragments rather than being merged into this file, where they could only
# describe settings something later has since changed.
HEADER
}

=head2 $language->write($file)

Generate one file and put it in place, returning true if what is on disk
changed.

Written through a temporary file in the same directory and renamed over the
target, so that a service reading it at that moment sees the old file or the
new one and never half of either.

=cut

sub write {
    my ( $self, $file ) = @_;

    my $target = $self->path( $file->{path} );
    my $wanted = $self->header($file) . $self->build($file);

    my $current = -f $target ? File::Slurper::read_text($target) : undef;    ## no critic (ValuesAndExpressions::ProhibitFiletest_f)
    return 0 if defined $current && $current eq $wanted;

    File::Slurper::Temp::write_text( $target, $wanted );
    chmod( $file->{mode} // 0644, $target );

    return 1;
}

=head2 $language->adopt()

Take over every file this language manages: make each one's fragment directory,
move what is there now into it as C<00-original>, and generate the file.

Does nothing to a file it has already adopted, so running it twice is safe.

=cut

sub adopt {
    my ($self) = @_;

    my @adopted;
    foreach my $file ( $self->files() ) {
        my $target   = $self->path( $file->{path} );
        my $dir      = $self->fragment_dir($file);
        my $original = "$dir/00-original";

        make_path($dir) unless -d $dir;

        # Already ours.  Re-adopting would take the file we generated last time
        # and make it the first fragment, which duplicates every setting in it.
        if ( -f $original ) {                                                ## no critic (ValuesAndExpressions::ProhibitFiletest_f)
            $self->write($file);
            next;
        }

        if ( -f $target ) {                                                  ## no critic (ValuesAndExpressions::ProhibitFiletest_f)
            File::Slurper::Temp::write_text( $original, File::Slurper::read_text($target) );
        }
        else {
            File::Slurper::Temp::write_text( $original, q{} );
        }

        $self->write($file);
        push @adopted, $file->{path};
    }

    return @adopted;
}

=head2 $language->release()

Give a file back: put C<00-original> where it came from and forget about it.

The counterpart to C<adopt>, and the reason C<00-original> is kept rather than
merged away.  Removing the drop-in is L<Configd::Unit>'s half of it.

=cut

sub release {
    my ($self) = @_;

    my @released;
    foreach my $file ( $self->files() ) {
        my $original = $self->fragment_dir($file) . '/00-original';
        next unless -f $original;                                            ## no critic (ValuesAndExpressions::ProhibitFiletest_f)

        File::Slurper::Temp::write_text( $self->path( $file->{path} ), File::Slurper::read_text($original) );
        push @released, $file->{path};
    }

    return @released;
}

=head1 SEE ALSO

L<Configd::Unit>, L<Configd::Language::postfix>

=cut

1;
