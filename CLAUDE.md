# CLAUDE.md

This file is the procedure for work in this repository.  `README.md` says what
the code is.  The POD of each module says how it works.

Configd gives software that has no `conf.d` one anyway.  A language in
`lib/Configd/Language/` knows the file format of one service.  `bin/configd`
adopts the files of a service, builds them again, and gives them back.
`Configd::Unit` writes the systemd drop-in that runs the build.

## Which skills, and when

The hooks of the perl-slop plugin hold you to the procedure.  They refuse an
edit to Perl until `perl-slop:reading-perl` is loaded.  They refuse a commit of
Perl until `perl-slop:data-perl`, `perl-slop:testing-perl` and
`perl-slop:reviewing-perl` are loaded, each one after the last commit.  A
refusal names the skills that are missing.

The hooks cannot see one case.  Before you answer a question about the code,
or look for something in it, load `perl-slop:reading-perl`.

## Read the code before you change it

A line that looks pointless is usually the scar of something that went wrong
once.  The reason is in the commit, not in the file.  Read `git blame` and the
commit before the first edit, not after the tests fail.

## The standards of the harness

`.perlcriticrc` and `.perltidyrc` come from `conformance update`.  Do not turn
off a policy to make the code pass.  If a policy is wrong for one place, turn
it off there with `## no critic (Policy::Name) -- the reason` on the line.

These rules need the most thought here:

- Every regular expression has the flags `/s` and `/x`.  Under `/x` a space is
  not literal.  Write `[ ]` for a space and `\#` for a hash sign.
- `no autovivification;` is on in the modules that read through nested data.
- The name of a language is the name of its service, in lower case, because a
  person types it: `configd adopt postfix`.  The package line of such a module
  gives the reason that `NamingConventions::Capitalization` is off for it.

## Build and test

- Run the tests with `prove -l t`.
- Run the critic with `perlcritic --profile .perlcriticrc bin lib t`.
- Tidy a file with `perltidy --profile=.perltidyrc -b -bext='/' FILE`.

The tests run in a directory of their own through the `root` option.  A test
must never write to the real `/etc`, and must never run `systemctl`.

## Where it is written down

| | |
|---|---|
| `README.md` | what Configd is for, and the commands |
| `perldoc Configd::Language` | how to write a language, and which methods it overrides |
| `perldoc Configd::Syntax::Spaced` | the `key value` format that four languages share |
| `Changes` | one entry for each change that a user sees |
