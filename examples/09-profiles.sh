#!/bin/sh
# Profiles: files of rules, one command per line.
. "$(dirname "$0")/lib.sh"

title 'profiles'

cat >"$HOME/.config/keyfilter/mine.profile" <<'PROFILE'
# my rules
map a=1
block q
PROFILE

show "cat ~/.config/keyfilter/mine.profile"
cat "$HOME/.config/keyfilter/mine.profile"

show "keyfilter --profile mine -- bash      # a name is looked for in ~/.config/keyfilter"
typed 'aqb' 2 --profile mine
expect 'what the command received' '1b' "$out"

show "keyfilter --profile examples/profiles/shell.profile -- bash   # a path"
typed '\033[15~' 11 --profile "$here/profiles/shell.profile"
bytes 'git status\n'
expect 'what the command received' "$want" "$out"

show "keyfilter --profile mine --map a=z -- bash   # the command line comes after the profiles"
typed 'a' 1 --profile mine --map a=z
expect 'what the command received' 'z' "$out"

done_ok
