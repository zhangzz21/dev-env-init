# zsh-bin

The Zsh that `init.sh` installs, from [zsh-bin](https://github.com/romkatv/zsh-bin)
v6.1.1. Two files are needed here:

```
install                      https://raw.githubusercontent.com/romkatv/zsh-bin/v6.1.1/install
zsh-5.8-linux-x86_64.tar.gz  https://github.com/romkatv/zsh-bin/releases/download/v6.1.1/zsh-5.8-linux-x86_64.tar.gz
```

The archive's expected hashes, as published in that `install` script:

```
md5:e04d16b71e4a9dbcab6d39c78b64124b
sha256:6df668fb6e9a12874e0d80518d582f2e99e512d4a4532fa73d938360aaddc838
```

`init.sh` installs it offline with `install -q -e no -d <work_dir>/.bin/.zsh -f <archive>`
and symlinks `<work_dir>/.bin/zsh` at the result.

## Why this build

The nodes have no Zsh of their own, so it has to travel with the repo, and a
plain build cannot: Zsh hard-codes the paths to its own autoloadable functions
and to its loadable modules at compile time. This one is built to be relocated —
the install script patches those paths to wherever you put it — it is statically
linked (no libc, ncurses or terminfo needed from the node), it carries its own
terminfo database as a fallback, and every standard module is linked into the
binary.

It replaces the static Zsh 5.9 that used to be `tools-bin/zsh`. That one was a
Nix musl build whose `fpath` and `module_path` pointed into
`/nix/store/…-zsh-static-x86_64-unknown-linux-musl-5.9/`, a directory that only
exists on the machine that built it, so on our nodes every autoload failed
(`compinit`, `add-zsh-hook`, `is-at-least`, `colors`, `compdef` …). Being
statically linked it also could not load any module from disk, and only 11 of
them were linked in: `zsh/system`, `zsh/files`, `zsh/mathfunc`, `zsh/stat`,
`zsh/regex` and `zsh/net/socket` were missing, and powerlevel10k's git status
needs the first two (`gitstatus.plugin.zsh` does
`zmodload zsh/datetime zsh/system || return`).

The trade-off is the version: zsh-bin is Zsh 5.8, from 2020. Nothing in this
setup needs anything newer.
