#!/bin/sh
# Rules look at the key that was typed, not at what another rule made of it.
. "$(dirname "$0")/lib.sh"

title 'maps do not chain'

show "keyfilter --map a=b --map b=c -- bash   # typing a, b"
typed 'ab' 2 --map a=b --map b=c
expect 'a gives b, b gives c' 'bc' "$out"

show "keyfilter --map a=b --map b=a -- bash   # swap two keys"
typed 'ab' 2 --map a=b --map b=a
expect 'a gives b, b gives a' 'ba' "$out"

show "keyfilter --map a=b --block b -- bash   # typing a, b, z"
typed 'abz' 2 --map a=b --block b
expect 'what a map gives is not blocked, the typed b is' 'bz' "$out"

done_ok
