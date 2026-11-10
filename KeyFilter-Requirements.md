# KeyFilter Requirements Draft

## Goal

KeyFilter is a PTY-based wrapper that launches a child process and filters, remaps, records, injects, and observes terminal input before it reaches the child.

The project should remain:

- Unix-friendly
- dependency-light
- configuration-file friendly
- scriptable with grep/sed/awk
- usable interactively

---

# Key Specifications

Supported forms:

## Named keys

- a
- A
- Enter
- Tab
- Esc
- Up
- Down
- Left
- Right
- Home
- End
- PgUp
- PgDn
- F1..F12

## Modifiers

Examples:

- C-a
- M-a
- M-S-a
- C-M-a
- M-Up
- C-M-S-F5

Modifiers:

- C = Ctrl
- M = Alt / Meta
- S = Shift

Order does not matter.

## Raw sequences

Examples:

- 1b5b41
- \x1b\x5b\x41

Discovery mode should display sequences in a format that can be copied directly into configuration.

---

# Discovery Mode

Example:

    keyfilter --discover

Shows:

- Friendly name when known
- Raw bytes
- Hex dump

Purpose:

- Learn terminal-specific escape sequences
- Build custom filters
- Create mappings for uncommon keys

---

# Blocking

Examples:

    --block C-z
    --block M-F4
    --block-code 1b5b313b3241

Rules are processed through a normalized internal representation.

---

# Unblocking

Examples:

    --unblock C-z

Command-line rules override profile rules.

---

# Mapping

Examples:

    --map M-b=C-t
    --map Up=Down
    --map F1=Enter

Any valid key specification may be used on either side.

Mappings operate on normalized byte sequences.

---

# Macros

Example:

    --macro F5='git status\n'

When F5 is pressed, the text is injected into the child process.

Macros are active while the session is running.

---

# Automatic Startup Injection

New feature.

Example:

    --send-startup 'source env.sh\n'

or

    --send-startup-file init.txt

Purpose:

Automatically type characters into the child process as soon as possible.

Because some programs are not ready immediately after exec(), support:

    --startup-delay 250ms
    --startup-delay 1s

Multiple startup injections should be allowed.

---

# Recording

Example:

    --record session.log

Capture:

- timestamps
- input
- output
- child exit code

---

# Replay

Examples:

    --replay session.log
    --replay-fast session.log

Replay previously recorded sessions.

---

# Profiles

User configuration directory:

    ~/.config/keyfilter/

System configuration directory:

    /etc/keyfilter/

Lookup order:

1. user profile
2. system profile

Examples:

    --profile vim
    --profile work

---

# Multiple Profiles

Example:

    --profile common
    --profile laptop
    --profile vim

Profiles are loaded in order.

Later values override earlier values.

---

# Include Directive

Inside a profile:

    include common.profile

Allow rule reuse.

Circular includes should be detected.

---

# Aliases

Example:

    alias Leader M-Space

Then:

    block Leader

Aliases are expanded before rule processing.

---

# Toggle Rules (Expanded Design)

This is one of the most interesting ideas.

Example:

    toggle M-F12 gaming

A toggle activates or deactivates a named rule set while the child keeps running.

A rule group is a file containing a set of rules in the same format as a profile.

Example rule group:

block C-z
map j=Down
map k=Up

Pressing M-F12:

- enables the group if disabled
- disables it if enabled

Potential uses:

- temporarily disable mappings
- switch between vim/emacs layouts
- gaming mode
- debugging mode
- emergency pass-through mode

# Toggle all rules

Example:

    toggle M-F11 all-rules

pressing M-F11 disables all rules, and pressing it again re-enables them.

---

# One-Shot Mappings

Example:

    map-next F6 Enter

Meaning:

The next time F6 is pressed it becomes Enter.

Then the rule disappears.

Useful for:

- confirmations
- login automation
- setup wizards
- temporary overrides

---

# Macro Recording

## via keyfilterctl

Example:

    keyfilterctrl record-macro --start-stop F5

Meaning:

Record a macro until F5 is pressed; then print the macro to stdout.

## while running keyfilter

Example:

    keyfilter --record-macro F5 --macro-to-stdout --macro-prefix space-m


Meaning:

- record a macro when F5 is pressed until F5 is pressed
- assign the macro to the prefix space-m-index, where index is the number of saved macro in the session
- option macro to-stdout prints all the the macros to stdout after the child process exists

# Remote Control

KeyFilter exposes a UNIX socket.

Example:

    ~/.cache/keyfilter/session.ID.sock

External utility:

    keyfilterctl send ID block C-z
    keyfilterctl send ID unblock C-z
    keyfilterctl send ID stats

Possible operations:

- block
- unblock
- map
- unmap
- enable-group
- disable-group
- inject-text
- display-status

This allows live modification without restarting the child process.

'keyfilterctrl ls' list all the running sessions IDs.

---

# Profile Format

Simple text.

Example:

    block C-z
    block M-F4

    map M-j=Down
    map M-k=Up

    alias Leader M-Space

    include common.profile

No JSON.
No YAML.
No external parser.

Designed to be editable using standard Unix tools.
