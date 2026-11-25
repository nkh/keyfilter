#!/bin/sh
# Send text to the command when it starts, after a delay.
. "$(dirname "$0")/lib.sh"

title 'startup'

show "keyfilter --startup-delay 500 --send-startup 'echo hello\n' -- sh   # no key is typed"
out=$( (sleep 2) | $limit ${limit:+30} "$kf" --startup-delay 300 --send-startup 'echo hello\nexit\n' -- sh 2>&1 )
contains 'the shell ran the line that was sent' 'hello' "$out"

show "keyfilter --startup-delay 300 --send-startup one --send-startup two -- bash"
typed '' 6 --startup-delay 300 --send-startup one --send-startup two
expect 'the texts arrive in order' 'onetwo' "$out"

show "keyfilter --map o=O --startup-delay 300 --send-startup one -- bash   # rules do not apply to it"
typed '' 3 --map o=O --startup-delay 300 --send-startup one
expect 'what the command received' 'one' "$out"

done_ok
