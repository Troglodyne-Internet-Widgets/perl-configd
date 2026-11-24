#!perl
use 5.034;

use strict;
use warnings FATAL => 'all';
use re '/aa';

=head1 NAME

t/Configd-Language-ossec.t - ossec.conf merged from the configuration of the
package and the fragments after it

=cut

use Test::More;
use Test::Fatal qw{exception};
use File::Temp  qw{tempdir};
use File::Path  qw{make_path};

use FindBin::libs;

# Recommended, not required: see metamerge.yml.
BEGIN {
    eval { require XML::LibXML; 1 } or plan( skip_all => 'Configd::Language::ossec needs XML::LibXML, which is not installed' );
}

use Configd();
use Configd::Language();
use Configd::Language::ossec();    ## no critic (ProhibitUnusedImports) -- the class whose methods the test calls by name

# The shape of the configuration that the package installs, with its example
# settings.
my $PACKAGE = <<'XML';
<!-- OSSEC example config -->
<ossec_config>
  <global>
    <email_notification>yes</email_notification>
    <email_to>bogus@example.com</email_to>
  </global>

  <rules>
    <include>rules_config.xml</include>
    <include>pam_rules.xml</include>
    <!-- <include>disabled_rules.xml</include> -->
    <include>syslog_rules.xml</include>
    <include>local_rules.xml</include>
  </rules>

  <syscheck>
    <frequency>79200</frequency>
    <directories check_all="yes">/etc,/usr/bin</directories>
  </syscheck>
</ossec_config>

<ossec_config>
  <global>
    <white_list>127.0.0.1</white_list>
    <white_list>192.0.2.10</white_list>
  </global>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/messages</location>
  </localfile>

  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>
</ossec_config>
XML

my $FRAGMENT = <<'XML';
<ossec_config>
  <global>
    <email_notification>no</email_notification>
    <white_list/>
    <white_list>127.0.0.1</white_list>
  </global>
  <rules>
    <include>pam_rules.xml</include>
    <include>trog_rules.xml</include>
  </rules>
  <localfile/>
  <remote>
    <connection>syslog</connection>
    <port>10514</port>
  </remote>
  <syscheck>
    <disabled>yes</disabled>
  </syscheck>
</ossec_config>
XML

sub merged {
    my (@fragments) = @_;
    my $language = 'Configd::Language::ossec'->new();
    my @parsed;
    foreach my $fragment (@fragments) {
        push @parsed, $language->parse($fragment);
    }
    return $language->emit( $language->merge(@parsed) );
}

sub includes {
    my ($xml) = @_;
    return [ $xml =~ m{<include>([^<]+)</include>}sxg ];
}

subtest 'the package and a fragment' => sub {
    my $xml = merged( $PACKAGE, $FRAGMENT );

    is_deeply( includes($xml), [qw{rules_config.xml pam_rules.xml syslog_rules.xml local_rules.xml trog_rules.xml}], 'the rule files of the package in its order, none that it comments out, and the new one after them' );
    like( $xml, qr{<email_notification>no</email_notification>}sx,                'a setting of the fragment wins' );
    like( $xml, qr{<email_to>bogus[@]example[.]com</email_to>}sx,                 'and one that it does not name stays' );
    like( $xml, qr{<directories[ ]check_all="yes">/etc,/usr/bin</directories>}sx, 'with its attributes' );
    like( $xml, qr{<disabled>yes</disabled>.*</syscheck>}sx,                      'in its section, beside what the fragment adds' );
    is_deeply( [ $xml =~ m{<white_list>([^<]+)</white_list>}sxg ], ['127.0.0.1'], 'an empty element clears its list, and what comes after it adds to nothing' );
    is_deeply( [ $xml =~ m{<location>([^<]+)</location>}sxg ],     [],            'and an empty section clears every block of it' );
    my $remote = qr{<remote>\s*<connection>syslog</connection>}sx;
    my $port   = qr{\s*<port>10514</port>\s*</remote>}sx;
    like( $xml, qr{$remote$port}sx, 'a block of the fragment is added' );

    my @sections = $xml =~ m{^[ ][ ]<(\w+)}msxg;
    is_deeply( \@sections, [qw{global rules syscheck remote}], 'one of each section that appears once, in the order first seen' );
};

subtest 'what it writes, it reads back' => sub {
    my $xml   = merged( $PACKAGE, $FRAGMENT );
    my $again = merged($xml);
    is( $again,                       $xml,             'the same file, merged on its own' );
    is( merged( $PACKAGE, $PACKAGE ), merged($PACKAGE), 'and a fragment that repeats what is there changes nothing' );
};

subtest 'the generated file starts with a comment that XML allows' => sub {
    my $header = 'Configd::Language::ossec'->new()->header( { path => '/var/ossec/etc/ossec.conf' } );
    like( $header, qr{\A<!--\n.*-->\n\z}sx, 'one comment' );
    my ($inside) = $header =~ m{\A<!--(.*)-->}sx;
    unlike( $inside, qr/--/sx, 'with no two hyphens inside it' );
    like( $inside, qr{ossec[.]conf[.]d}sx, 'naming the directory of the fragments' );
    is_deeply( 'Configd::Language::ossec'->new()->parse( $header . merged($PACKAGE) ), 'Configd::Language::ossec'->new()->parse( merged($PACKAGE) ), 'and the file reads the same with it' );
};

subtest 'what it refuses' => sub {
    my $language = 'Configd::Language::ossec'->new();
    like( exception { $language->parse("<agent_config>\n</agent_config>\n") },             qr/is[ ]not[ ]<ossec_config>/sx, 'a root other than ossec_config' );
    like( exception { $language->parse("<ossec_config>\n  <global>\n</ossec_config>\n") }, qr/Cannot[ ]read[ ]the[ ]XML/sx, 'a tag that is not closed' );
    like( exception { $language->parse("stray\n<ossec_config/>\n") },                      qr/Text[ ]outside/sx,            'and text outside of an element' );
};

subtest 'two hyphens in a comment, which the package writes and XML forbids' => sub {
    my $xml = merged(<<'XML');
<ossec_config>
  <syscheck>
    <!-- Frequency that syscheck is executed -- default every 20 hours -->
    <frequency>79200</frequency>
    <!-- one -- and two -- on a line --><directories>/etc</directories>
  </syscheck>
  <localfile><location>/var/log/a--b.log</location></localfile>
</ossec_config>
XML
    like( $xml,                                                                         qr{<frequency>79200</frequency>}sx,             'the file is read' );
    like( $xml,                                                                         qr{<directories>/etc</directories>}sx,          'past two of them on one line' );
    like( $xml,                                                                         qr{<location>/var/log/a--b[.]log</location>}sx, 'and two hyphens outside of a comment are left as they are' );
    like( exception { merged("<ossec_config><!-- a -- b --><global></ossec_config>") }, qr/Cannot[ ]read[ ]the[ ]XML/sx,                'and any other error still stops it' );
};

subtest 'what a real parser reads that a guess would not' => sub {
    my $xml = merged("<ossec_config><global><email_to>a&amp;b\@example.com</email_to></global><localfile><location><![CDATA[/var/log/<x>.log]]></location></localfile></ossec_config>");
    like( $xml, qr{<email_to>a&amp;b[@]example[.]com</email_to>}sx,            'an entity is written back as it was' );
    like( $xml, qr{<location><!\[CDATA\[/var/log/<x>[.]log\]\]></location>}sx, 'and CDATA is read, and written back as it was' );
    my $commented = merged("<ossec_config><localfile><location attr=\"&lt;!--\">/x</location></localfile></ossec_config>");
    like( $commented, qr{<location[ ]attr="&lt;!--">/x</location>}sx, 'and a comment marker inside an attribute is not a comment' );
};

subtest 'adopting the file of the package' => sub {
    my $root = tempdir( CLEANUP => 1 );
    make_path("$root/var/ossec/etc");
    Configd::Language::spew( "$root/var/ossec/etc/ossec.conf", $PACKAGE );
    chmod 0o660, "$root/var/ossec/etc/ossec.conf";

    Configd->adopt( 'ossec', root => $root );
    Configd::Language::spew( "$root/var/ossec/etc/ossec.conf.d/50-collector", $FRAGMENT );
    Configd->build( 'ossec', root => $root );

    my $xml = Configd::Language::slurp("$root/var/ossec/etc/ossec.conf");
    is( Configd::Language::slurp("$root/var/ossec/etc/ossec.conf.d/00-original"), $PACKAGE, 'the file of the package is 00-original' );
    like( $xml, qr{<email_notification>no</email_notification>}sx, 'and the generated file has the fragment in it' );
    is( ( stat "$root/var/ossec/etc/ossec.conf" )[2] & 0o7777, 0o660, 'with the mode that the package gave it' );
};

done_testing();
