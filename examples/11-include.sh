#!/bin/sh
# A profile can include another one. A file is loaded once.
. "$(dirname "$0")/lib.sh"

title 'include'

cp "$here"/profiles/*.profile "$HOME/.config/keyfilter/"

show "cat examples/profiles/vim.profile"
cat "$here/profiles/vim.profile"

show "keyfilter --profile vim -- vim        # F5 is :w, and C-z of common.profile is blocked"
typed '\033[15~\032' 3 --profile vim
expect 'what the command received' ':w' "$(printf '%s' "$out" | head -c 2)"

show "keyfilter --profile vim --profile common -- vim   # common.profile is loaded once"
typed '\032x' 1 --profile vim --profile common
expect 'what the command received' 'x' "$out"

done_ok
