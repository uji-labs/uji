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

# Unit + integration tests.
test:
    cargo nextest run --workspace

# Build the documentation site into docs/book.
docs:
    mdbook build docs

# Serve the documentation site and rebuild on change.
docs-serve:
    mdbook serve docs --open

# Everything CI would run.
check: fmt lint test
