package Test::Configd;

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use parent qw{Exporter};

use File::Path qw{make_path};
use File::Temp qw{tempdir};

use Configd::Language();

our @EXPORT_OK = qw{scratch fragment};

=head1 NAME

Test::Configd - the fixture the tests share: a root with a postfix in it

=head1 SYNOPSIS

    use Test::Configd qw{scratch fragment};

    my $root = scratch();
    fragment( $root, 'main.cf', '50-example.cf', "mydestination = example.com\n" );

=head1 FUNCTIONS

=head2 scratch()

A temporary root holding the main.cf and master.cf a freshly installed postfix
has, at the modes a real one has them: 0644 and 0600.  Cleaned up with the
process.

=cut

sub scratch {
    my $root = tempdir( CLEANUP => 1 );
    make_path("$root/etc/postfix");

    Configd::Language::spew( "$root/etc/postfix/main.cf", <<'CF' );
# See /usr/share/postfix/main.cf.dist for a commented, fuller version.
myhostname = mail.example.com
mydestination = $myhostname, localhost
smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination
CF

    Configd::Language::spew( "$root/etc/postfix/master.cf", <<'CF' );
# service type  private unpriv  chroot  wakeup  maxproc command
smtp      inet  n       -       y       -       -       smtpd
CF

    chmod 0o644, "$root/etc/postfix/main.cf";
    chmod 0o600, "$root/etc/postfix/master.cf";

    return $root;
}

=head2 fragment($root, $file, $name, $text)

Drop a fragment into one of those files' fragment directories.

=cut

sub fragment {
    my ( $root, $file, $name, $text ) = @_;

    make_path("$root/etc/postfix/$file.d");
    Configd::Language::spew( "$root/etc/postfix/$file.d/$name", $text );

    return;
}

1;
