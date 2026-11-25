#!/bin/sh
# Several profiles: the later ones have the last word.
. "$(dirname "$0")/lib.sh"

title 'several profiles'

printf 'map a=c\nmap b=c\n' >"$HOME/.config/keyfilter/common.profile"
printf 'map a=v\n' >"$HOME/.config/keyfilter/vim.profile"

show "keyfilter --profile common --profile vim -- vim   # typing a, b"
typed 'ab' 2 --profile common --profile vim
expect 'a from vim, b from common' 'vc' "$out"

show "keyfilter --profile vim --profile common -- vim"
typed 'ab' 2 --profile vim --profile common
expect 'the other way round' 'cc' "$out"

done_ok
