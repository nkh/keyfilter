#!/bin/sh
# Help, version, and what mistakes look like.
. "$(dirname "$0")/lib.sh"

title 'help, version, errors'

show "keyfilter --help"
help=$("$kf" --help)
printf '%s\n' "$help" | sed -n '1,4p'
contains 'the help has the options' '--block KEYS' "$help"

show "keyfilter --version"
"$kf" --version

show "keyfilter --map F5 -- bash"
message=$("$kf" --map F5 -- bash 2>&1)
printf '%s\n' "$message"
contains 'a wrong option names the option' "option '--map'" "$message"

show "keyfilter --block bogus -- bash"
message=$("$kf" --block bogus -- bash 2>&1)
printf '%s\n' "$message"
contains 'an unknown key is named' "unknown key specification 'bogus'" "$message"

show "keyfilter --profile nothing -- bash"
message=$("$kf" --profile nothing -- bash 2>&1)
printf '%s\n' "$message"
contains 'a profile that does not exist' "missing profile 'nothing'" "$message"

show "keyfilter --bogus"
message=$("$kf" --bogus 2>&1)
printf '%s\n' "$message"
contains 'an unknown option' "unknown option '--bogus'" "$message"

show "keyfilterctl --help"
"$ctl" --help | sed -n '1,3p'

done_ok
