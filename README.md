# NAME

Configd - Give software without a conf.d one anyway.

# VERSION

version 0.001

# SYNOPSIS

```perl
use Configd();

my @known = Configd->languages();
my $postfix = Configd->language('postfix');

Configd->adopt('postfix');    # take the files over, wrap the service
Configd->build('postfix');    # regenerate, which the unit does for you
Configd->release('postfix');  # give them back
```

# DESCRIPTION

Postfix keeps its configuration in `/etc/postfix/main.cf` and offers
`postconf -e` to change it.  That is fine for a person at a terminal and wrong
for anything automated, because `postconf -e` **sets** a parameter -- there is no
way to **add** to one.

Provisioning a second domain onto a mail server that already hosts one is enough
to hit it:

```perl
postconf -e "mydestination = first.example.com"     # the first domain
postconf -e "mydestination = second.example.com"    # the second
```

The second run does not add the second domain.  It replaces the first, and mail
for `first.example.com` quietly stops being delivered locally.  Nothing errors,
nothing logs, and the two provisioning runs had no way to know about each other.

Software that ships a `conf.d` does not have this problem: each thing drops in a
file and the daemon reads them all.  Plenty of software does not ship one.

## What this does

`configd adopt postfix` gives it one anyway:

- `/etc/postfix/main.cf` becomes **generated output**.
- `/etc/postfix/main.cf.d/` appears beside it, holding fragments in
main.cf's own syntax.
- Whatever was in main.cf becomes `main.cf.d/00-original`, so the
distribution's defaults and anything the administrator had done keep winning
wherever nothing later has an opinion.
- A systemd drop-in regenerates the file every time the service starts or
reloads, so what the daemon reads is always what the fragments say.

Two domains can then each write their own file and both get what they asked for:

```perl
mydestination = $myhostname, localhost, first.example.com, second.example.com
```

## Which settings merge, and which do not

This is the whole design decision, and it is per setting.

Most are **values**: two fragments setting `myhostname` disagree, and the later
one wins.  Some are **lists**: two fragments each naming a domain in
`mydestination` both meant it, and joining them is the only answer that does not
lose one.  A language says which is which by overriding `accumulates`.

[Configd::Language::postfix](https://metacpan.org/pod/Configd%3A%3ALanguage%3A%3Apostfix) deliberately does **not** accumulate
`smtpd_recipient_restrictions` and its relatives, even though they are lists.
They are _ordered_ lists where the order is the meaning, and joining two end to
end produces something that parses and that neither fragment asked for -- a
`permit_` landing ahead of a check that was supposed to run first is an open
relay.  Two fragments disagreeing about a restriction list is something a person
should look at.

## Caveats

**Comments are not carried into the generated file.**  A comment is anchored to
the setting below it, and once several fragments have had their say there may be
no such setting any more -- reproducing the distribution's paragraph above a
value that has since been replaced tells the reader something untrue.  They stay
in the fragment they were written in, and `00-original` keeps every one the file
arrived with.

**Editing the generated file works until the next restart.**  That is deliberate:
long enough to test something, short enough that nobody comes to rely on it.  The
header on the file says so.

## Requirements

Core perl 5.34 or newer, and nothing else.  Deliberately: this runs from
`ExecStartPre`, so it stands between a service and starting, and it has to work
on whatever perl the guest already has rather than one somebody installed first.
Ubuntu 24.04 ships 5.38 and 22.04 ships 5.34.

[Configd::Language](https://metacpan.org/pod/Configd%3A%3ALanguage) is where the design is written down and what you subclass
to teach it a new format.  Read the part about checking for a native `conf.d`
first: this is for software that has none, and using it where a real mechanism
exists trades a working feature for a moving part.

# NAME

Configd - give software without a conf.d one anyway.

# CLASS METHODS

## languages()

The languages this installation knows about, by name.

Found by looking through `@INC` rather than by keeping a list, so a language
dropped in by a site -- or by a distribution that ships one -- is found without
anything here being edited.

## language($name, %opts)

One language, loaded and instantiated. `%opts` reaches its constructor, which
is how `root` gets there.

Dies naming what is available when there is no such language, because the
alternative is a typo looking exactly like a language that does not handle the
file you expected.

## build($name, %opts)

Regenerate every file a language manages, returning the paths that changed.

This is what the systemd drop-in runs, so it does exactly this and nothing else:
no `systemctl`, which would deadlock against the start it is part of, and no
adopting, because a service starting is not the time to be taking files over.

## adopt($name, %opts)

Take a language's files over and wrap its service: move each file into its own
fragment directory as `00-original`, generate it, and install the drop-in.

Returns a hashref of what happened, which is what the command line prints.  Its
`services` is what to restart, which is not always what the drop-in went on --
see ["services()" in Configd::Language](https://metacpan.org/pod/Configd%3A%3ALanguage#services).

Safe to run again: a file already adopted is regenerated rather than adopted a
second time, and re-adopting is the one thing that would duplicate every setting
in it.

Reloading systemd and restarting the service are the caller's, so that a caller
building an image rather than configuring a running machine can skip them.

## release($name, %opts)

Give a language's files back: restore each `00-original` and remove the
drop-in.

The fragment directories are left alone. They are somebody's configuration, and
throwing them away on the way out means a release followed by an adopt loses
everything that was ever added.

## status($name, %opts)

What a language is doing right now: its files, whether each is adopted, how many
fragments it has, and whether the drop-in is in place.

# SEE ALSO

Please see those modules/websites for more information related to this module.

- [Configd::Language](https://metacpan.org/pod/Configd%3A%3ALanguage), [Configd::Unit](https://metacpan.org/pod/Configd%3A%3AUnit), [Configd::Language::postfix](https://metacpan.org/pod/Configd%3A%3ALanguage%3A%3Apostfix)

# AUTHORS

Current Maintainers:

- George S. Baugh <george@troglodyne.net>

# COPYRIGHT AND LICENSE

Copyright (c) 2026 Troglodyne LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
