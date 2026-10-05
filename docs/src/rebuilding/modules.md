# Where things live

The tree has three parts. `core/` is the engine. `api/` is the `uji.*` table
that plugins use. `builtin/` is what uji ships on top of the engine, written as
plugins are: the providers, request formats, tools, commands and the default
screen.

| Path in `lua/uji/` | What it does |
|---|---|
| `boot.lua` | Starts uji. It reads the command line, opens the session and starts the screen. |
| `api/` | The `uji.*` functions in the [API reference](../api/index.md). |
| `core/cli.lua` | The command line and `uji --help`. |
| `core/run.lua` | `uji run`, one prompt without the screen. |
| `core/paths.lua` | Where the config, the data and the session database are. |
| `core/config.lua` | Loads your config and plugins, and runs `/reload`. |
| `core/packs.lua` | `uji.pack`, and finding modules in your config and packs. |
| `core/agent/`, `core/loop.lua` | Runs a turn, which sends the conversation, runs tools, compacts and picks a title. |
| `core/prompt.lua` | The system prompt. |
| `core/model.lua`, `core/catalog.lua` | Providers, models and choosing between them. |
| `core/tool.lua`, `core/system/` | Registering tools, the tool policy, file access and processes. |
| `core/command.lua` | Registering slash commands. |
| `core/store/` | Sessions and messages in the database. |
| `core/auth/` | API keys, `auth.toml`, the optional keychain and subscription sign-in. |
| `core/ui/` | Draws the screen, with its parts, input line, markdown, keys and theme engine. |
| `core/ui/views/` | The transcript, the input line, pickers, prompts and the approval question. |
| `core/images.lua` | Attaching images from files, pasted paths and the clipboard. |
| `core/event.lua`, `core/task.lua`, `core/plugin.lua`, `core/registry.lua`, `core/class.lua` | Events, tasks, plugin ownership and the building blocks the rest is made of. |
| `builtin/providers/` | The providers `/login` lists, each with the API it speaks and its own changes to it. |
| `builtin/apis/` | The Chat Completions, Responses, Anthropic and Gemini API classes, and the streaming they share. |
| `builtin/tools/` | `read_file`, `edit_file`, `write_file` and `run_command`. |
| `builtin/commands/` | The built-in slash commands, one file each. |
| `builtin/defaults.lua` | The default tool policy and bindings that `require("uji.builtin.defaults")` loads. |
| `themes/default.lua` | The default theme, and the function other themes build on. |
| `sys/` | `require("uji.sys")`, a table with a field for each [Runtime](../runtime/index.md) module, such as `fs` or `json`. A field loads its module, `uji.sys.fs` or `uji.sys.json`, the first time it is read. `uji.*` falls back to the same fields for anything `api/` does not define. |

The Runtime modules are built into the uji program, and a module with the same
name replaces any of them, as
[Native modules](../runtime/native.md#replacing-a-built-in-module) describes.
Everything built on them, `sys/` included, can be replaced too.
