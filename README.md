# keyfilter

Run a program in a pseudo terminal and decide what the keys you type do: block
them, replace them by text or by other keys, send text to the program at
startup, record the session, and change all that while it runs.

keyfilter is one file written in Perl. Nothing has to be installed, it runs from
where it is. It needs `perl` and the module `IO::Pty`.

    ./keyfilter --help

## Using it

Block a key, so that Ctrl-Z does not suspend your shell:

    ./keyfilter --block C-z -- bash

Map keys to text or to other keys:

    ./keyfilter --map F5='git status\n' -- bash
    ./keyfilter --map 'M-b=<<C-t>>' -- bash

Profiles are files of rules. A name is looked for in `~/.config/keyfilter`, a
path is used as it is. Samples are in `examples/profiles`:

    ./keyfilter --profile examples/profiles/shell.profile -- bash
    ./keyfilter --profile examples/profiles/common.profile --profile examples/profiles/vim.profile -- vim

Copy them to `~/.config/keyfilter` to use their names:

    mkdir -p ~/.config/keyfilter
    cp examples/profiles/*.profile ~/.config/keyfilter/
    ./keyfilter --profile common --profile vim -- vim

Send text to the program when it starts:

    ./keyfilter --startup-delay 500 --send-startup 'source env.sh\n' -- bash

Record a session, and replay it with its pauses or without:

    ./keyfilter --record session.rec -- bash
    ./keyfilter --replay session.rec
    ./keyfilter --replay session.rec --fast

Find out what a key sends, to write a rule for it:

    ./keyfilter --discover

## Changing the rules of a running instance

Every instance has a control socket. `keyfilterctl` is the same file under
another name, a symbolic link is part of the repository:

    ./keyfilterctl ls
    ./keyfilterctl send 'ls -l<<Enter>>'
    ./keyfilterctl toggle gaming
    ./keyfilterctl block C-z
    ./keyfilterctl unblock C-z
    ./keyfilterctl map F5='git status\n'
    ./keyfilterctl --pid 4242 send hello

With several instances running, choose one with `--pid`.

## Keys and text

Keys are written `a`, `C-a`, `M-a`, `S-Tab`, `C-M-Up`, `F5`, `Enter`, `Esc`,
`Space`, or as bytes: `1b5b41`. A replacement is text, with `\n`, `\t`, `\e`,
`\\`, `\#`, `\xHH`, and keys between `<<` and `>>`, for example `<<Enter>>`.
A `#` starts a comment, a literal one is written `\#`.

Rules are evaluated in order. Profiles come first, in the order they are given,
then the rules of the command line, then what was sent to the running instance.
The last map of a key wins, a key that is blocked at the end gives nothing,
and rules look at the key that was typed: maps do not chain.

## Documentation

- `man ./man/keyfilter.1` and `man ./man/keyfilterctl.1`, the manual pages
- `examples/`, scripts that run from the checkout without a terminal, `./examples/run-all.sh` runs them all
- `KeyFilter-Requirements.md`, what keyfilter does, precisely
- `KeyFilter-Implementation-Roadmap.md`, how it was built, step by step

## Tests

    prove

runs the tests, about two thousand five hundred checks. They need no
installation either.
