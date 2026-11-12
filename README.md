# KeyFilter

KeyFilter runs a program inside a PTY and filters keyboard input before it reaches the child process.

## Philosophy

- Small
- Single-file
- Unix-friendly
- Human-readable configuration
- No JSON required
- Runtime control through a UNIX socket

## Examples

Block Ctrl-Z:

    keyfilter --block C-z -- bash

Map Alt-b to Ctrl-t:

    keyfilter --map M-b=<<C-t>> -- bash

Map F5 to text:

    keyfilter --map F5='git status\n' -- bash

Load a profile:

    keyfilter --profile vim -- vim

Load multiple profiles:

    keyfilter --profile common \
              --profile vim \
              -- vim

Startup injection:

    keyfilter \
        --startup-delay 500ms \
        --send-startup 'source env.sh\n' \
        -- bash

Discovery mode:

    keyfilter --discover

## Runtime Control

List instances:

    keyfilterctl ls

Toggle a profile:

    keyfilterctl toggle gaming

Block a key:

    keyfilterctl block C-z

Inject characters into the child:

    keyfilterctl send 'abc<<Enter>>'

## Profiles

Profiles live in:

    ~/.config/keyfilter/

Socket files live in:

    ~/.config/keyfilter/sockets/

## Rule Semantics

Rules are evaluated in order.

All matching rules are evaluated.

The original key is used for matching.

The last matching map wins.

Blocking and unblocking determine whether the final output is emitted.
