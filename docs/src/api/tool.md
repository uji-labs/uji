# uji.tool

uji ships four tools: `read_file`, `edit_file`, `write_file` and
`run_command`. `uji.tool` adds your own, turns tools off, and sets the rules that
decide which calls need your approval.

### uji.tool.add(name, spec)

Registers a tool the model can call, or replaces the tool with the same name.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `description` | string | no | What the tool does. The model reads this to decide when to call it. |
| `parameters` | table | no | A JSON Schema for the arguments, written as a Lua table. |
| `run` | function | yes | Runs the call. See below. |
| `subject` | string or function | no | What policy rules match against, and what the transcript and approval question show. A function receives the arguments and returns a string. The default is the tool's name. |
| `policy` | string | no | `"allow"`, `"ask"` or `"deny"`. Used when no policy rule matches. |
| `display.verb` | string | no | The transcript line, such as `"Read"`, which uji follows with the subject. |
| `display.question` | string | no | The title of the approval question. |

`run(args, ctx)` receives the decoded arguments and a context table. It returns
the result in one of three ways:
- It returns a string, which becomes the result at once.
- It returns nothing and calls `ctx.done(text)` later.
- It returns a function and calls `ctx.done(text)` later. uji calls that
  function to stop the work if you interrupt the turn.

`ctx.progress(line)` shows a line under the running tool while it works.

Raises an error when `run` is missing, `policy` is not one of the three
values, or `subject` is neither a string nor a function.

```lua
uji.tool.add("branch", {
  description = "Name of the current git branch.",
  parameters = { type = "object", properties = {} },
  policy = "allow",
  display = { verb = "Checked the branch", question = "Read the current branch?" },
  run = function()
    return io.popen("git branch --show-current"):read("*l")
  end,
})
```

### uji.tool.remove(name)

Removes a tool and returns `true` if it existed.

```lua
uji.tool.remove("write_file")
```

### uji.tool.list()

Returns the names of every registered tool.

```lua
for _, name in ipairs(uji.tool.list()) do
  uji.notify(name)
end
```

### uji.tool.disable(names)

Turns tools off. The model still sees them, and uji denies any call to them.
Plan mode uses this to take away the editing tools.

```lua
uji.tool.disable({ "edit_file", "write_file" })
```

### uji.tool.enable(names)

Turns tools back on after `uji.tool.disable`.

```lua
uji.tool.enable({ "edit_file", "write_file" })
```

### uji.tool.policy(rules)

Sets which tool calls run without asking, which ask first, and which uji
refuses. `rules` maps a tool name to a table with `allow`, `ask` and `deny`
lists and an optional `default`. A top-level `default` applies to every tool.

```lua
uji.tool.policy({
  default = "ask",
  run_command = {
    allow = { "git status", "git diff *", "cargo test*" },
    deny = { "/^rm\\s+-rf/" },
  },
})
```

Each rule matches the tool's subject: the path for the file tools, the command
line for `run_command`, and the `subject` of a tool you add. A rule is an
exact string, a glob when it contains `*`, `?` or `[`, or a regular expression
between slashes.

uji checks `deny` rules first, then `allow`, then `ask`, and uses the first
match. With no match, it uses the tool's `default`, then the policy the tool
declares, then the top-level `default`, then `ask`. `read_file` declares
`allow` and the other built-in tools declare `ask`.

Each call replaces the tools it names and keeps the others. A
[`before_tool`](events.md#before_tool) hook runs before the policy and
overrides it.

### uji.tool.confine(enabled)

With `true`, limits `read_file`, `edit_file` and `write_file` to the working
directory and the roots from `uji.tool.roots`. A `../` path or a symbolic link
cannot reach outside them. `run_command` is not limited. With `false`, lifts
the limit. Returns whether the limit is on, so calling it with no argument
reads the setting.

```lua
uji.tool.confine(true)
local confined = uji.tool.confine()
```

### uji.tool.roots(paths)

Replaces the directories the file tools may reach besides the working
directory, and returns the list. A path may start with `~/`. Calling it with no
argument returns the list without changing it.

```lua
uji.tool.roots({ "~/reference/other-project" })
local roots = uji.tool.roots()
```
