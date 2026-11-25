#!/bin/sh
# Keys that are escape sequences: arrows, function keys, combinations.
. "$(dirname "$0")/lib.sh"

title 'keys that are sequences'

show "keyfilter --block Up -- bash        # typing a, Up, b"
typed 'a\033[Ab' 2 --block Up
expect 'what the command received' 'ab' "$out"

show "keyfilter --block F5 -- bash        # typing a, F5, b"
typed 'a\033[15~b' 2 --block F5
expect 'what the command received' 'ab' "$out"

show "keyfilter --block C-Up -- bash      # typing a, Ctrl-Up, b"
typed 'a\033[1;5Ab' 2 --block C-Up
expect 'what the command received' 'ab' "$out"

show "keyfilter --block 1b5b41 -- bash    # the same Up, as bytes"
typed 'a\033[Ab' 2 --block 1b5b41
expect 'what the command received' 'ab' "$out"

show "keyfilter --block Up -- bash        # Down is not Up"
typed '\033[B' 3 --block Up
bytes '\033[B'
expect 'what the command received' "$want" "$out"

done_ok
