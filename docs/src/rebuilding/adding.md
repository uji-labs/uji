# Adding a module

uji loads every file in the `builtin/commands/`, `builtin/tools/`,
`builtin/providers/` and `api/` folders of `lua/uji/`, and each file registers
itself. A new file such as
`~/.config/uji/lua/uji/builtin/commands/hello.lua` adds a command without a
change to any other file, and the same works in a pack.

The files in `builtin/` use only the `uji.*` API, the same calls a plugin
makes.

| Folder | What a file there calls |
|---|---|
| `builtin/commands/` | [`uji.command.add(name, spec)`](../api/command.md#ujicommandaddname-spec). |
| `builtin/tools/` | [`uji.tool.add(name, spec)`](../api/tool.md#ujitooladdname-spec). |
| `builtin/providers/` | [`uji.provider.add(spec)`](../api/provider.md#ujiprovideraddspec), with an `api` made from a class in `builtin/apis/`, or from a class of its own. |
| `api/` | Nothing. It sets its own table on `uji`, such as `uji.session`. |

Files in a folder load in alphabetical order, so `/login` lists providers in
that order. [`uji.modules`](../runtime/system.md#ujimodulesnamespace) gives
the same list uji loads from.

`builtin/apis/` holds the [API classes](../api/apis.md). uji loads one the
first time something reads `uji.api.<name>`.
