# Installation

On a Mac with Apple silicon, or on 64-bit Intel or ARM Linux, this installs
the latest release:

```sh
curl -fsSL https://raw.githubusercontent.com/uji-labs/uji/main/install.sh | sh
```

It puts `uji` in `~/.local/bin`. On a machine without a uji config, it also
writes `~/.config/uji/init.lua`, which installs
[uji-plugins](https://github.com/uji-labs/uji-plugins) and turns on its
statusline, themes and websearch plugins. uji installs plugins with `git`.
Running the command again replaces uji with the latest release and leaves your
config alone.

| Variable | Effect |
|---|---|
| `UJI_INSTALL_DIR` | The folder `uji` goes in, instead of `~/.local/bin`. |
| `UJI_VERSION` | A release such as `v0.3.0` instead of the latest one. |

The Linux builds need glibc 2.34 or newer. On Alpine, other musl systems and
older releases such as Ubuntu 20.04, build uji with Cargo.

## With Homebrew

```sh
brew install uji-labs/uji/uji
```

Homebrew installs the same ready-made build as the script. `brew upgrade uji`
moves to a newer release.

## With Cargo

```sh
cargo install --git https://github.com/uji-labs/uji --locked uji
```

The build needs Rust 1.88 or newer, a C compiler and `make`. Cargo puts the
`uji` binary in `~/.cargo/bin`, and `uji --version` prints the version once
your shell finds it.

From a clone of the repository, run `cargo install --path crates/uji --locked`
in its top folder instead. Adding `--force` to either command replaces an
installed uji with a newer one.
