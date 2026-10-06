# workflow

A `workflow` tool that runs a short Lua script to orchestrate many agents: it
starts them, runs them side by side or in stages, and returns what the script
returns. Each agent is a [subagent](subagent.md), a separate `uji run` with a
context of its own, so set that plugin up first.

```lua
require("subagent").setup({})
require("workflow").setup({ concurrency = 4 })
```

| Option | Meaning | Default |
|---|---|---|
| `policy` | Whether a workflow asks before it starts: `"allow"`, `"ask"` or `"deny"`. | `"ask"` |
| `scope` | Where named agents and saved workflows come from: `"user"`, `"project"` or `"both"`. | `"user"` |
| `concurrency` | How many agents of one workflow run at once. | `4` |
| `max_agents` | The most agents one workflow may start. | `25` |
| `output` | Bytes of the result kept in the tool's answer. | `51200` |

The approval question shows the whole script, because its agents run without
asking, except for calls your policy denies.

## Scripts

A script starts with a `meta` table. It must be plain values, with no
functions, because uji reads it before the script runs to name the workflow in
the transcript.

```lua
meta = {
  name = "review",
  description = "review each changed file, then check the findings",
  phases = { "Review", "Verify" },
}

phase("Review")
local found = pipeline(args.files, function(file)
  return agent("Review " .. file .. " for bugs. List each one on a line.", { label = file })
end)

phase("Verify")
local checked = agent("Check each finding and drop the false ones:\n" .. table.concat(found, "\n"))
return { findings = checked }
```

| Function | Does |
|---|---|
| `agent(prompt, opts)` | Starts an agent and waits for it. Returns its answer, or `nil` and the error. |
| `parallel(functions)` | Calls each function at once and waits for all. Returns their results in order, and a table of errors by index when any raised one. |
| `pipeline(items, stage, ...)` | Sends every item through the stages at once. An item moves to the next stage as soon as it clears one, and a `nil` skips the rest. A stage receives the value and the item's index. Returns the results like `parallel`. |
| `phase(name)` | Puts the agents that follow under `name`. |
| `log(...)` | Notes a line in the run, which `/workflows` shows. `print` does the same. |
| `args` | The `args` the model passed. |
| `json.encode`, `json.decode` | JSON, as in [uji.json](../api/json.md). |

`agent` takes these options.

| Option | Meaning |
|---|---|
| `label` | The name of its row. The default is the first line of the prompt. |
| `phase` | Its heading, instead of the current phase. |
| `agent` | A named [agent](subagent.md#agents). The default has every tool and no extra prompt. |
| `model`, `effort`, `tools` | Override the agent's model, effort and list of tools. |
| `cwd` | The directory it works in. |

Besides these, a script has `string`, `table`, `math`, `pairs`, `ipairs`,
`pcall`, `error` and the other plain Lua functions, but no files, processes or
modules. The value it returns becomes the result, as JSON unless it is a string.

## While it runs

Each agent is a [task](../api/tool.md#tasks) under the running tool, under the
heading of its phase. The line above shows the workflow, the phase it is in,
how many agents it started and the tokens they used. Interrupting the turn
stops every agent.

## Resuming

Every run gets an id, like `wf_5494b001`, which the tool's answer starts with.
Passing it as `resume` runs the script again, and each `agent` call with the
same prompt and options as before returns the earlier answer at once instead
of starting an agent. Changing one stage of a script therefore reruns only
that stage. uji keeps the last 20 runs until it exits.

## Saved workflows

A saved workflow is a `.lua` file in `workflows/` in your config directory or
a pack, named after the file. With the `project` or `both` scope, uji also
reads `.uji/workflows/` in the session's directory or the nearest directory
above it. The model sees the list with each `meta.description`, and runs one
with the tool's `name` instead of `script`.

## Commands

| Command | Does |
|---|---|
| `/workflows` | Lists this uji's runs with their state, agents, tokens and time. Picking one shows its details: each agent's state and the start of its answer, the log and the result, updated while it runs. From there you can also open an agent's session, put the script in the input to edit it, or stop a running workflow. |
| `/workflow <name> [args]` | Asks the model to run that saved workflow. |
| `/workflow` | Lists the saved workflows. Picking one puts `/workflow <name> ` in the input. |

## For other plugins

`workflow.runs()` returns the runs, newest first. Each has `id`, `meta`,
`status` (`running`, `completed`, `failed` or `stopped`), `phase`, `tokens`,
`log`, `agents`, and `result` or `error` once it ends. Each agent has `label`,
`phase`, `status`, `tokens`, `seconds`, `session` and `answer`.
`workflow.details(run)` gives the markdown `/workflows` shows. A status line
could use them to show the workflow in progress:

```lua
local workflow = require("workflow")
local ito = require("ito")

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.top_bar_trailing, function()
    local run = workflow.runs()[1]
    if run and run.status == "running" then
      return ito.Text(run.meta.name .. " · " .. #run.agents .. " agents")
    end
  end),
})
```
