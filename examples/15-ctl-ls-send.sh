#!/bin/sh
# keyfilterctl: see the instances that run, send text to one.
. "$(dirname "$0")/lib.sh"

title 'keyfilterctl ls and send'

start_instance 5

show "keyfilterctl ls"
listing=$("$ctl" ls)
printf '%s\n' "$listing"
contains 'the instance is listed with its pid' "$bg " "$listing"

show "keyfilterctl send hello"
"$ctl" send hello
sleep 0.3
finish_instance
expect 'what the command received' 'hello' "$out"

done_ok
