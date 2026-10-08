# uji.tool

uji ships six tools: `read_file`, `edit_file`, `write_file`, `run_command`,
and `job_output` and `stop_job` for [background jobs](jobs.md). The functions
below add your own, switch tools off and on, and decide which calls need your
approval.

## uji.tool.add(name, spec)

Registers a tool the model can call, or replaces the tool with the same name.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `description` | string | no | What the tool does. The model reads this to decide when to call it. |
| `parameters` | table | no | A JSON Schema for the arguments, written as a Lua table. |
| `run` | function | yes | Runs the call. See below. |
| `resolve` | function | no | Receives the arguments before the policy is checked and returns the ones to use from then on, or `nil` and an error message, which becomes the result. |
| `subject` | string or function | no | What policy rules match against, and what the transcript and approval question show. A function receives the arguments and returns a string. The default is the tool's name. |
| `policy` | string | no | `"allow"`, `"ask"` or `"deny"`. Used when no policy rule matches. |
| `path` | boolean | no | `true` when the subject is a file path, so policy rules match it the way they match the file tools. |
| `display.label` | string | no | The name the transcript shows for a call, such as `"Read"`, followed by the subject in brackets. The default is the tool's name. |
| `display.question` | string | no | The title of the approval question. |
| `display.preview` | function | no | Receives the arguments and returns the change the call would make, as [`uji.diff`](#ujidiffold-new-path) gives it. The approval question shows it. |

`run(args, ctx)` receives the decoded arguments and a context table. It returns
the result in one of three ways:
- It returns a string, which becomes the result at once.
- It returns nothing and calls `ctx.done(text)` later.
- It returns a function and calls `ctx.done(text)` later. uji calls that
  function to stop the work if you interrupt the turn.

A result may also be a table, in any of the three ways. Only `text` is
required.

| Field | Type | Meaning |
|---|---|---|
| `text` | string | The result the model reads. |
| `images` | list | Images in the format the [provider API request](apis.md#the-request) describes. The model gets them with the text. |
| `diff` | table | A change to a file, as [`uji.diff`](#ujidiffold-new-path) gives it. The transcript draws it in place of the text. |
| `summary` | string | A short line, such as `"Read 40 lines"`, that the transcript shows in place of the text until you click it. |

The model never sees `diff` or `summary`, and `after_tool` handlers see only
the text. An image with no supported `media_type`, no `data` or more than 5 MB
is left out, and a note at the end of the text says so.

`ctx.progress(line)` shows a line under the running tool while it works.

Raises an error when `run` is missing, `policy` is not one of the three
values, or `subject` is neither a string nor a function.

```lua
uji.tool.add("branch", {
  description = "Name of the current git branch.",
  parameters = { type = "object", properties = {} },
  policy = "allow",
  display = { label = "Branch", question = "Read the current branch?" },
  run = function()
    return io.popen("git branch --show-current"):read("*l")
  end,
})
```

## uji.tool.display(name, opts)

Describes a tool that uji does not run itself, such as one that a provider's
[own loop](provider.md) runs, so the transcript and the approval question can
name its calls. The model is never offered it. `opts` takes `label`, `subject`,
`question` and `preview`, which mean the same as `display.label`, `subject`,
`display.question` and `display.preview` in `uji.tool.add`.

```lua
uji.tool.display("Edit", {
  label = "Update",
  subject = function(args)
    return args.file_path
  end,
})
```

## uji.tool.remove(name)

Removes a tool and returns `true` if it existed.

```lua
uji.tool.remove("write_file")
```

## uji.tool.list()

Returns the names of every registered tool.

```lua
for _, name in ipairs(uji.tool.list()) do
  uji.notify(name)
end
```

## uji.tool.disable(names)

Turns tools off. The model still sees them, and uji denies any call to them.
Plan mode uses this to take away the editing tools.

```lua
uji.tool.disable({ "edit_file", "write_file" })
```

## uji.tool.enable(names)

Turns tools back on after `uji.tool.disable`.

```lua
uji.tool.enable({ "edit_file", "write_file" })
```

## uji.tool.policy(rules, opts)

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
line for `run_command`, the job's name for `job_output` and `stop_job`, and the
`subject` of a tool you add. A job's name follows the theme's `text.job`, such
as `job 3`. A rule is an exact string, a glob when it contains `*`, `?` or `[`,
or a regular expression between slashes. For the file tools, a rule also
matches the file's full path, and a rule that starts with `~/` starts at your
home folder. A rule can also be a table with `pattern` and `message`, and the
model reads `message` when that rule refuses a call.

uji checks `deny` rules first, then `allow`, then `ask`, and uses the first
match. With no match, it uses the tool's `default`, then the top-level
`default`, then the policy the tool declares, then `ask`. `read_file`,
`job_output` and `stop_job` declare `allow` and the other built-in tools
declare `ask`. A top-level `default = "allow"` runs every tool without asking,
except the calls a rule matches.

```lua
uji.tool.policy({
  default = "allow",
  run_command = { deny = { "/^\\s*rm\\s+-rf/" } },
})
```

Rules may name a tool uji does not register, such as a tool of a provider
that runs [its own loop](provider.md#your-own-loop). They match the subject
that loop passes to `agent:approve`.

Each call replaces the tools it names and keeps the others. With
`opts.name`, the rules go in a separate set under that name, which calls
without it, or with another name, leave alone. uji checks the `deny` rules of
every set first, and when sets give different defaults, the strictest wins.

```lua
uji.tool.policy({
  edit_file = {
    deny = { { pattern = "~/reference/**", message = "~/reference is read-only" } },
  },
}, { name = "reference" })
```

A [`before_tool`](events.md#before_tool) hook runs before the policy and
overrides it.

## uji.diff(old, new, path)

Compares two texts line by line and returns the change as a table, for a
result's `diff` or a `display.preview`. `path` names the file, and its
extension, or its name when it has none, picks the colours for the code. The
table has `path` and `changes`.
Each change is a list of lines: the lines that changed and, around them, up to
the theme's `limits.diff_context` lines that did not. A line has:

| Field | Meaning |
|---|---|
| `kind` | `"context"`, `"removed"` or `"added"`. |
| `old`, `new` | The line's number before and after the change. A removed line has no `new`, and an added line has no `old`. |
| `parts` | The line's text in pieces, each `{ text, changed }`, where `changed` marks the words that differ. |

Raises an error when `old` or `new` is not a string.

```lua
uji.tool.add("upcase", {
  description = "Uppercase a file.",
  parameters = { type = "object", properties = { path = { type = "string" } } },
  run = function(args)
    local before = uji.fs.read(args.path)
    local after = before:upper()
    uji.fs.write(args.path, after)
    return { text = "uppercased " .. args.path, diff = uji.diff(before, after, args.path) }
  end,
})
```
