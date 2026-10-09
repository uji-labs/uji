#!/bin/sh
set -eu

dir="${UJI_INSTALL_DIR:-$HOME/.local/bin}"
version="${UJI_VERSION:-latest}"
config="${UJI_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/uji}"
cargo="Build it with Cargo: https://docs.uji.sh/getting-started/install.html"

fail() {
    echo "uji: $*" >&2
    exit 1
}

verify() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c "$1"
    else
        shasum -a 256 -c "$1"
    fi
}

case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) target=aarch64-apple-darwin ;;
    Linux/x86_64) target=x86_64-unknown-linux-gnu ;;
    Linux/aarch64 | Linux/arm64) target=aarch64-unknown-linux-gnu ;;
    *) fail "there is no ready-made uji for $(uname -s) $(uname -m). $cargo" ;;
esac

archive="uji-$target.tar.gz"
if [ "$version" = latest ]; then
    url="https://github.com/uji-labs/uji/releases/latest/download/$archive"
else
    url="https://github.com/uji-labs/uji/releases/download/$version/$archive"
fi

mkdir -p "$dir"
work="$(mktemp -d "$dir/.uji.XXXXXX")"
trap 'rm -rf "$work"' EXIT

echo "Downloading uji for $target"
curl -fsSL "$url" -o "$work/$archive" || fail "could not download $url"
curl -fsSL "$url.sha256" -o "$work/$archive.sha256" || fail "could not download $url.sha256"
(cd "$work" && verify "$archive.sha256") >/dev/null 2>&1 || fail "$archive does not match its checksum"

tar -xzf "$work/$archive" -C "$work"
installed="$("$work/uji" --version 2>/dev/null)" || fail "uji does not run here. It needs macOS 11, or glibc 2.34 or newer. $cargo"
mv "$work/uji" "$dir/uji"
echo "Installed $installed in $dir"

if [ ! -e "$config/init.lua" ]; then
    mkdir -p "$config"
    cat >"$config/init.lua" <<'EOF'
uji.pack.add({ "uji-labs/uji-plugins" })

require("statusline").setup({})
require("themes").setup({})
require("websearch").setup({})
EOF
    echo "Wrote $config/init.lua"
fi

command -v git >/dev/null 2>&1 || echo "Install git, which uji uses to install plugins."

case ":$PATH:" in
    *":$dir:"*) ;;
    *) echo "Add $dir to your PATH." ;;
esac

echo "Run uji in a project and type /login to sign in."
