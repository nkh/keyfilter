#!/bin/sh
# Map a key to text: F5 types a command.
. "$(dirname "$0")/lib.sh"

title 'map a key to text'

show "keyfilter --map F5='git status\n' -- bash   # typing F5"
typed '\033[15~' 11 --map 'F5=git status\n'
bytes 'git status\n'
expect 'what the command received' "$want" "$out"

show "keyfilter --map F1='<<Enter>>' -- bash      # typing F1"
typed '\033OP' 1 --map 'F1=<<Enter>>'
bytes '\r'
expect 'what the command received' "$want" "$out"

show "keyfilter --map x='a<<Tab>>b' -- bash       # typing x"
typed 'x' 3 --map 'x=a<<Tab>>b'
bytes 'a\tb'
expect 'what the command received' "$want" "$out"

show "keyfilter --map x='' -- bash                # a map to nothing removes the key"
typed 'axb' 2 --map 'x='
expect 'what the command received' 'ab' "$out"

done_ok
