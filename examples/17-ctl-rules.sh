#!/bin/sh
# keyfilterctl block, unblock, map: change the rules of a running instance.
. "$(dirname "$0")/lib.sh"

title 'keyfilterctl block, unblock and map'

start_instance 14

send_keys 'x'
show "keyfilterctl block x"
"$ctl" block x
sleep 0.3
send_keys 'xy'
show "keyfilterctl unblock x"
"$ctl" unblock x
sleep 0.3
send_keys 'x'
show "keyfilterctl map F5='git status\n'"
"$ctl" map 'F5=git status\n'
sleep 0.3
send_keys '\033[15~'
finish_instance
bytes 'x' ; first=$want
bytes 'yxgit status\n'
expect 'x, then y only, then x, then F5' "${first}${want}" "$out"

done_ok
