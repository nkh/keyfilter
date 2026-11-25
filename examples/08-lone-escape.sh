#!/bin/sh
# A lone Escape is a key too, it is sent after 50 milliseconds.
. "$(dirname "$0")/lib.sh"

title 'the Escape key'

show "keyfilter --map Esc=q -- bash       # typing Escape alone"
typed '\033' 1 --map Esc=q
expect 'what the command received' 'q' "$out"

show "keyfilter --map Esc=q -- bash       # Escape followed by a letter is Alt, not Escape"
typed '\033b' 2 --map Esc=q
bytes '\033b'
expect 'what the command received' "$want" "$out"

done_ok
