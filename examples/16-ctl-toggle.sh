#!/bin/sh
# keyfilterctl toggle: turn profiles on and off in a running instance.
. "$(dirname "$0")/lib.sh"

title 'keyfilterctl toggle'

printf 'map a=1\n' >"$HOME/.config/keyfilter/base.profile"
printf 'map a=2\n' >"$HOME/.config/keyfilter/gaming.profile"

start_instance 4 --profile base

send_keys 'a'
show "keyfilterctl toggle gaming   # turn on a profile that was not loaded"
"$ctl" toggle gaming
sleep 0.3
send_keys 'a'
show "keyfilterctl toggle gaming   # turn it off"
"$ctl" toggle gaming
sleep 0.3
send_keys 'a'
show "keyfilterctl toggle gaming   # and on again, where it was"
"$ctl" toggle gaming
sleep 0.3
send_keys 'a'
finish_instance
expect 'a typed with base, gaming on, off, on' '1212' "$out"

done_ok
