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
