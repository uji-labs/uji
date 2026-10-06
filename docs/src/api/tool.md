# uji.tool

uji ships four tools, `read_file`, `edit_file`, `write_file` and
`run_command`. The functions below add your own, switch tools off and on, and
decide which calls need your approval.

## uji.tool.add(name, spec)

Registers a tool the model can call, or replaces the tool with the same name.

| Field | Type | Required | Meaning |
|---|---|---|---|
| `description` | string | no | What the tool does. The model reads this to decide when to call it. |
| `parameters` | table | no | A JSON Schema for the arguments, written as a Lua table. |
| `run` | function | yes | Runs the call. See below. |
| `subject` | string or function | no | What policy rules match against, and what the transcript and approval question show. A function receives the arguments and returns a string. The default is the tool's name. |
| `parts` | function | no | Receives the arguments and returns a list of strings that policy rules check one by one, as `run_command` does with each command in a line. See [`uji.tool.policy`](#ujitoolpolicyrules). |
| `policy` | string | no | `"allow"`, `"ask"` or `"deny"`. Used when no policy rule matches. |
| `display.verb` | string | no | The transcript line, such as `"Read"`, which uji follows with the subject. |
| `display.question` | string | no | The title of the approval question. |
| `display.body` | function | no | Receives the arguments and returns the text under the approval question, such as a script the tool will run. The default is the subject. |

`run(args, ctx)` receives the decoded arguments and a context table. It returns
the result in one of three ways:
- It returns a string, which becomes the result at once.
- It returns nothing and calls `ctx.done(text)` later.
- It returns a function and calls `ctx.done(text)` later. uji calls that
  function to stop the work if you interrupt the turn.

A result may also be a table with `text` and `images`, in any of the three
ways. `images` is a list in the format the
[provider API request](apis.md#the-request) describes. The model gets
the images with the text, and `after_tool` handlers see only the text. An
image with no supported `media_type`, no `data` or more than 5 MB is left out,
and a note at the end of the text says so.

`ctx.progress(line)` shows a line under the running tool while it works.

### Tasks

`ctx.task(label, opts)` adds a row under the running tool for one piece of
its work, such as an agent it started, and returns a handle. Several tasks
show as a list, each with its state, how long it has run, its `detail` and,
while it runs, its latest `line`. Tasks with the same `group` show under a
heading with that name. When there are more than the theme's `limits.tasks`,
the running and failed ones show first and a line counts the rest.

| Option | Meaning | Default |
|---|---|---|
| `status` | `"queued"`, `"running"`, `"done"` or `"failed"`. | `"running"` |
| `group` | The heading the task shows under. | none |
| `line` | What it is doing now. | `""` |
| `detail` | Facts about it, such as the tokens it used. | `""` |

| Handle | Meaning |
|---|---|
| `task:update(fields)` | Changes any of `label`, `status`, `group`, `line` and `detail`. |
| `task:done(detail)` | Marks the task done, with an optional `detail`. |
| `task:fail(detail)` | Marks the task failed, with an optional `detail`. |

The clock starts when a task first leaves `queued` and stops when it is done
or failed. The rows go away when the tool returns its result. `uji run --json`
reports each change as a [`tasks` event](../getting-started/run.md#json-events).

```lua
uji.tool.add("check_all", {
  description = "Run the linters and the tests.",
  parameters = { type = "object", properties = {} },
  run = function(_, ctx)
    local lint = ctx.task("lint", { group = "Checks" })
    local test = ctx.task("tests", { group = "Checks", status = "queued" })
    uji.job.start({
      cmd = "just lint",
      on_exit = function(code)
        if code == 0 then lint:done() else lint:fail("exit " .. code) end
        test:update({ status = "running" })
        uji.job.start({
          cmd = "just test",
          on_stdout = function(line) test:update({ line = line }) end,
          on_exit = function(status)
            if status == 0 then test:done() else test:fail("exit " .. status) end
            ctx.done(code == 0 and status == 0 and "all checks pass" or "some checks failed")
          end,
        })
      end,
    })
  end,
})
```

Raises an error when `label` is not a string or `status` is not one of the
four states.

Raises an error when `run` is missing, `policy` is not one of the three
values, `subject` is neither a string nor a function, or `parts` is not a
function.

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

## uji.tool.policy(rules)

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

A tool with `parts` splits its subject before the rules see it. `run_command`
splits the command line into each command it runs: the commands joined by
`&&`, `||`, `;`, `|` or a newline, and those inside `( )`, `$( )` and
backticks. The call runs without asking only when every command is allowed,
so `git diff*` allows `git diff --stat` but not `git diff; rm -rf ~`. A `deny`
or `ask` rule that matches the whole line or any one command applies, and the
strictest answer wins. A line such as `cargo test 2>&1 | tail -20` needs a
rule for `tail` too.

Each call replaces the tools it names and keeps the others. A
[`before_tool`](events.md#before_tool) hook runs before the policy and
overrides it.

## uji.tool.confine(enabled)

With `true`, limits `read_file`, `edit_file` and `write_file` to the working
directory and the roots from `uji.tool.roots`. A `../` path or a symbolic link
cannot reach outside them. `run_command` is not limited. With `false`, lifts
the limit. Returns whether the limit is on, so calling it with no argument
reads the setting.

```lua
uji.tool.confine(true)
local confined = uji.tool.confine()
```

## uji.tool.roots(paths)

Replaces the directories the file tools may reach besides the working
directory, and returns the list. A path may start with `~/`. Calling it with no
argument returns the list without changing it.

```lua
uji.tool.roots({ "~/reference/other-project" })
local roots = uji.tool.roots()
```
