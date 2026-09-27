# Configuration

uji reads `~/.config/uji`, or the directory in `UJI_CONFIG_DIR`.

```text
~/.config/uji/
  init.lua        runs first
  plugin/*.lua    runs after init.lua, sorted by file name
  lua/            modules for require()
```

`init.lua` replaces the default config. Start it with
`require("uji.defaults")` to keep the default screen.

```lua
require("uji.defaults")

uji.keymap.add("normal", "<C-p>", { command = "models" })
```

## Packs

[`uji.pack.add`](api/pack.md) installs a directory or git repository with its
own `lua/` and `plugin/`. `/sync` updates them.

```lua
uji.pack.add({
  "uji-labs/uji-plugins",
  { "someone/tool", tag = "v1.2" },
  { dir = "~/code/my-plugin" },
})
```

## Rebuilding uji

Everything uji does, from startup to the screen, is written in Lua in the
`uji` module tree, and you can replace any file in it. A file at
`lua/uji/<path>.lua` in your config directory or in a pack replaces the
built-in module `uji.<path>`. A module that is a folder, such as `uji.agent`,
lives in `lua/uji/agent/init.lua`.

A replacement is a whole file. uji loads yours instead of the built-in one, so
the easiest start is a copy of the original from the `lua/uji` folder of the
uji source.

For example, `~/.config/uji/lua/uji/prompt.lua`:

```lua
local M = {}

function M.system(env)
  return "You are a careful coding agent. Work in " .. env.directory .. "."
end

return M
```

### Where things live

| Path in `lua/uji/` | What it does |
|---|---|
| `boot.lua` | Starts uji. It reads the command line, opens the session and starts the screen. |
| `cli.lua` | The command line and `uji --help`. |
| `paths.lua` | Where the config, the data and the session database are. |
| `config.lua` | Loads your config and plugins, and runs `/reload`. |
| `packs.lua` | `uji.pack`, and finding modules in your config and packs. |
| `api/` | The `uji.*` functions in the [API reference](api/index.md). |
| `agent/`, `loop.lua` | Runs a turn, which sends the conversation, runs tools, compacts and picks a title. |
| `prompt.lua` | The system prompt. |
| `model.lua`, `catalog.lua`, `providers/` | Providers, models and choosing between them. |
| `wires/` | The request format of each provider API. |
| `tools/` | `read_file`, `edit_file`, `write_file` and `run_command`. |
| `tool.lua`, `system/` | Registering tools, the tool policy, file access and processes. |
| `commands/` | The built-in slash commands, one file each. |
| `store/` | Sessions and messages in the database. |
| `auth/` | API keys, the system keychain and subscription sign-in. |
| `ui/` | Draws the screen, with its layout, windows, input line, markdown, keys and theme. |
| `ui/views/` | The transcript, the input line, pickers, prompts and the approval question. |
| `defaults.lua` | The default screen and bindings that `require("uji.defaults")` loads. |
| `event.lua`, `task.lua`, `plugin.lua`, `registry.lua`, `class.lua` | Events, tasks, plugin ownership and the building blocks the rest is made of. |

The functions in [Runtime](api/runtime.md) are part of the uji program itself.
Everything built on them can be replaced.

### When a replacement takes effect

A replacement is used from the first file uji loads, `boot.lua` included. The
first time a pack that replaces modules is added, uji starts over once while it
starts up, so that the pack's files are used from the beginning. It remembers
those packs for later starts.

`/reload` and `/sync` start uji's Lua side again with your current files. The
conversation, what you are typing and the screen stay as they are. A turn in
progress has to finish, or be interrupted with Esc, before a reload. Processes
that plugins started, such as MCP servers, are started again.

### Replacing everything

Copy the whole `lua/uji` folder of the uji source into
`~/.config/uji/lua/uji`. Every module then comes from your copy. A file you
delete from your copy falls back to the built-in one.

To run a complete tree kept somewhere else, set `UJI_RUNTIME` to the directory
that contains its `uji` folder. uji then uses none of its built-in files, and
replacements in your config and packs still apply on top.

### If a replacement breaks uji

When uji cannot start, it prints the error and the file it came from. Fix or
remove that file, or start uji with `--config-dir` pointing at another
directory.
