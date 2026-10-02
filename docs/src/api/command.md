# uji.command

These functions manage the slash commands. The built-in ones, listed in
[Slash commands](../getting-started/commands.md#slash-commands), are added the
same way, so a plugin can replace or remove any of them.

## uji.command.add(name, spec)

Registers `/name`, or replaces the command with the same name, built-in or
not. `spec` is a function, or a table with these fields.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `handler` | function | yes | Runs the command. It receives the text typed after the name. |
| `desc` | string | no | The description in the suggestion list. |

Raises an error when `spec` is neither a function nor a table with a
`handler`.

```lua
uji.command.add("standup", {
  desc = "summarise yesterday's commits",
  handler = function(args)
    uji.session.submit("Summarise the commits since yesterday. " .. args)
  end,
})
```

This replaces `/help` with a notice that names every command:

```lua
uji.command.add("help", {
  desc = "list commands",
  handler = function()
    uji.notify(table.concat(uji.command.list(), "  "))
  end,
})
```

## uji.command.remove(name)

Removes a command and returns `true` if it existed.

```lua
uji.command.remove("standup")
```

## uji.command.list()

Returns the names of every command, built-in and added, in alphabetical
order.

```lua
local names = uji.command.list()
```
