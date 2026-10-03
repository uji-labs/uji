default:
    @just --list

# Install git hooks (one-time setup).
setup:
    git config core.hooksPath .githooks

# Format check (no writes).
fmt:
    cargo fmt --all --check

# Apply formatting.
fmt-apply:
    cargo fmt --all

# Clippy with warnings denied, plus structural ast-grep rules.
# `main.rs` is excluded from the print rules — printing is its job.
lint: scan
    cargo clippy --workspace --all-targets -- -D warnings

# Structural rules only.
scan:
    ast-grep scan crates/kernel/src crates/uji/src

# Lua formatting and lint (needs stylua and luacheck).
lua:
    stylua --check lua/uji crates/kernel/src crates/tests/lua
    luacheck lua/uji crates/kernel/src crates/tests/lua

# The Lua specs; filters pick tests by name, like `just test screen::`.
test *filters:
    cargo run -q -p uji-tests --bin uji-test -- -l crates/tests/lua/main.lua {{filters}}

# Build the documentation site into docs/book.
docs:
    mdbook build docs

# Serve the documentation site and rebuild on change.
docs-serve:
    mdbook serve docs --open

# Everything CI would run.
check: fmt lint lua test
