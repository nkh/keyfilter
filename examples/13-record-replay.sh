#!/bin/sh
# Record a session, replay it with its pauses, replay it fast.
. "$(dirname "$0")/lib.sh"

title 'record and replay'

show "keyfilter --record session.rec -- sh -c 'echo one; sleep 0.4; echo two; exit 3'"
"$kf" --record "$tmp/session.rec" -- sh -c 'echo one ; sleep 0.4 ; echo two ; exit 3' </dev/null >"$tmp/live.out"
expect 'exit code of the session' 3 "$?" 2>/dev/null || true
code=$?

show "cat session.rec"
cat -v "$tmp/session.rec"

start=$(date +%s)
show "keyfilter --replay session.rec"
"$kf" --replay "$tmp/session.rec" >"$tmp/timed.out"
timed_code=$?

show "keyfilter --replay session.rec --fast"
"$kf" --replay "$tmp/session.rec" --fast >"$tmp/fast.out"
fast_code=$?

expect 'a replay shows what the session showed' "$(cat -v "$tmp/live.out")" "$(cat -v "$tmp/timed.out")"
expect 'a fast replay shows the same' "$(cat -v "$tmp/live.out")" "$(cat -v "$tmp/fast.out")"
expect 'exit code of the replay' 3 "$timed_code"
expect 'exit code of the fast replay' 3 "$fast_code"

done_ok
