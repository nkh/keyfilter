# KeyFilter

KeyFilter runs a program inside a PTY and filters keyboard input before the program receives it.

## Features

- Block keys
- Unblock keys
- Map one key to another
- Macros
- Startup text injection
- Discovery mode
- Session recording
- Session replay
- Profiles
- Multiple profiles
- Aliases
- Toggleable rule groups

## Examples

Block Ctrl-Z:

    keyfilter --block C-z -- bash

Map Alt-b to Ctrl-t:

    keyfilter --map M-b=C-t -- bash

Load profile:

    keyfilter --profile vim -- vim

Save profile:

    keyfilter --save-profile vim -- vim

Discovery mode:

    keyfilter --discover

Send startup text:

    keyfilter --startup-delay 500ms \
              --send-startup 'source env.sh\n' \
              -- bash

## Profile Locations

User:

    ~/.config/keyfilter/

System:

    /etc/keyfilter/

## Philosophy

- Small
- Scriptable
- Unix friendly
- Human-readable configuration
- No JSON required
