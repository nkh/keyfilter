#!/bin/sh
# Map a key to another key.
. "$(dirname "$0")/lib.sh"

title 'map a key to another key'

show "keyfilter --map 'M-b=<<C-t>>' -- bash   # Alt-b becomes Ctrl-t"
typed '\033b' 1 --map 'M-b=<<C-t>>'
bytes '\024'
expect 'what the command received' "$want" "$out"

show "keyfilter --map 'Up=<<Down>>' -- bash   # up becomes down"
typed '\033[A' 3 --map 'Up=<<Down>>'
bytes '\033[B'
expect 'what the command received' "$want" "$out"

show "keyfilter --map 'C-a=<<Home>>' -- bash"
typed '\001' 3 --map 'C-a=<<Home>>'
bytes '\033[H'
expect 'what the command received' "$want" "$out"

done_ok
