lua_paths := "lua/uji crates/kernel/src crates/tests/lua bench"

default:
    @just --list

# Install git hooks (one-time setup).
setup:
    git config core.hooksPath .githooks

# Format check for Rust and Lua (no writes).
fmt:
    cargo fmt --all --check
    stylua --check {{lua_paths}}

# Apply Rust and Lua formatting.
fmt-apply:
    cargo fmt --all
    stylua {{lua_paths}}

# Clippy with warnings denied, plus structural ast-grep rules.
# `main.rs` is excluded from the print rules — printing is its job.
lint: scan
    cargo clippy --workspace --all-targets -- -D warnings

# Structural rules only.
scan:
    ast-grep scan crates/kernel/src crates/uji/src lua/uji

# Lua lint (needs luacheck and selene).
lua:
    luacheck {{lua_paths}}
    selene lua/uji crates/kernel/src bench
    selene --config .config/selene/tests.toml crates/tests/lua

# The Lua specs; filters pick tests by name, like `just test screen::`.
test *filters:
    cargo run --release -q -p uji-tests --bin uji-test -- -l crates/tests/lua/main.lua {{filters}}

# Benchmarks of what users do, like typing and streaming; filters pick them by name, like `just bench typing`.
bench *filters:
    cargo run --release -q -p uji-tests --bin uji-test -- -l bench/main.lua bench {{filters}}

# Pathological inputs that must not crash or stall uji; filters pick them by name.
torture *filters:
    cargo run --release -q -p uji-tests --bin uji-test -- -l bench/main.lua torture {{filters}}

# Build the documentation site into docs/book.
docs:
    mdbook build docs

# Serve the documentation site and rebuild on change.
docs-serve:
    mdbook serve docs --open

# Everything CI would run.
check: fmt lint lua test
