package Configd::Language::redis;

#ABSTRACT: redis.conf, which has no conf.d and a handful of directives you say more than once.

use 5.034;

use strict;
use warnings FATAL => 'all';

use re '/aa';

use parent qw{Configd::Language};

use Configd::Syntax::Spaced();

=head1 NAME

Configd::Language::redis - redis.conf, which has no conf.d and a handful of
directives you say more than once.

=head1 SYNOPSIS

    use Configd();

    Configd->adopt('redis');
    Configd->build('redis');

=head1 DESCRIPTION

Redis has an C<include> directive, which is not the same thing as a C<conf.d>:
the included file has to be named from the file doing the including, so adding
one still means editing C<redis.conf>.  Include order also decides precedence in
a way that surprises people -- a directive in the main file B<after> an include
wins over the included one.

So C<redis.conf> becomes generated, and a fragment is a file rather than a file
plus an edit.

=head1 REPEATED DIRECTIVES

Most of redis.conf is one value per directive: a second C<maxmemory> replaces
the first.  A few are not, and mean every occurrence:

=over 4

=item * C<save> -- one line per snapshot point, C<save 900 1> and C<save 300 10>
being two conditions rather than one overriding the other.

=item * C<client-output-buffer-limit> -- one line per client class.

=item * C<rename-command>, C<module>, C<include>, C<bind> when written as
several lines.

=back

Those are matched on everything they say, so two fragments both asking for
C<save 900 1> get one line and two asking for different snapshot points get
both.  That is what lets a fragment be written without checking whether somebody
else already asked for the same thing.

=head1 METHODS

=head2 files()

=head2 units()

=head2 repeats($key)

=head2 parse($text)

=head2 emit($directives)

=cut

# Everything redis takes more than once, meaning each of them.
my %REPEATS = map { $_ => 1 } qw{
  save
  client-output-buffer-limit
  rename-command
  module
  include
  bind
  replicaof
  slaveof
};

sub files {

    # 0640 root:redis as the package ships it, but configd keeps whatever it
    # finds; this is only what a file created from nothing would get.
    return ( { path => '/etc/redis/redis.conf', mode => 0o640 } );
}

sub units {
    return ('redis-server.service');
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
