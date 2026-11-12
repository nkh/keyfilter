# KeyFilter Implementation Roadmap

## Milestone 0 - Infrastructure

### Step 1
- Create Makefile
- Create t/ directory
- Add smoke test

Test:
- t/01-smoke.t

### Step 2
- Create internal package structure
- No behavior changes

Test:
- t/02-packages.t

---

## Milestone 1 - Key Parsing

### Step 3
- parse_key_specs(): basic keys

Test:
- t/03-basic-keys.t

### Step 4
- Ctrl keys

Test:
- t/04-ctrl.t

### Step 5
- Named keys

Test:
- t/05-named-keys.t

### Step 6
- Navigation keys

Test:
- t/06-navigation-keys.t

### Step 7
- Function keys

Test:
- t/07-function-keys.t

### Step 8
- Modifiers

Test:
- t/08-modifiers.t

### Step 9
- Raw sequences

Test:
- t/09-raw-sequences.t

### Step 10
- Replacement parser

Test:
- t/10-replacement-parser.t

---

## Milestone 2 - Command Parsing

### Step 11
- block
- unblock
- map

Test:
- t/11-command-parser-basic.t

### Step 12
- toggle
- include
- profile

Test:
- t/12-command-parser-advanced.t

### Step 13
- startup-delay
- send-startup

Test:
- t/13-startup-commands.t

### Step 14
- send

Test:
- t/14-runtime-commands.t

---

## Milestone 3 - Rule Engine

### Step 15
- Ordered rule storage

Test:
- t/15-rule-storage.t

### Step 16
- Blocking support

Test:
- t/16-blocking.t

### Step 17
- Unblocking support

Test:
- t/17-unblocking.t

### Step 18
- Mapping support

Test:
- t/18-mapping.t

### Step 19
- Evaluate all matching rules

Test:
- t/19-rule-order.t

### Step 20
- Last matching map wins

Test:
- t/20-last-map-wins.t

### Step 21
- Rules operate on original trigger

Test:
- t/21-original-trigger.t

---

## Milestone 4 - Profiles

### Step 22
- Load one profile

Test:
- t/22-profile-load.t

### Step 23
- Multiple profiles

Test:
- t/23-multiple-profiles.t

### Step 24
- Include support

Test:
- t/24-includes.t

### Step 25
- Include once semantics

Test:
- t/25-include-once.t

### Step 26
- Profile lookup paths

Test:
- t/26-profile-search-path.t

---

## Milestone 5 - PTY Engine

### Step 27
- Spawn child process

Test:
- t/27-spawn-child.t

### Step 28
- Forward stdin

Test:
- t/28-forward-input.t

### Step 29
- Forward stdout

Test:
- t/29-forward-output.t

### Step 30
- Self-pipe

Test:
- t/30-self-pipe.t

### Step 31
- SIGCHLD handling

Test:
- t/31-child-exit.t

### Step 32
- SIGWINCH handling

Test:
- t/32-resize.t

---

## Milestone 6 - Discovery

### Step 33
- Discovery mode

Test:
- t/33-discovery.t

---

## Milestone 7 - Startup Injection

### Step 34
- Startup delay

Test:
- t/34-startup-delay.t

### Step 35
- Startup actions

Test:
- t/35-startup-send.t

### Step 36
- Startup ordering

Test:
- t/36-startup-order.t

---

## Milestone 8 - Recording

### Step 37
- Recording engine

Test:
- t/37-record.t

### Step 38
- Timestamp recording

Test:
- t/38-record-timestamps.t

### Step 39
- Exit code recording

Test:
- t/39-record-exit-code.t

---

## Milestone 9 - Replay

### Step 40
- Replay engine

Test:
- t/40-replay.t

### Step 41
- Fast replay

Test:
- t/41-replay-fast.t

---

## Milestone 10 - Runtime Control

### Step 42
- Create socket

Test:
- t/42-socket-create.t

### Step 43
- Instance discovery

Test:
- t/43-instance-discovery.t

### Step 44
- Socket command parser

Test:
- t/44-socket-parser.t

### Step 45
- keyfilter_runtime profile

Test:
- t/45-runtime-profile.t

### Step 46
- Runtime block/unblock

Test:
- t/46-runtime-blocking.t

### Step 47
- Runtime mapping

Test:
- t/47-runtime-mapping.t

### Step 48
- Runtime send

Test:
- t/48-runtime-send.t

---

## Milestone 11 - Profile Toggling

### Step 49
- Enable profile

Test:
- t/49-enable-profile.t

### Step 50
- Disable profile

Test:
- t/50-disable-profile.t

### Step 51
- Restore original profile position

Test:
- t/51-toggle-order.t

### Step 52
- Rebuild active rule chain

Test:
- t/52-rebuild-chain.t

---

## Milestone 12 - keyfilterctl

### Step 53
- ls

Test:
- t/53-keyfilterctl-ls.t

### Step 54
- send

Test:
- t/54-keyfilterctl-send.t

### Step 55
- toggle

Test:
- t/55-keyfilterctl-toggle.t

### Step 56
- block
- unblock
- map

Test:
- t/56-keyfilterctl-rules.t
