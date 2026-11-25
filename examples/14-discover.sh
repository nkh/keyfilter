#!/bin/sh
# Find out what the keys of your terminal send.
. "$(dirname "$0")/lib.sh"

title 'discover'

show "keyfilter --discover     # typing Up, F1, Ctrl-Up, a"
out=$(printf '\033[A\033OP\033[1;5Aa' | "$kf" --discover)
printf '%s\n' "$out"

contains 'Up is Escape [ A' 'Key      : Up' "$out"
contains 'with its bytes' 'Sequence : 1b 5b 41' "$out"
contains 'F1' 'Key      : F1' "$out"
contains 'Ctrl-Up' 'Key      : C-Up' "$out"
contains 'a letter' 'Sequence : 61' "$out"

show "keyfilter --discover   # a key that has no name is shown with its bytes"
out=$(printf '\033[15;5A' | "$kf" --discover)
contains 'the key is unknown' 'Key      : (unknown)' "$out"
contains 'and its bytes are shown' 'Sequence : 1b 5b 31 35 3b 35 41' "$out"

show "keyfilter --map 1b5b31353b3541=x -- bash   # use the bytes in a rule"
typed '\033[15;5A' 1 --map 1b5b31353b3541=x
expect 'what the command received' 'x' "$out"

done_ok
