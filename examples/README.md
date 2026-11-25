# Examples

Scripts that run directly from a checkout. Nothing has to be installed, they
need `perl` with the module `IO::Pty`, which keyfilter needs.

They do not need a terminal. They use a private home directory, so they do not
touch your files, and they remove what they make. Each one shows the command it
runs, the result, and checks the result. It prints `OK` and exits with 0 when it
works.

    ./examples/01-block.sh
    ./examples/run-all.sh

| script                    | shows                                     |
| ---                       | ---                                       |
| `01-block.sh`             | `--block`, `--unblock`                    |
| `02-map-text.sh`          | `--map` to text, the `F5` example         |
| `03-map-keys.sh`          | `--map` to other keys                     |
| `04-rule-order.sh`        | the order of the rules, the last map wins |
| `05-maps-do-not-chain.sh` | rules look at the typed key               |
| `06-sequences.sh`         | arrows, function keys, raw bytes          |
| `07-modifiers.sh`         | Alt, Shift, Control and combinations      |
| `08-lone-escape.sh`       | the Escape key                            |
| `09-profiles.sh`          | `--profile`, a name and a path            |
| `10-profile-order.sh`     | several profiles                          |
| `11-include.sh`           | `include` in a profile                    |
| `12-startup.sh`           | `--startup-delay`, `--send-startup`       |
| `13-record-replay.sh`     | `--record`, `--replay`, `--fast`          |
| `14-discover.sh`          | `--discover`                              |
| `15-ctl-ls-send.sh`       | `keyfilterctl ls` and `send`              |
| `16-ctl-toggle.sh`        | `keyfilterctl toggle`                     |
| `17-ctl-rules.sh`         | `keyfilterctl block`, `unblock`, `map`    |
| `18-ctl-more.sh`          | several instances, `--pid`, mistakes      |
| `19-help-and-errors.sh`   | `--help`, `--version`, messages           |

`profiles/` has profiles to start from: `common`, `vim`, `gaming`, `shell`.
Use them by path, or copy them to `~/.config/keyfilter` and use their names.
