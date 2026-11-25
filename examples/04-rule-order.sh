#!/bin/sh
# Rules are evaluated in order, all the rules of a key, the last map wins.
. "$(dirname "$0")/lib.sh"

title 'the order of the rules'

show "keyfilter --map a=1 --map a=2 -- bash"
typed 'a' 1 --map a=1 --map a=2
expect 'the last map wins' '2' "$out"

show "keyfilter --block a --map a=b --unblock a -- bash"
typed 'a' 1 --block a --map a=b --unblock a
expect 'blocked, mapped, unblocked: the map applies' 'b' "$out"

show "keyfilter --map a=b --block a -- bash       # typing a, z"
typed 'az' 1 --map a=b --block a
expect 'blocked at the end: nothing for a' 'z' "$out"

show "keyfilter --block a --unblock a --block a -- bash   # typing a, z"
typed 'az' 1 --block a --unblock a --block a
expect 'blocked again: nothing for a' 'z' "$out"

done_ok
