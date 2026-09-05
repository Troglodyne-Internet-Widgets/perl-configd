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

## Requirements

Core perl 5.34 or newer, and nothing else. Deliberately: this runs from
`ExecStartPre`, so it stands between a service and starting, and it has to work
on whatever perl the guest already has rather than one somebody installed first.
That is a lower bar than the rest of the fleet, which is written against 5.41.

## Status

Early, but exercised against a real machine: an Ubuntu 24.04 guest running
postfix 3.8.6, provisioned by trog-provisioner's `mail` recipe.

Adopting its 64-line `main.cf` changed **no setting** — `postconf -n` was
byte-identical before and after — and `postfix check` stayed clean. Dropping a
second and third domain's fragment in and doing nothing but `systemctl restart
postfix` and `systemctl reload postfix` produced a `mydestination` carrying all
of them, and the server went on answering SMTP throughout.

Four things that only a real machine found, all fixed:

* `systemctl try-restart postfix@.service` is refused — a template is not a
  thing that runs. The drop-in belongs on the template, the restart belongs on
  `postfix.service`; those are now separate questions (`units` and `services`).
* `master.cf` is 0600 on a properly set up mail server. A rename puts the
  temporary file's permissions on the target, so regenerating loosened it.
* The same bug on the way back out: `release` handed a 0644 `main.cf` back as
  0600. Permission preservation now lives in `spew`, so every caller gets it.
* `mydestination` in postfix's own `main.cf` ends with a trailing comma, so
  joining onto it produced `,,`.

Next would be the other monolithic configs in the fleet — `/etc/default/grub`
and `redis.conf` among them.
