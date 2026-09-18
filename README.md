# uji

uji is a terminal coding agent for people who configure their tools in Lua, the way Neovim users do. The core is one Rust binary with six tools. MCP, plan mode, skills, web search, the fuzzy finder and the status line are all Lua plugins, and the MCP client is 612 lines.

```lua
-- ~/.config/uji/init.lua
uji.pack.add({ "uji-labs/uji-plugins" })
require("statusline").setup({})
require("planmode").setup({})

uji.tool.policy = {
  run_command = {
    allow = { "git status", "cargo *" },
    deny  = { "/^rm\\s+-rf/" },
  },
}

uji.keymap.set("normal", "<A-e>", { command = "effort" })
```

uji is two weeks old. The Lua API still changes between commits, and there are no releases yet.

## Install

You need Rust 1.88 or newer and the SQLite development library. macOS ships SQLite. On Debian or Ubuntu, install `libsqlite3-dev`.

```sh
git clone git@github.com:uji-labs/uji.git
cd uji
cargo install --path crates/uji
```

## First run

```sh
uji
```

Type `/login` and pick a provider. You can sign in with a Claude or ChatGPT subscription through the browser, or paste an API key. uji stores credentials in the OS keychain. It also reads the usual environment variables, such as `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `GEMINI_API_KEY`.

`/models` picks the model. uji ships entries for 22 providers, including Ollama and LM Studio for local models and OpenRouter for everything else. `uji.provider.add` registers any other endpoint that speaks the OpenAI, Anthropic or Gemini wire format.

Then talk to it. A line starting with `!` runs in your shell instead of going to the model. Alt+Enter or Ctrl+J inserts a newline. The input line uses readline bindings, so Ctrl+A, Ctrl+W, Ctrl+Y and the rest work as they do in bash.

| Command | What it does |
|---|---|
| `/login` | configure provider and auth |
| `/models` | pick the default model |
| `/effort` | how hard the model should think |
| `/thinking` | show or hide model reasoning |
| `/compact` | summarise earlier messages to free context |
| `/sync` | update installed packs |
| `/reload` | redraw the UI from config |
| `/help` | list commands, including the ones plugins added |
| `/quit` | leave uji |

Sessions live in SQLite at `~/.local/share/uji/uji.db`.

```sh
uji                  # new session
uji resume           # pick up the latest session
uji resume --id ID   # pick up a specific one
uji list             # browse sessions
uji delete ID
```

## What the core does

The model gets six tools: `read_file`, `edit_file`, `write_file`, `list_dir`, `grep` and `run_command`.

Reads run without asking. Writes and shell commands ask first. You change that with `uji.tool.policy`, which takes `allow`, `ask` and `deny` lists per tool. An entry is an exact string, a glob, or a `/regex/`, and uji matches it against the file path or the command line. Deny beats allow, and allow beats ask.

`uji.tool.confine()` restricts the file tools to the working directory plus whatever you pass to `uji.tool.roots`. The check opens directories through cap-std, so a `../` path or a symlink can't climb out. It covers the file tools only. `run_command` is an ordinary shell, so gate it with policy or run uji in a container.

You can type while the model works. uji queues the message and hands it over at the next step, so you can steer a turn without killing it. Esc on an empty input line interrupts.

When the context window fills, uji summarises the older messages and keeps going. `/compact` does it on demand.

## Configure it

uji reads `~/.config/uji/init.lua` at startup, then every `.lua` file in `~/.config/uji/plugin/`. `require` resolves modules from `~/.config/uji/lua/` and from each installed pack.

Your `init.lua` replaces the built-in config. It doesn't extend it. The screen layout is part of that config, so start by copying [`crates/agent/config/default.lua`](crates/agent/config/default.lua). It is 49 lines and it opens the message, input and modal windows that you see by default.

### Events

`uji.on(event, handler)` subscribes to an event. The `tool_call` event fires before each tool runs, and the handler can veto it.

```lua
uji.on("tool_call", function(event)
  if event.name == "run_command" and event.arguments.command:match("^git push") then
    return { deny = "Pushing is my job." }
  end
end, { priority = 10 })
```

Return `{ deny = reason }` and the model sees the reason. Return `{ ask = true }` to force the approval prompt. Return `nil` to let the next handler or the policy table decide.

The other events are `session_created`, `session_resumed`, `session_titled`, `message_submitted`, `message_appended`, `render_message`, `queue_changed`, `shell_started`, `shell_finished`, `tool_started`, `tool_finished`, `turn_finished`, `model_changed`, `compacted`, `status_changed`, `error`, `tick` and `quit`.

### Tools

```lua
uji.tool.register("branch", {
  description = "Name of the current git branch.",
  parameters = { type = "object", properties = {} },
  run = function()
    return io.popen("git branch --show-current"):read("*l")
  end,
})
```

For a tool that waits on a process or the network, set `defer = true`. `run` then receives `(args, done)`, and the turn resumes when you call `done(text)`. `uji.job.start` runs a process in the background and streams its stdout, stderr and exit code to Lua callbacks. `uji.job.send` writes to its stdin. The MCP plugin is built from deferred tools, jobs and `uji.json`, and nothing in the Rust code mentions MCP.

### Commands, keys and the screen

```lua
uji.command("standup", {
  desc = "summarise yesterday's commits",
  handler = function(args)
    uji.notify("not written yet")
  end,
})

uji.keymap.set("normal", "<C-s>", { command = "standup" })
```

`uji.ui.open_win` opens a window and `uji.ui.set_lines` draws styled text into it. `uji.ui.select`, `uji.ui.pick` and `uji.ui.prompt` open modals. `uji.status.add` adds a segment to the footer. `uji.agent.context` adds text to the system prompt. `uji.session` reads the transcript and the token counts.

### Packs

```lua
uji.pack.add({
  "uji-labs/uji-plugins",                      -- GitHub shorthand
  { "user/repo", tag = "v1.2.0" },             -- pin a tag, branch or commit
  { dir = "~/Projects/my-plugin" },            -- a working copy
})
```

uji clones packs into `~/.local/share/uji/site/` and records each commit in `uji-lock.json`, so a second machine gets the same revisions. `/sync` pulls updates.

## What's not in the core

| Plugin | What you get |
|---|---|
| `mcp` | MCP client over stdio and HTTP, with OAuth |
| `planmode` | read-only exploration, then `/approve` to execute |
| `skills` | [Agent Skills](https://agentskills.io/specification) folders |
| `websearch` | a `web_search` tool |
| `telescope` | fuzzy finder for files, branches, history and grep |
| `statusline` | the footer |
| `readonly` | lets the agent read sibling repos without editing them |

They live in [uji-plugins](https://github.com/uji-labs/uji-plugins). Each one uses the same `uji.*` functions your `init.lua` can call. If you dislike how plan mode works, the file is 154 lines. Fork it.

[pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) takes the same position with TypeScript extensions, and its README argues the case well. uji differs in three ways. It is one binary with no Node runtime. Permission prompts and file confinement are in the core, because a plugin that forgets to load shouldn't leave the shell open. The screen layout is config too.

## Layout

| Crate | Job |
|---|---|
| `crates/agent` | providers, streaming, tools, policy, sessions, OAuth. No UI. |
| `crates/ui` | ratatui front end, input line, keymap, pickers |
| `crates/uji` | event loop, the `uji.*` Lua API, packs, the binary |
| `crates/tests` | integration tests, including full-screen render tests |

The runtime is single-threaded on a calloop event loop, with `Rc` and `RefCell` throughout. Lua callbacks never race each other. Network and process work runs on a tokio pool and reports back through channels.

## Development

```sh
just setup   # install the pre-commit hook
just check   # fmt, clippy, ast-grep rules, tests
```

You need [just](https://github.com/casey/just) and [ast-grep](https://ast-grep.github.io). The lint settings are strict. `unsafe` is forbidden, and clippy denies `unwrap`, `expect`, `panic!`, `todo!` and `dbg!` outside tests. The ast-grep rules in `rules/` also reject `as` casts, stringly-typed errors, inline test modules and `println!` in library code.
