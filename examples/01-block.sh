#!/bin/sh
# Block keys: they do not reach the command.
. "$(dirname "$0")/lib.sh"

title 'block a key'

show "keyfilter --block C-z -- bash        # typing a, Ctrl-Z, b"
typed 'a\032b' 2 --block C-z
expect 'what the command received' 'ab' "$out"

show "keyfilter --block 'C-z C-c' -- bash  # typing Ctrl-Z, Ctrl-C, x"
typed '\032\003x' 1 --block 'C-z C-c'
expect 'what the command received' 'x' "$out"

show "keyfilter --block C-z --block C-c -- bash"
typed '\032\003y' 1 --block C-z --block C-c
expect 'what the command received' 'y' "$out"

show "keyfilter --block a --unblock a -- bash   # an unblock after a block"
typed 'a' 1 --block a --unblock a
expect 'what the command received' 'a' "$out"

done_ok
