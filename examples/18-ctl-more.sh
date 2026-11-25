#!/bin/sh
# keyfilterctl: several instances, choosing one, mistakes.
. "$(dirname "$0")/lib.sh"

title 'keyfilterctl with several instances'

mkfifo "$tmp/in2"
exec 4<>"$tmp/in2"
"$kf" -- sh -c 'stty raw -echo ; echo ready ; head -c 3' <"$tmp/in2" >"$tmp/out2" 2>/dev/null &
second=$!

start_instance 3

sleep 0.5

show "keyfilterctl send x          # two instances run"
message=$("$ctl" send x 2>&1)
code=$?
printf '%s\n' "$message"
expect 'exit status' 2 "$code"
contains 'the pids are named' 'several keyfilter instances are running' "$message"

show "keyfilterctl --pid $bg send abc"
"$ctl" --pid "$bg" send abc
sleep 0.3
finish_instance
expect 'what the chosen command received' 'abc' "$out"

kill "$second" 2>/dev/null
wait "$second" 2>/dev/null

show "keyfilterctl send x          # nothing runs"
message=$("$ctl" send x 2>&1)
code=$?
printf '%s\n' "$message"
expect 'exit status' 2 "$code"

show "keyfilterctl send 'a<<nokey>>'   # a mistake is found before anything is sent"
message=$("$ctl" send 'a<<nokey>>' 2>&1)
code=$?
printf '%s\n' "$message"
expect 'exit status' 1 "$code"

done_ok
