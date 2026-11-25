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

Combinations that cannot be encoded for a key are fatal errors, use a raw sequence for those.

## Raw sequences

Examples:

    1b5b41
    \x1b\x5b\x41

A token that is both a key name and valid hexadecimal is the key: F1 is the key, f1 is the byte f1.

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

Discovery is started with `keyfilter --discover`.

Each key is followed by a blank line. A key that has no name is shown as `(unknown)`, its sequence is still shown.

When the input is a terminal, discovery puts it in raw mode and tells how to stop on the error output. Ctrl-C pressed twice in a row ends discovery, so does the end of the input.

---

# Comments

A # starts a comment that extends to the end of the line.

The part of the line before the # is still valid:

    map a=b # a types b

Whitespace before a comment is ignored.

To use a literal # write \# in a replacement or in a key specification:

    map F1=issue \#12<<Enter>>

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

## Replacement syntax

Plain characters are sent as they are.

Key symbols are written between << and >>:

    <<Enter>>
    <<C-a>>

Escapes:

    \n      newline
    \r      carriage return
    \t      tab
    \e      escape
    \\      backslash
    \<      literal <
    \#      literal #
    \xHH    byte in hexadecimal

An unknown escape, an unterminated key symbol and an unknown key are fatal errors.

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

If the key is still blocked when all rules have been evaluated, it produces no output, even if a map matched it.

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

    startup-delay 500

    send-startup source env.sh\n
    send-startup make\n
The delay is a number of milliseconds, no unit is written.

After the startup delay expires, startup actions are executed in declaration order.

The delay is counted from the moment the child is started. There is one delay for all the startup actions, if several `startup-delay` commands are declared the last one wins, wherever it is declared. Without one the delay is zero.

Declaration order is the order of the files and of the lines: profiles in the order they are loaded, and an included file where its `include` is.

The text of a startup action is sent to the child as it is. Rules and filters do not apply to it. Text typed by the user before the delay expires reaches the child before it, text typed after reaches the child after it.

If the child has ended when the delay expires, nothing is sent.

---

# Profiles

## User directory

    ~/.config/keyfilter/

## Socket directory

    ~/.config/keyfilter/sockets/

## Profile file

A profile file contains one command per line.

Blank lines and comments are ignored.

Errors are reported as file:line: message.

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

A relative path is resolved against the directory of the including file.

Included files may include other files.

A file is loaded at most once.

If a file was already loaded:

    ignore it

and continue.

This prevents include loops automatically.

The set of loaded files is shared by all the profiles loaded together, a file included by two profiles is loaded once.

---

# Toggle Profiles

Examples:

    toggle gaming

If profile gaming is active:

    deactivate it

Otherwise:

    activate it at its original position

Rebuilding preserves profile ordering.

The active rules are built once and kept, they are built again each time the chain changes: a profile is toggled on or off, a runtime rule is added. Rules that were given out earlier are not changed. Finding the rules of a key does not depend on how many rules there are.

A profile that is not loaded, a name or a path, is loaded when it is toggled on, with the same lookup as `--profile`. It is added after the profiles of the chain. A profile that is known by its name is the same profile whether it is written as a name or as a path. If it cannot be loaded, because it does not exist or has an error, nothing changes, the instance keeps the error.

The reserved names `keyfilter_runtime` and `keyfilter_command_line` cannot be toggled.

Toggling never changes the order of the profiles. A profile that comes back is back where it was, between the same neighbours, so it does not win over the profiles after it. A profile that was loaded when it was first toggled on keeps the place it was added at, after the profiles that were known before it.

A profile that is toggled off stays known, its rules are no longer used. The files a profile included belong to it, a file that was included by two profiles is loaded once, by the first, so toggling the first off also removes the rules of that file for the second.

The startup commands of a profile that is toggled on are not run, startup is only at the start. The rules of the command line and the runtime profile always stay after all the profiles.

---

# Runtime Control

Every instance creates:

    ~/.config/keyfilter/sockets/<pid>.sock

and optionally:

    ~/.config/keyfilter/sockets/<pid>.info

The socket directory is created, private to the user, when it does not exist. The socket is private to the user too. A file or a socket left under the same name by an instance that ended without cleaning up is replaced. The socket is removed when the instance ends.

A socket path is limited by the system to about a hundred characters, a longer one is a fatal error.

A socket file alone does not guarantee the process still exists.

The PID must be validated before communication.

The instances are found by listing the socket directory. A socket is an instance when its name is `<pid>.sock`, it is a socket, and the process `<pid>` is alive. A process that has ended but was not reaped is not alive. Instances are sorted by pid, as numbers. Files left by processes that are gone are ignored, not removed.

The information file is a list of `name: value` lines, it tells what the instance runs:

    command: bash -l
    started: 1700000000

Characters that are not printable are replaced by spaces in a value. Lines that are not `name: value` are ignored. The file is optional.

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

A connection can carry any number of lines. A line ends with a newline, a carriage return before it is ignored. A last line without a newline is used when the connection ends. Blank lines and comments are ignored.

These commands are accepted at runtime:

    block, unblock, map, toggle, send

The others, `startup-delay`, `send-startup`, `include` and `profile`, make no sense in a running instance and are refused.

A line that is wrong, an unknown command, a syntax error, a command that is refused, is ignored. The lines around it are still used, the connection stays open. Nobody is told, the instance keeps the errors.

A line is limited to 65536 bytes. A client that sends more without ending its line is disconnected.

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

The names `keyfilter_runtime` and `keyfilter_command_line` are reserved, a profile file cannot have them.

The runtime profile only holds rules: `block`, `unblock` and `map`. The command line profile holds the rules and the startup commands given as options, `--block`, `--unblock`, `--map`, `--startup-delay` and `--send-startup`. A rule of a later layer overrides a rule of an earlier one, as rules do inside a profile.

Startup commands of the command line come after those of the profiles, so a `--startup-delay` wins over the delay of a profile.

Runtime commands affect only the running instance. A runtime `block`, `unblock` or `map` applies to the keys typed after it. A runtime `send` is delivered to the child at once, after what was typed before it and before what is typed after it, rules and filters do not apply to it, and a recording has it as input. What a map sends to the child is not looked at by the rules again, maps do not chain, and the text of a startup is not mapped. Typed bytes are split into keys, a sequence like `Up` is one key even when it arrives in pieces. While there are no rules at all, typed bytes go to the child unchanged and at once. A lone Escape is sent after 50 milliseconds, when nothing completes it.

They never modify profile files.

They disappear when KeyFilter exits.

---

# Recording and Replay

Recordings contain:

- timestamps
- input
- output
- child exit code

A recording is a text file, one event per line. The first line is a comment that gives the format.

Input is what the child received: the input after filtering, the end of the input, and the text sent by a startup. Output is what the child wrote, as it was forwarded.

Each event line starts with its time, in seconds with six decimals, counted from the creation of the recording. Times never go back, events that happen together have the same time.

A recording of a run ends with the exit code of the child, as the event `X`, written `X 3`. The exit code of a child killed by a signal is 128 plus the signal number. Nothing comes after it. A run that fails has no exit code in its recording.

Bytes are written as printable text: the characters from space to tilde as they are, a backslash as `\\`, and `\n`, `\r`, `\t` and `\e` for the usual controls. Any other byte is `\xHH` in lower case hexadecimal.

A session is recorded with:

    keyfilter --record session.rec -- bash

It is replayed with:

    keyfilter --replay session.rec

Replay writes the recorded output to the standard output, input events are not shown. It exits with the recorded exit code, or 0 if the recording has none. An invalid recording, one whose times go back, is a fatal error that names the file and the line.

Replay can run:

- with recorded timing
- as fast as possible

The default is recorded timing: replay waits until the time of each event, and until the time of the exit code. With `--fast` there is no waiting, the output and the exit code are the same:

    keyfilter --replay session.rec --fast

`--fast` is only valid with `--replay`.

---

# keyfilterctl

`keyfilterctl` controls the instances of keyfilter that run for the current user. It is the same file as keyfilter, started under the name `keyfilterctl`, for example through a symbolic link:

    ln -s keyfilter keyfilterctl

    keyfilterctl ls

`ls` lists the instances, one per line: the pid, a space, and the command the instance runs. The instances are sorted by pid. Instances whose process is gone are not listed. An instance that has no information file has the command `(unknown)`. Without instances nothing is printed, it is not an error.

    keyfilterctl [--pid PID] command [arguments]
    keyfilterctl -h | --help

    keyfilterctl send TEXT

`send` sends text to the command of the instance, as the command `send` of the instance does. The text is written as the replacement of a map: `\n`, `\t`, `\e`, `\xHH` and keys between `<<` and `>>`. Several arguments are joined with a space. Spaces at the start of the text are not kept, write `\x20`. A `#` starts a comment, write `\#`. The text cannot contain a line end, write `\n`.

    keyfilterctl send 'ls -l<<Enter>>'

The text is checked before anything is sent, a mistake in it is a usage error. Nothing is sent to the instance then. The instance does not answer, `send` only tells that the text was handed over.

    keyfilterctl toggle PROFILE

`toggle` turns a profile of the instance on if it is off, and off if it is on, as the command `toggle` of the instance does. The profile is a name or a path. The name has no space and no `#`, the reserved names are refused. A profile that the instance does not have is loaded. If it cannot be loaded the instance keeps running with the profiles it had.

    keyfilterctl block KEYS
    keyfilterctl unblock KEYS
    keyfilterctl map KEY=REPLACEMENT

These send the rule to the instance, it is added to the runtime profile and applies to the keys typed after it. The arguments are joined with a space and written as the argument of the command of the same name, with the same syntax. The rule is checked before it is sent, a mistake is a usage error and nothing is sent.

    keyfilterctl block C-z
    keyfilterctl map F5='git status\n'

`-p` or `--pid` chooses the instance for the commands that talk to one. `-h` and `--help` show the usage on the standard output.

Without `--pid` the commands that talk to an instance use the only one that runs. If none runs, or several do, they fail with exit status 2 and a message that names the pids. A pid that is not an instance, and an instance that cannot be connected to, also give 2.

Exit status: 0 on success, 1 for a wrong command line, 2 when no instance can be reached.

---

# Command Line

    keyfilter [options] [--] command [args...]
    keyfilter --discover
    keyfilter --replay FILE [--fast]
    keyfilter -h | --help | --version

Rules and profiles:

    --block KEYS             same as the command block
    --unblock KEYS           same as the command unblock
    --map KEY=REPLACEMENT    same as the command map
    --profile NAME           load a profile, a name or a path
    --startup-delay MS       same as the command startup-delay
    --send-startup TEXT      same as the command send-startup

The value of an option is written as the argument of the command of the same name, with the same syntax and the same escapes, a `#` starts a comment, a literal one is written `\#`. An option that is wrong is a fatal error that names the option.

Options can be repeated and mixed. The order of the profiles is the order of the `--profile` options. The rule and startup options make the command line profile, which comes after the profiles. Where an option is placed among the others does not change that.

Other options:

    --record FILE            record the session
    --replay FILE            replay a recording
    --fast                   replay without the recorded pauses
    --discover               show what the keys of the terminal send
    --no-socket              do not create the control socket
    -h, --help               show the help
    --version                show the version

`-h` and `--help` print the usage, the options and examples on the standard output and exit with 0. They are looked for before the other options are checked, so they work whatever else is on the command line. After the command, or after `--`, everything is for the command.

Every instance creates its control socket and an information file, unless `--no-socket` is given. If the socket cannot be created, keyfilter says so on the error output and runs the command anyway.

Errors in the command line exit with 1, errors in a profile, a recording or the command exit with 255. Otherwise keyfilter exits with the exit code of the command.

## Documentation

A manual page is part of the program: `keyfilter(1)`, which also describes `keyfilterctl`, and `keyfilterctl(1)`. They are written in the man format, they are in the repository, and they are checked by the tests.

## Examples

The repository has an `examples` directory of scripts. They run directly from a checkout, nothing has to be installed. They do not need a terminal, they use a private home directory so they do not touch the files of the user, they print what they do and what comes out, and they end with 0 when they work. `examples/run-all.sh` runs them all. The tests run every example.

---

# Error Policy

The following conditions are fatal:

- unknown key specification
- unknown command
- missing profile
- invalid syntax

Errors should be explicit and easy to diagnose.
