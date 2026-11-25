#!/bin/sh
# Alt, Shift, Control, and their combinations.
. "$(dirname "$0")/lib.sh"

title 'modifiers'

show "keyfilter --map M-a=x -- bash       # Alt-a is Escape then a"
typed '\033a' 1 --map M-a=x
expect 'what the command received' 'x' "$out"

show "keyfilter --block M-a -- bash       # typing a, Alt-a, b"
typed 'a\033ab' 2 --block M-a
expect 'a is not Alt-a' 'ab' "$out"

show "keyfilter --map S-Tab=s -- bash     # Shift-Tab sends Escape [ Z"
typed '\033[Z' 1 --map S-Tab=s
expect 'what the command received' 's' "$out"

show "keyfilter --map C-M-a=x -- bash     # modifiers in any order"
typed '\033\001' 1 --map M-C-a=x
expect 'what the command received' 'x' "$out"

show "keyfilter --map C-M-S-F5=x -- bash"
typed '\033[15;8~' 1 --map C-M-S-F5=x
expect 'what the command received' 'x' "$out"

show "keyfilter --map M-Enter=x -- bash"
typed '\033\r' 1 --map M-Enter=x
expect 'what the command received' 'x' "$out"

done_ok
