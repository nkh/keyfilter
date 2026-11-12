# KeyFilter Requirements

## Goal

KeyFilter is a PTY-based wrapper that launches a child process and filters, transforms, records, injects, and observes terminal input before it reaches the child.

Design goals:

- Unix-friendly
- single-file implementation
- dependency-light
- human-readable configuration
- scriptable with grep/sed/awk
- configuration, command-line, and runtime control share the same command language

---

# Core Model

Everything is a profile.

Active configuration is built from an ordered list:

1. User-selected profiles
2. `keyfilter_command_line`
3. `keyfilter_runtime`

`keyfilter_command_line` is generated from command-line options.

`keyfilter_runtime` is generated from commands received over the control socket.

Whenever profiles are enabled or disabled, the active rule set is rebuilt from the active profile list.

---

# Key Specifications

## Named keys

Examples:

    a
    A
    Enter
    Tab
    Esc
    Up
    Down
    Left
    Right
    Home
    End
    PgUp
    PgDn
    F1
    F12

## Modifier syntax

Examples:

    C-a
    M-a
    S-Tab
    M-S-a
    C-M-a
    C-M-S-F5

Modifiers:

- C = Ctrl
- M = Alt/Meta
- S = Shift

Order does not matter.

Examples:

    C-M-a
    M-C-a

are equivalent.

## Raw sequences

Examples:

    1b5b41
    \x1b\x5b\x41

---

# Discovery Mode

Purpose:

- learn what the terminal sends
- discover terminal-specific sequences
- build filters and mappings

Example output:

    Key      : Up
    Sequence : 1b 5b 41

Discovery output is intended for humans.

---

# Commands

## block

    block C-z

Blocks a key.

## unblock

    unblock C-z

Re-enables a blocked key.

## map

Examples:

    map a=b

    map F1=git status\n
    map F1=<<Enter>>

    map F1=abc<<Enter>><<C-a>>

A map replaces a matching key with a sequence of characters and/or key symbols.

There is no separate macro command.

A long replacement is simply a map.

---

# Rule Evaluation

All matching rules are evaluated.

Rules are evaluated in declaration order.

Every rule sees the ORIGINAL input key.

Example:

    map a=b
    map b=c

Typing:

    a

Produces:

    b

not:

    c

because transforms never chain.

## Blocking example

Rules:

    block a
    map a=b
    unblock a

Typing:

    a

Produces:

    b

Reason:

- block marks the key as blocked
- map sets replacement to b
- unblock re-enables the key
- final output is allowed

## Multiple mappings

Rules:

    map a=b
    map a=c

Typing:

    a

Produces:

    c

The last matching map wins.

---

# Startup Injection

Special commands are stored separately from rules.

Examples:

    startup-delay 500ms

    send-startup source env.sh\n
    send-startup make\n
After the startup delay expires, startup actions are executed in declaration order.

---

# Profiles

## User directory

    ~/.config/keyfilter/

## Socket directory

    ~/.config/keyfilter/sockets/

## Profile lookup

If a profile name contains a path separator, it is loaded directly.

Examples:

    ./local.profile
    ../test.profile

Otherwise KeyFilter loads:

    ~/.config/keyfilter/<name>.profile

Example:

    profile vim

loads:

    ~/.config/keyfilter/vim.profile

Missing profiles are fatal errors.

---

# Includes

Example:

    include common.profile

Included files may include other files.

A file is loaded at most once.

If a file was already loaded:

    ignore it

and continue.

This prevents include loops automatically.

---

# Toggle Profiles

Examples:

    toggle gaming

If profile gaming is active:

    deactivate it

Otherwise:

    activate it at its original position

Rebuilding preserves profile ordering.

---

# Runtime Control

Every instance creates:

    ~/.config/keyfilter/sockets/<pid>.sock

and optionally:

    ~/.config/keyfilter/sockets/<pid>.info

A socket file alone does not guarantee the process still exists.

The PID must be validated before communication.

## Protocol

One command per line.

Examples:

    block C-z
    map F1=<<Enter>>
    toggle gaming
    send abc<<Enter>>

Commands use the same language as profile files.

No JSON.
No YAML.
No responses are currently sent.

---

# Runtime Rules

Runtime commands are appended to profile:

    keyfilter_runtime

Command-line commands are appended to profile:

    keyfilter_command_line

Active order:

    profiles
    keyfilter_command_line
    keyfilter_runtime

Runtime commands affect only the running instance.

They never modify profile files.

They disappear when KeyFilter exits.

---

# Recording and Replay

Recordings contain:

- timestamps
- input
- output
- child exit code

Replay can run:

- with recorded timing
- as fast as possible

---

# Error Policy

The following conditions are fatal:

- unknown key specification
- unknown command
- missing profile
- invalid mapping cycle
- invalid syntax

Errors should be explicit and easy to diagnose.
