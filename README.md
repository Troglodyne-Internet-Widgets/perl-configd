# configd

Give software without a `conf.d` one anyway.

## The problem

Postfix keeps its configuration in `/etc/postfix/main.cf` and offers `postconf
-e` to change it. That is fine for a person at a terminal and wrong for anything
automated, because `postconf -e` *sets* a parameter — there is no way to *add* to
one.

Provisioning a second domain onto a mail server that already hosts one is enough
to hit it:

```
postconf -e "mydestination = first.example.com"    # provisioning the first domain
postconf -e "mydestination = second.example.com"   # provisioning the second
```

The second run does not add the second domain. It replaces the first, and mail
for `first.example.com` quietly stops being delivered locally. Nothing errors,
nothing logs, and the two provisioning runs had no way to know about each other.

Software that ships a `conf.d` does not have this problem: each thing drops in a
file and the daemon reads them all. Plenty of software does not ship one.

## What this does

`configd adopt postfix` gives it one anyway:

* `/etc/postfix/main.cf` becomes **generated output**.
* `/etc/postfix/main.cf.d/` appears beside it, holding fragments in main.cf's own
  syntax.
* Whatever was in `main.cf` becomes `main.cf.d/00-original`, so the
  distribution's defaults and anything the administrator had done keep winning
  wherever nothing later has an opinion.
* A systemd drop-in regenerates the file every time the service starts or
  reloads, so what the daemon reads is always what the fragments say.

Then two domains can each write their own file, and both get what they asked
for:

```
$ printf 'mydestination = first.example.com\n'  > /etc/postfix/main.cf.d/50-first.cf
$ printf 'mydestination = second.example.com\n' > /etc/postfix/main.cf.d/50-second.cf
$ configd build postfix
Rebuilt /etc/postfix/main.cf

$ grep mydestination /etc/postfix/main.cf
mydestination = $myhostname, localhost, first.example.com, second.example.com
```

## Usage

```
configd languages          # what this installation knows how to adopt
configd adopt   postfix    # take the files over and wrap the service
configd status  postfix    # what is adopted, what fragments exist, is it wrapped
configd build   postfix    # regenerate; this is what the drop-in runs
configd release postfix    # put the originals back and let go
```

`--root DIR` works under a directory rather than `/`, which is what you want
when building an image rather than configuring the machine you are on. It
implies `--no-restart`.

## Which parameters merge, and which do not

This is the whole design decision, and it is per parameter.

Most settings are **values**: two fragments setting `myhostname` disagree with
each other, and the later one wins. Some are **lists**: two fragments each
naming a domain in `mydestination` both meant it, and joining them is the only
answer that does not lose one.

`Configd::Language::postfix` accumulates the parameters postfix documents as
comma-or-space separated lists — `mydestination`, `mynetworks`, `relay_domains`,
the `virtual_*` family, the `*_maps` and `*_checks` families, `smtpd_milters`.

It deliberately does **not** accumulate `smtpd_recipient_restrictions` and its
relatives, even though they are lists. They are *ordered* lists where the order
is the meaning, and joining two of them end to end produces something that
parses and that neither fragment asked for — a `permit_` landing ahead of a
check that was supposed to run first is an open relay. Two fragments disagreeing
about a restriction list is something a person should look at.

## Teaching it a new format

Subclass `Configd::Language`, which needs four things from you: which files you
manage, which systemd units read them, how to `parse` the format into directives
and how to `emit` them back. Override `accumulates` for the settings that are
lists.

```
perldoc Configd::Language
```

## How it hooks in

A drop-in at `/etc/systemd/system/<unit>.d/10-configd.conf`:

```
[Service]
ExecStartPre=/usr/bin/configd build postfix
ExecReload=/usr/bin/configd build postfix
```

A drop-in rather than a replacement unit, so that a package upgrade rewriting
the unit does not conflict with a copy we made. For postfix that is
`postfix@.service` — the templated one — because on Debian and Ubuntu
`postfix.service` is a oneshot whose `ExecStart` is `/bin/true`, and the daemon
that actually reads `main.cf` is an instance.

`configd release postfix` removes the drop-in and puts `00-original` back. The
fragment directories are left alone, so adopting again picks up where it left
off.

## Caveats

**Comments are not carried into the generated file.** A comment is anchored to
the setting below it, and once several fragments have had their say there may be
no such setting any more — reproducing the distribution's paragraph above a
value that has since been replaced tells the reader something untrue. They stay
in the fragment they were written in, and `00-original` keeps every one the file
arrived with.

**Editing the generated file works until the next restart.** That is deliberate:
long enough to test something, short enough that nobody comes to rely on it. The
header on the file says so.

## Status

Early. Postfix is implemented and tested; the languages that would come next are
the other monolithic-config software in the fleet — `/etc/default/grub` and
`redis.conf` among them.

The systemd behaviour is the part that most wants a real machine under it: the
tests cover what is written and where, but not what systemd then does with it.
