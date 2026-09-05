#!/usr/bin/env perl
use 5.034;

use strict;
use warnings FATAL => 'all';
use re '/aa';

=head1 NAME

t/configd.t - the command line: what each command prints, what it exits, and
when it is allowed to touch systemd

=cut

use Test::More;
use Test::MockModule;

use FindBin;
use FindBin::libs;

use Test::Configd qw{scratch fragment};

use Configd::Language();

require_ok("$FindBin::RealBin/../bin/configd") or BAIL_OUT('the modulino does not load');

# Every command's output, and what it exited.  The commands are run in process
# rather than through system(), so that a test failure says which line was
# wrong rather than which exit code was.
sub run {
    my (@args) = @_;

    my $out = q{};
    my $exit;
    {
        open( my $fh, '>', \$out ) or die "Could not capture output: $!\n";
        local *STDOUT = $fh;
        $exit = Configd::Bin::Configd::main(@args);
    }

    return ( $exit, $out );
}

# systemctl is not something a test may run, and whether it is reached at all is
# the thing being asserted.
my $systemd = Test::MockModule->new( 'Configd::Bin::Configd', no_auto => 1 );
my @dispatched;
$systemd->redefine( systemd => sub { push @dispatched, $_[0]; return 0 } );

subtest 'languages lists what is installed' => sub {
    my ( $exit, $out ) = run('languages');

    is( $exit, 0, 'exits zero' );
    like( $out, qr/^postfix$/m, 'and names a language it found on disk' );
};

subtest 'a root means these are not this machine files, so nothing is restarted' => sub {

    # The reason --root implies it: adopting into an image, or looking at what
    # would happen, must not try-restart the postfix running on the machine
    # doing the looking.
    @dispatched = ();
    my $root = scratch();

    my ( $exit, $out ) = run( '--root', $root, 'adopt', 'postfix' );

    is( $exit, 0, 'adopt exits zero' );
    is_deeply( \@dispatched, [], 'and systemd was not touched' );
    like( $out, qr{Adopted /etc/postfix/main\.cf},                             'saying what it took over' );
    like( $out, qr{Wrote \Q$root\E/etc/systemd/system/postfix\@\.service\.d/}, 'and where the drop-in went' );
    like( $out, qr/Not restarting/,                                            'and that it stopped short of the restart' );
};

subtest 'without a root it restarts what runs, not the template' => sub {

    # systemctl refuses to restart postfix@.service, so an adopt that passed the
    # drop-in unit along would report a failure after having done its job.
    @dispatched = ();
    my $root = scratch();

    my ($exit) = run( '--root', $root, qw{--restart adopt postfix} );

    is( $exit, 0, 'adopt exits zero' );
    is_deeply( \@dispatched, [ ['postfix.service'] ], 'the unit that has a process behind it' );
};

subtest 'build says what it rebuilt, and says when there was nothing to do' => sub {
    my $root = scratch();
    run( '--root', $root, 'adopt', 'postfix' );

    my ( $exit, $out ) = run( '--root', $root, 'build', 'postfix' );
    is( $exit, 0, 'exits zero' );
    like( $out, qr/already up to date/, 'nothing changed' );

    fragment( $root, 'main.cf', '50-example.cf', "mydestination = example.com\n" );
    ( $exit, $out ) = run( '--root', $root, 'build', 'postfix' );
    like( $out, qr{Rebuilt /etc/postfix/main\.cf}, 'and names the file when one does' );
};

subtest 'status exits non-zero until the service is actually wrapped' => sub {

    # So that `configd status postfix && ...` means what it looks like it means.
    my $root = scratch();

    my ( $exit, $out ) = run( '--root', $root, 'status', 'postfix' );
    is( $exit, 1, 'not wrapped is a failure' );
    like( $out, qr/NOT adopted/, 'and it says the files are not adopted' );
    like( $out, qr/NOT wrapped/, 'nor the service wrapped' );

    run( '--root', $root, 'adopt', 'postfix' );
    fragment( $root, 'main.cf', '50-example.cf', "mydestination = example.com\n" );

    ( $exit, $out ) = run( '--root', $root, 'status', 'postfix' );
    is( $exit, 0, 'wrapped is a success' );
    like( $out, qr/2 fragments/,          'counting the fragments' );
    like( $out, qr/^\s+50-example\.cf$/m, 'and naming them' );

    # The drop-in is on the template, which is what status reports; the restart
    # goes elsewhere.  Reporting the restart target here would say the wrong
    # unit was wrapped.
    like( $out, qr/\Qpostfix@.service\E: wrapped/, 'the unit the drop-in is on' );
};

subtest 'release puts it back and lets go' => sub {
    @dispatched = ();
    my $root = scratch();
    my $was  = Configd::Language::slurp("$root/etc/postfix/main.cf");

    run( '--root', $root, 'adopt', 'postfix' );
    my ( $exit, $out ) = run( '--root', $root, 'release', 'postfix' );

    is( $exit, 0, 'exits zero' );
    is_deeply( \@dispatched, [], 'and does not restart under a root either' );
    like( $out, qr{Removed \Q$root\E/etc/systemd/system/}, 'the drop-in is gone' );
    like( $out, qr{Restored /etc/postfix/main\.cf},        'and the file is back' );
    is( Configd::Language::slurp("$root/etc/postfix/main.cf"), $was, 'byte for byte' );
};

subtest 'quiet says nothing it does not have to' => sub {
    my $root = scratch();

    my ( $exit, $out ) = run( '--root', $root, qw{--quiet adopt postfix} );
    is( $exit, 0,   'still does the work' );
    is( $out,  q{}, 'and prints none of it' );
    ok( -e "$root/etc/postfix/main.cf.d/00-original", 'the file really was adopted' );    ## no critic (ValuesAndExpressions::ProhibitFiletest_f)
};

subtest 'a command or a language that does not exist says so' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };

    my ($exit) = run('frobnicate');
    is( $exit, 2, 'an unknown command is a usage error' );
    like( $warnings[-1], qr/No such command 'frobnicate'/, 'naming it' );
    like( $warnings[-1], qr/adopt/,                        'and listing the ones there are' );

    ($exit) = run( 'status', 'nosuchthing' );
    is( $exit, 1, 'an unknown language is a plain failure' );
    like( $warnings[-1], qr/No language 'nosuchthing'/, 'naming it too' );
};

done_testing();
