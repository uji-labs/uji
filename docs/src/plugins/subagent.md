# subagent

A `subagent` tool that hands tasks to agents. Each agent runs as a separate
uji process with [`uji run`](../getting-started/run.md), in a context of its
own, and only its final answer comes back.

```lua
require("subagent").setup({ concurrency = 2 })
```

| Option | Meaning | Default |
|---|---|---|
| `policy` | Whether starting agents asks first: `"allow"`, `"ask"` or `"deny"`. | `"allow"` |
| `scope` | Where agents come from when the model does not say: `"user"`, `"project"` or `"both"`. | `"user"` |
| `confirm_project` | Ask before running an agent from the project. | `true` |
| `max_tasks` | The most tasks one call may run at the same time. | `8` |
| `concurrency` | How many of them run at once. | `4` |
| `output` | Bytes of each answer kept when several run at once. | `51200` |

## Agents

An agent is a markdown file. The front matter describes it and the text below
is added to its system prompt.

```markdown
---
name: scout
description: Looks things up in the code and reports back with paths and lines
tools: read_file, run_command
model: anthropic/claude-haiku-4-5
effort: low
---
You are a scout. Find what you were asked for and report it briefly.
```

| Field | Meaning |
|---|---|
| `name` | The agent's name. The default is the file name. |
| `description` | Required. The model reads it to choose an agent. |
| `tools` | The tools the agent gets, separated by commas, with or without brackets. The default is every tool. |
| `model` | The model, written as `provider/model`. The default is yours. |
| `effort` | The reasoning effort. The default is yours. |

uji looks for agents in `agents/` in your config directory and in each pack.
With the `project` or `both` scope, it also reads `.uji/agents/` in the
session's directory, or in the nearest directory above it that has one. An
agent there replaces one of yours with the same name. A project's agents ask before they
run, unless `confirm_project` is `false`, because the repository controls
them.

## Commands

| Command | Does |
|---|---|
| `/agent <name> <task>` | Asks the model to run that agent on the task with the `subagent` tool. The agent's answer shows under the tool call, and the model replies with what it found. |
| `/agent` | Lists the agents. Picking one puts `/agent <name> ` in the input. |
| `/subagents` | Lists the agents that ran, newest first, with their state, time and tokens. Enter opens the agent's session in uji, and quitting it comes back. |

## The tool

| Arguments | Runs |
|---|---|
| `agent` and `task` | One task. |
| `tasks` | A list of `{ agent, task }` that run at the same time. |
| `chain` | A list of `{ agent, task }` that run in order. `{previous}` in a task is replaced by the answer of the step before, and a failed step stops the chain. |

Each item may also have `cwd`, the directory it works in. `scope` picks where
agents come from for this call.

An agent's tool calls run without asking, except the ones your policy denies.
Its conversation is saved as a session under yours, which
`uji resume --id <ID>` opens. Interrupting the turn stops every agent it
started. The agents themselves do not get the `subagent` tool.

## While agents run

Each agent shows as a [task](../api/tool.md#tasks) under the running tool:
waiting ones as queued, running ones with the tool they are calling, and
finished ones with the tokens they used. A line above them counts how many are
done. A failed step of a chain marks the steps after it as failed with
`skipped`.

## For other plugins

The [workflow](workflow.md) plugin starts its agents through these.

| Function | Does |
|---|---|
| `subagent.agents(scope)` | Returns the agents by name, from `"user"`, `"project"` or `"both"`. |
| `subagent.run(agent, task, opts)` | Runs one agent and waits. Returns its answer, or a string that starts with `error:`, and a table with `session`, `tokens`, `seconds` and `failed`. `opts.row` is a task to keep up to date, `opts.cwd` the directory, and `opts.stops` a list it adds a stop function to. |
| `subagent.row(ctx, label, opts)` | Adds a task under the running tool, as `ctx.task` does, and falls back to progress lines on an older uji. |
| `subagent.open(id)` | Opens a saved session in uji, and comes back when you quit it. |
| `subagent.tokens(count)` | Formats a token count, such as `12.3k tokens`. |
| `subagent.GENERAL` | The agent a task gets when it names none: every tool and no extra prompt. |
