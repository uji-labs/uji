# Native modules

A native module is a shared library that Lua loads with `require`. uji looks
for it in `native/` in the [config directory](../configuration/files.md) and
in every [pack](../configuration/packs.md). `require("name")` finds
`name.dylib` on macOS and `name.so` on Linux. A dotted name looks in folders,
so `require("tools.fast")` finds `native/tools/fast.dylib`. Native modules
work on macOS and Linux only.

The library is a Lua C module for LuaJIT. It exports a function named
`luaopen_` followed by the module name, with each dot written as an
underscore, and whatever that function returns is the module. A module can be
written in any language that can export such a function, such as C, Zig or
Rust.

The library does not link LuaJIT itself. It uses the LuaJIT inside uji, which
on macOS needs the linker flag `-undefined dynamic_lookup`.

A native function runs while every task waits, so a slow one holds up the
screen until it returns.

## Loading

uji loads a library the first time `require` asks for it, and keeps it until
uji restarts. After you rebuild a library, `/reload` loads the new
one.

## Errors

An error raised inside a native function, such as an argument of the wrong
type, reaches Lua like any other error. `pcall` catches it, and
`uji.message(err)` gives its text without a stack trace.

```lua
local ok, err = pcall(require("loadavg").get)
if not ok then
    uji.notify(uji.message(err))
end
```

## Writing one in C

The module needs LuaJIT's headers, for example from `brew install luajit` or a
`libluajit-5.1-dev` package. This one gives a status segment the system's load
average.

```c
#include <stdlib.h>
#include <lua.h>
#include <lauxlib.h>

static int get(lua_State *L) {
    double average;
    if (getloadavg(&average, 1) != 1) {
        return luaL_error(L, "the load average is not available");
    }
    lua_pushnumber(L, average);
    return 1;
}

int luaopen_loadavg(lua_State *L) {
    lua_newtable(L);
    lua_pushcfunction(L, get);
    lua_setfield(L, -2, "get");
    return 1;
}
```

On macOS:

```sh
cc -shared -undefined dynamic_lookup -I"$(brew --prefix luajit)/include/luajit-2.1" -o loadavg.dylib loadavg.c
mkdir -p ~/.config/uji/native && cp loadavg.dylib ~/.config/uji/native/
```

On Linux:

```sh
cc -shared -fPIC -I/usr/include/luajit-2.1 -o loadavg.so loadavg.c
mkdir -p ~/.config/uji/native && cp loadavg.so ~/.config/uji/native/
```

```lua
uji.status.add("load", function()
  return { text = string.format("load %.2f", require("loadavg").get()), color = "gray" }
end)
```

## Writing one in Rust

A Rust module is a crate with `crate-type = ["cdylib"]` that depends on mlua
with the `luajit52` and `module` features. `#[mlua::lua_module]` on a function
that takes `&Lua` and returns the module exports it as `luaopen_` followed by
the function's name, and `#[mlua::lua_module(name = "tools_fast")]` exports it
under the name you give instead. This one gives the number of CPU cores, which
sizes how many subagents run at once.

`Cargo.toml`:

```toml
[package]
name = "cpus"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
mlua = { version = "0.12", features = ["luajit52", "module"] }
```

`build.rs`, which passes the macOS linker flag:

```rust
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!("cargo::rustc-cdylib-link-arg=-undefined");
        println!("cargo::rustc-cdylib-link-arg=dynamic_lookup");
    }
}
```

`src/lib.rs`:

```rust
use mlua::prelude::*;

#[mlua::lua_module]
fn cpus(lua: &Lua) -> LuaResult<LuaTable> {
    let module = lua.create_table()?;
    module.set(
        "count",
        lua.create_function(|_, ()| {
            Ok(std::thread::available_parallelism().map_or(1, std::num::NonZero::get))
        })?,
    )?;
    Ok(module)
}
```

Build it and copy the library under the module's name, `cpus.dylib` on macOS
or `cpus.so` on Linux:

```sh
cargo build --release
cp target/release/libcpus.dylib ~/.config/uji/native/cpus.dylib
```

```lua
require("subagent").setup({ concurrency = require("cpus").count() })
```

## Replacing a built-in module

Every part of the [Runtime](index.md) is a module named `uji.sys.` followed by
its name. `require` looks in these places, in order, and uses the first module
it finds:

1. Lua in your config and packs, such as `~/.config/uji/lua/uji/sys/fs.lua`.
2. The Lua that comes with uji.
3. Native modules in `native/` in your config and packs, such as
   `native/uji/sys/fs.dylib`, which exports `luaopen_uji_sys_fs`.
4. The modules built into uji.

A module you provide under one of these names replaces the built-in one, and
everything in uji that uses it uses yours. The other modules stay built in.

| Module | What it is |
|---|---|
| `uji.sys.task` | `spawn`, `race`, `timeout` and `on_error`, in [Tasks](tasks.md). |
| `uji.sys.sleep` | The `sleep` function, in [Tasks](tasks.md). |
| `uji.sys.promise` | The `promise` function, in [Tasks](tasks.md). |
| `uji.sys.fs` | Files and folders, in [uji.fs](../api/fs.md). |
| `uji.sys.net` | Requests and the local server, in [Network](network.md). |
| `uji.sys.proc` | Processes, in [Processes](processes.md). |
| `uji.sys.db` | SQLite databases, in [Storage](storage.md). |
| `uji.sys.os` | The system and restarting, in [System](system.md). |
| `uji.sys.keychain` | The keychain, in [System](system.md). |
| `uji.sys.clipboard` | The clipboard, in [System](system.md). |
| `uji.sys.modules` | The `modules` function, in [System](system.md). |
| `uji.sys.message` | The `message` function, in [System](system.md). |
| `uji.sys.json` | JSON, in [uji.json](../api/json.md). |
| `uji.sys.toml` | TOML, in [Encoding](encoding.md). |
| `uji.sys.base64` | Base64, in [Encoding](encoding.md). |
| `uji.sys.sha256` | The `sha256` function, in [Encoding](encoding.md). |
| `uji.sys.random` | The `random` function, in [Encoding](encoding.md). |
| `uji.sys.regex` | The `regex` function, in [Text](text.md). |
| `uji.sys.glob` | The `glob` function, in [Text](text.md). |
| `uji.sys.fuzzy` | The `fuzzy` function, in [Text](text.md). |
| `uji.sys.width` | The `width` function, in [Text](text.md). |
| `uji.sys.lossy` | The `lossy` function, in [Text](text.md). |
| `uji.sys.markdown` | The `markdown` function, in [Text](text.md). |
| `uji.sys.image` | Image fitting, in [Images](images.md). |
| `uji.sys.tty` | The screen and its input, in [Terminal](terminal.md). |

This file at `~/.config/uji/lua/uji/sys/width.lua` counts every character as
one column. `/reload` puts it to use.

```lua
return function(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end
```
