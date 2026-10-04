# uji.action

Actions are named functions that keys can run. uji has built-in actions,
listed in [Keys](keymap.md#actions), and you can add your own.

## uji.action.add(name, handler)

Registers an action. A key bound to `name` then runs `handler` with no
arguments. Raises an error when `name` belongs to a built-in action.

```lua
uji.action.add("insert_date", function()
  uji.input.append(os.date("%Y-%m-%d"))
end)
uji.keymap.add("normal", "<A-d>", "insert_date")
```

## uji.action.remove(name)

Removes an action you added and returns `true` if it existed.

```lua
uji.action.remove("insert_date")
```

## uji.action.list()

Returns the names of every action, built-in and added, in alphabetical order.

```lua
local actions = uji.action.list()
```


# Provider APIs

A provider's `api` turns a model call into a request in one HTTP API's format
and streams the answer back. It's an object with a `stream` method, and you set it with
the `api` field of [`uji.provider.add`](provider.md#ujiprovideraddspec).

uji ships four API classes under `uji.api`, and calling a class makes an
object.

| Class | API |
|---|---|
| `uji.api.openai` | OpenAI Chat Completions, `/chat/completions`. Most providers use it. |
| `uji.api.responses` | OpenAI Responses, `/responses`. The OpenAI and xAI providers use it. |
| `uji.api.anthropic` | Anthropic Messages, `/messages`. |
| `uji.api.gemini` | Gemini `streamGenerateContent`. |

`uji.api.<name>` loads `lua/uji/builtin/apis/<name>.lua`, so a file of your
own in that folder of your config adds `uji.api.<name>` too.

```lua
uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  api = uji.api.openai(),
  base_url = "http://localhost:4000",
  auth_env = { "LITELLM_API_KEY" },
  models = { { id = "claude-sonnet-4-5", reasoning = true } },
})
```

## uji.class(parent)

Makes a class from `parent`, such as `uji.api.openai`, that keeps the parent's
methods until it defines its own. The next section shows it in use.

## Changing an API for one provider

A provider whose API differs in a few places gets a class of its own, made
from the closest built-in class with `uji.class`. It redefines only the
methods that differ. This is how the built-in DeepSeek provider turns
thinking on and off and sends each reply's reasoning back:

```lua
local OpenAI = uji.api.openai

local DeepSeek = uji.class(OpenAI)

function DeepSeek:efforts()
  return { "off", "low", "high", "max" }
end

function DeepSeek:thinking(body, request)
  body.thinking = { type = request.effort == "off" and "disabled" or "enabled" }
  if request.effort ~= "off" then
    body.reasoning_effort = request.effort
  end
end

function DeepSeek:assistant(item, request)
  local out = OpenAI.assistant(self, item, request)
  out.reasoning_content = item.reasoning or ""
  return out
end

uji.provider.add({
  id = "deepseek",
  name = "DeepSeek",
  api = DeepSeek(),
  base_url = "https://api.deepseek.com",
  models = { { id = "deepseek-v4-pro", reasoning = true } },
})
```

## The OpenAI Chat Completions class

`uji.api.openai(opts)` makes an object. Each field of
`opts` is set on the object, so these options can be given there or changed
in a class of your own.

| Option | Default | Meaning |
|---|---|---|
| `max_tokens_field` | `"max_tokens"` | The body field for the output limit, such as `"max_completion_tokens"`. `false` leaves the limit out. |
| `finish_reason` | `true` | With `false`, a stream that ends without a `finish_reason` still counts as complete. |
| `cache_key` | `false` | With `true`, sends the session id as `prompt_cache_key`. |
| `tool_result_name` | `false` | With `true`, sends the tool's name with each tool result. |
| `bridge_tool_images` | `false` | With `true`, puts a short assistant message between tool results and the images they returned. Mistral needs this. |

These methods are the ones a provider most often redefines:

| Method | Does |
|---|---|
| `efforts(model)` | Returns the efforts a model accepts, used when the model does not list its own. |
| `thinking(body, request)` | Adds the reasoning fields to the request body. The default sends `reasoning_effort`. |
| `user(item, request)`, `assistant(item, request)`, `tool(item, request)` | Turn one message into the API's format. |
| `headers(request)` | Returns the request headers. The default sends the key as a bearer token. |
| `url(request)` | Returns the endpoint. |
| `body(request)` | Builds the whole request body. |
| `reasoning(delta)` | Returns the reasoning text in a streamed delta. The default reads `reasoning_content`, `reasoning` and `reasoning_text`. |

The other classes follow the same shape. The Responses class has the
`cache_key` option, on by default, and a `reasoning(request)` method that
returns the `reasoning` field. The Anthropic class picks adaptive thinking or
a thinking budget from the model id, and the Gemini class picks a thinking
level or a budget the same way.

## The request

uji calls `api:stream(request, reply)`. The method may return a function that
cancels the call. The request has these fields:
- `model`, the model id
- `system`, the system prompt
- `messages`, the conversation in uji's message format, where a user or tool
  message may have `images`, a list of tables with `media_type`, base64
  `data`, `name`, `width` and `height`
- `tools`, a list of `name`, `description` and `parameters`
- `reasoning`, `true` when the model reasons
- `effort`, one of the model's efforts, or `nil` for the provider's default
- `max_output`, the output token limit
- `cache`, one of `off`, `short` and `long`
- `ctx`, a table with `session`, the session the request is for, whose `id`
  is the session id. It is empty for a request made outside a session.
- `provider`, with `id` and `base_url`
- `auth`, with `key`, and `oauth` for subscription sign-in

An assistant message carries the `replay` its API returned, described below.

## The reply

The reply table has four functions:
- `reply.text(delta)` streams answer text.
- `reply.reasoning(delta)` streams reasoning text.
- `reply.done(answer)` finishes the call. `answer` has `text`, and optionally
  `reasoning`, `tool_calls`, `usage` and `replay`. Each tool call has `id`,
  `name` and `arguments`, where `arguments` is a JSON string, and may have a
  `signature`. `usage` has `input`, `output`, `cache_read` and `cache_write`.
- `reply.fail(failure)` ends the call with an error. `failure.kind` is
  `"http"`, with `status`, `message` and `retry_after`, or `"auth"`, with
  `status`, or `"provider"`, with `message`. uji retries `http` failures with a
  status of 408, 409, 425, 429 or 5xx, and `http` failures with no status,
  such as a dropped connection.

## Replay

Some APIs need data from an earlier reply sent back with the conversation,
such as Anthropic's signed thinking blocks or the encrypted reasoning of the
Responses API. An API puts that data in `answer.replay`, and uji saves it on
the assistant message. When the API builds a later request, it finds the data
in `item.replay` and sends it back. The built-in classes tag their replay with
their name and the model, and send it back only to the same model. A
tool call's `signature` is saved the same way, and the Gemini class sends it
back with the call.

## uji.api.stream

`uji.api.stream.run(spec, reply)` sends a JSON `POST` to
an endpoint that answers with server-sent events, reads the stream into an
answer, and ends the call through `reply`. It returns the answer, or `nil`
and the failure, so a `stream` method can return what it returns. The
built-in classes all use it.

| Field | Type | Meaning |
|---|---|---|
| `url` | string | Required. The endpoint. |
| `headers` | table | Request headers. uji adds `Content-Type: application/json`. |
| `body` | table | The request body, which uji encodes as JSON. |
| `read` | function | Required. uji calls `read(event, parts)` with each `data:` event, decoded from JSON. |
| `finished` | function | Called as `finished(parts)` when the stream ends. It may return a failure. |
| `settle` | function | Called as `settle(parts, calls)` once the tool calls are complete. It may return a failure. |

`read` builds the answer on `parts`:
- `parts:push_text(delta)` adds answer text and streams it to the transcript.
- `parts:push_reasoning(delta)` does the same for reasoning text.
- `parts:call(index)` returns the tool call at `index`, creating it with an
  empty `id`, `name` and `arguments`. Set `id` and `name`, and append each
  fragment of JSON to `arguments` as it arrives. A `signature` set on it stays
  with the call.
- `parts:finish()` marks the reply as complete. A `data: [DONE]` line does the
  same.
- `parts.usage` is a table with `input`, `output`, `cache_read` and
  `cache_write`, which `read` sets from what the provider reports.
- `parts.hit_limit = true` records that the model stopped at its output limit.
- `parts.failure` set to a failure ends the call with it.
- `parts.replay` becomes the answer's `replay`.
- `parts:has_text()` returns `true` once any answer text has arrived.

uji ends the call with a failure in these cases:
- The status is not 2xx. A 401 or 403 is an `auth` failure, and anything else
  is an `http` failure with the status, the `retry-after` seconds and the
  start of the body.
- No data arrives for 120 seconds.
- The stream ends before `parts:finish()`. A provider that never says it
  finished can call `parts:finish()` from `finished`.
- A tool call's `arguments` are not complete JSON.
- The model hit its output limit and made no tool calls.

```lua
local Plain = uji.class()

function Plain:stream(request, reply)
  local messages = { { role = "system", content = request.system } }
  for _, message in ipairs(request.messages) do
    if message.type == "user" or message.type == "assistant" then
      messages[#messages + 1] = { role = message.type, content = message.text }
    end
  end
  return uji.api.stream.run({
    url = request.provider.base_url .. "/chat/completions",
    headers = { Authorization = "Bearer " .. (request.auth.key or "") },
    body = { model = request.model, messages = messages, stream = true },
    read = function(event, parts)
      local choice = event.choices and event.choices[1]
      if choice and choice.delta and choice.delta.content then
        parts:push_text(choice.delta.content)
      end
      if choice and choice.finish_reason then
        parts.hit_limit = choice.finish_reason == "length"
        parts:finish()
      end
    end,
  }, reply)
end

uji.provider.add({ id = "plain", name = "Plain", api = Plain(), base_url = "http://localhost:8080/v1" })
```


# Quitting and reloading

## uji.quit()

Fires [`before_quit`](events.md#before_quit), restores the terminal and exits
uji. `/quit` calls this.

```lua
uji.keymap.add("normal", "<C-q>", function()
  uji.quit()
end)
```

## uji.reload()

Restarts uji on the same session, reading your config and plugins again, and
keeps the text on the input line. While a turn runs, uji doesn't restart and
says so in a notice. `/reload` calls this.

```lua
uji.keymap.add("normal", "<A-r>", function()
  uji.reload()
end)
```


# uji.auth

These functions choose where credentials live, save them, and sign in to the
providers that offer a subscription.

## uji.auth.configure(opts)

Chooses where uji keeps API keys and subscription sign-ins.

| Field | Type | Meaning |
|---|---|---|
| `keychain` | boolean | With `true`, uji saves credentials in the system keychain and looks there first. The default is `false`. |

Without the keychain, uji keeps credentials in `auth.toml` in the
[data directory](../configuration/files.md), readable only by you. Each
provider gets a table named by its id, and a provider can also be a plain
string, which uji reads as an API key. A keychain that refuses a save sends
the credential to `auth.toml` as well.

Raises an error for an unknown field, and for a `keychain` that is not a
boolean.

## uji.auth.authenticated(id)

Returns `true` when uji has a saved key or sign-in for the provider `id`, or
finds its key in one of the provider's `auth_env` variables. Raises an error
for an unknown provider.

```lua
if not uji.auth.authenticated("anthropic") then
  uji.notify("run /login to set up Anthropic")
end
```

## uji.auth.save_key(id, key)

Saves an API key for the provider `id` and returns `true`, or `nil` and an
error message when the key could not be saved. Raises an error for an unknown
provider or an empty key.

```lua
local ok, err = uji.auth.save_key("openrouter", os.getenv("MY_OPENROUTER_KEY"))
```

## uji.auth.login(id, on_done)

Signs in to the provider `id` with its subscription. uji opens your browser,
waits for the sign-in to finish, saves it, and gives `true`, or `nil` and an
error message. A provider without `oauth` settings gives an error message
too. Raises an error for an unknown provider.

```lua
uji.auth.login("anthropic", function(ok, err)
  uji.notify(ok and "signed in" or "sign-in failed: " .. err)
end)
```


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


# uji.config

## uji.config.files(folder, opts, on_done)

Reads the files in `folder` of your config directory and of each pack, in the
order [`uji.pack.list`](pack.md#ujipacklist) gives. `on_done` receives a list
of tables with `name`, the file name, `path`, the full path, and `text`, the
contents. Folders inside `folder` are left out. These reads are not limited to
the working directory, because the files belong to your config.

| Option | Type | Meaning |
|---|---|---|
| `project` | boolean | With `true`, also reads `.uji/<folder>` in the session's directory, or in the nearest directory above it that has one. Those files come last and have `project = true`. |

Raises an error when `folder` is empty, absolute or reaches outside with `..`.

```lua
uji.config.files("agents", { project = true }, function(files)
  for _, file in ipairs(files) do
    uji.notify((file.project and "project: " or "") .. file.name)
  end
end)
```


# uji.context

These functions control what the model sees besides the conversation. They
add your own lines to each turn and decide when uji compacts old messages.

## uji.context.add(name, provide, opts)

Registers a function that uji calls at the start of every turn. What it
returns decides where the text goes.

| Return | Effect |
|---|---|
| a string | uji appends it to the system prompt. |
| `{ text = "...", at = "turn" }` | uji adds the text after your message and keeps it in the conversation. The transcript does not show it. |
| `nil` | uji adds nothing this turn. |

Text added with `at = "turn"` stays in the conversation. When it stops being
true, return a line that says so once, such as `Plan mode is off.` Return text
that changes between turns this way, not as a string. When the system prompt
changes, the provider cannot reuse its cache for the conversation.

`opts.priority` orders the functions, lowest first. The default is 50. A
function with the same name replaces the earlier one.

```lua
uji.context.add("branch", function()
  local branch = io.popen("git branch --show-current"):read("*l")
  if branch and branch ~= "" then
    return "The current git branch is " .. branch .. "."
  end
end, { priority = 20 })
```

## uji.context.remove(name)

Removes a context function and returns `true` if it existed.

```lua
uji.context.remove("branch")
```

## uji.context.list()

Returns the names of the context functions, in the order uji calls them.

```lua
local names = uji.context.list()
```

## uji.context.configure(opts)

Sets how long the provider caches the conversation, and when uji compacts.
When the conversation grows past the model's context window minus a reserve,
uji summarises older messages before the next turn.

| Key | Meaning | Default |
|---|---|---|
| `cache` | How long the provider keeps the conversation cached between turns. `"off"`, `"short"` for 5 minutes, or `"long"` for 1 hour. A cache write costs more with `"long"`, and the cache survives longer pauses. It applies to models with `cache = true` in [`uji.provider.add`](provider.md). | `"short"` |
| `compaction.enabled` | Compact automatically. `/compact` works either way. | `true` |
| `compaction.reserve` | Tokens to keep free for the reply. | the model's output limit, or 20,000 when unknown, at most a quarter of the window |
| `compaction.keep_recent` | Tokens of recent messages to keep word for word. | `20000` |

Raises an error for an unknown key or an unknown `cache` value.

```lua
uji.context.configure({
  cache = "long",
  compaction = { keep_recent = 40000 },
})
```


# Events

Handlers run lowest priority first. For the events under
[Hooks](#hooks), uji uses what the handlers return.

```lua
uji.on("tool_started", function(event)
  uji.notify("running " .. event.name)
end)
```

Every payload also has an `event` field that holds the event's name.

## uji.on(event, handler, opts)

Adds a handler for an event and returns the handler's name.

| Argument | Type | Required | Meaning |
|---|---|---|---|
| `event` | string | yes | The event name. |
| `handler` | function | yes | Receives the payload table. |
| `opts.priority` | integer | no | Lower runs first. The default is 50. |
| `opts.name` | string | no | A name for the handler. A handler with the same name replaces this one. uji picks a name when you leave it out. |

```lua
uji.on("turn_finished", function()
  uji.notify("done")
end, { name = "notify-done", priority = 90 })
```

## uji.off(event, name)

Removes the handler with that name and returns `true` if it existed.

```lua
local name = uji.on("turn_finished", function() end)
uji.off("turn_finished", name)
```

## uji.emit(event, payload)

Runs the handlers of any event with the payload you give. Plugins use it for
events of their own, and to redraw the footer through `status_changed`.

```lua
uji.emit("status_changed", {})
```

## Notifications

uji ignores what these handlers return.

### session_created

A new session started. The payload has `session_id`.

### session_resumed

You resumed a saved session. The payload has `session_id`.

### session_titled

The session got a title. The payload has `title`.

### session_compacted

uji summarised earlier messages to free context. The payload has `count`, the
number of messages it folded into the summary.

### message_submitted

You sent a message. The payload has `text`.

### message_appended

A message joined the transcript. The payload has `type` and `text`. The type
is one of `user`, `assistant`, `tool`, `system`, `shell`, `error`,
`compaction` and `context`.

### queue_changed

The queue of messages you typed while the model worked changed. The payload
has `count`.

### shell_started

A `!` command started. The payload has `command`.

### shell_finished

A `!` command finished. The payload has `command` and `code`, its exit code.

### tool_started

A tool call passed approval and started. The payload has `name`.

### turn_finished

The model finished its turn, or you interrupted it.

### model_changed

The provider or model changed. The payload has `provider` and `model`.

### status_changed

Something the footer shows changed, such as the running state, the model or
the queue.

### layout_changed

Fires when a window moves or changes size, including when the terminal is
resized. The payload is empty. Read the new places with
[`uji.ui.list_wins`](ui.md#ujiuilist_wins).

### loader_ticked

Fires on every loader frame while the model works, for redrawing an animation.

### before_quit

uji is about to exit.

## Hooks

### before_turn

Runs before each turn. The payload has `text`, the message you sent, and
`system`, the system prompt. Return a string to replace the system prompt.
Each handler receives the prompt as the previous handler left it.

```lua
uji.on("before_turn", function(turn)
  return turn.system .. "\n\nAnswer in British English."
end)
```

### before_tool

Runs before each tool call, before the tool policy. The payload has `name` and
`arguments`. The first handler to return a decision wins, and uji then skips
the policy. Return `nil` to leave the decision to the next handler.

| Return | Effect |
|---|---|
| `{ allow = true }` | Run the tool without asking. |
| `{ deny = "reason" }` | Refuse the call. The model sees the reason. |
| `{ ask = true }` | Ask you before running it. |
| `{ ask = "question" }` | Ask you, with your own question as the title. |

```lua
uji.on("before_tool", function(call)
  if call.name == "run_command" and call.arguments.command:match("^git push") then
    return { deny = "Pushing is my job." }
  end
end, { priority = 10 })
```

### after_tool

Runs after each tool call, before the result reaches the model. The payload
has `name` and `content`. Return a string to replace the result. Each handler
receives the result as the previous handler left it.

```lua
uji.on("after_tool", function(result)
  return (result.content:gsub("sk%-%w+", "[redacted]"))
end)
```

### render_message

Runs when uji draws a block of the transcript. The payload has `type`, `text`,
and for tool results `name`, and for assistant messages `tool_calls`. Besides
the message types, `type` can be `notice`, `pending`, `thinking` or `queued`.
Return a list of lines, in the [`uji.ui.set_lines`](ui.md#ujiuiset_linesid-lines)
format, to draw instead of the default. The first handler to return lines
wins.

```lua
uji.on("render_message", function(block)
  if block.type == "tool" and block.name == "todo" then
    return { { { text = "  task list updated", color = "gray" } } }
  end
end)
```


# uji.fs

Every function here goes through the same checks as the file tools.
Relative paths start at the working directory, and
[confinement](tool.md#ujitoolconfineenabled) applies.

## uji.fs.read(path, on_done)

Reads a whole file. `on_done` receives the contents, or `nil` and an error
message.

```lua
uji.fs.read("Cargo.toml", function(text, err)
  if text then
    uji.notify(#text .. " bytes")
  end
end)
```

## uji.fs.lines(path, opts, on_done)

Reads a range of lines from a text file. It refuses directories and binary
files.

| Option | Type | Meaning |
|---|---|---|
| `offset` | integer | The first line to return, counting from 1. The default is 1. |
| `limit` | integer | The most lines to return. The default is all of them. |
| `max_line` | integer | Cuts lines longer than this many bytes. |

`on_done` receives a table with `lines`, the list of lines, `cut`, whose keys
are the positions of lines that `max_line` cut, and `total`, the number of
lines in the file.

```lua
uji.fs.lines("README.md", { offset = 1, limit = 20 }, function(page, err)
  if page then
    uji.notify(string.format("showing %d of %d lines", #page.lines, page.total))
  end
end)
```

## uji.fs.write(path, content, on_done)

Writes a file, creating missing directories. `on_done` receives a table whose
`created` field is `true` when the file did not exist, or `nil` and an error
message.

```lua
uji.fs.write("notes/todo.md", "- write the docs\n", function(result, err)
  if result and result.created then
    uji.notify("created notes/todo.md")
  end
end)
```

## uji.fs.list(path, on_done)

Lists a directory. `on_done` receives a list of tables with `name` and
`type`, which is `"file"`, `"dir"`, `"link"` or `"other"`, sorted by name, or
`nil` and an error message.

```lua
uji.fs.list("src", function(entries, err)
  if entries then
    uji.notify(#entries .. " entries in src")
  end
end)
```


# uji.http

## uji.http.request(opts, on_done)

Sends an HTTP request and returns a function that cancels it. `on_done`
receives a response table with `status`, `headers` and `body`, or `nil` and an
error message. Header names are lower case.

| Option | Type | Meaning |
|---|---|---|
| `url` | string | Required. The URL. |
| `method` | string | The HTTP method. The default is `"GET"`. |
| `headers` | table | Request headers, name to value. |
| `body` | string | The request body. |
| `timeout` | number | Seconds before the request fails. The default is 30 for a plain request and none for a streamed one. |
| `on_line` | function | Streams the response. uji calls it with each line of the body as it arrives. Return `false` for a line that is not progress, such as a keep-alive. |
| `idle` | number | For a streamed request, the seconds without progress before uji gives up. The default is 120. |

A non-2xx status still counts as a response. Check `status` yourself. An
invalid URL, method or header raises an error.

```lua
uji.http.request({
  url = "https://api.github.com/repos/uji-labs/uji",
  headers = { Accept = "application/vnd.github+json" },
}, function(response, err)
  if not response then
    uji.notify("request failed: " .. err)
  elseif response.status == 200 then
    uji.notify(uji.json.decode(response.body).description)
  end
end)
```


# Available APIs

Every function lives under the global `uji` table. A function that finishes later takes a callback as its last argument, which receives the result, or `nil` and an error message. Called without the callback from a slash command, a key binding or a timer, it waits and returns the result instead. A function that starts background work returns a function that stops it. Wrong arguments raise an error at the call.

## Tools

| Name | Does |
|---|---|
| [`uji.tool.add(name, spec)`](tool.md#ujitooladdname-spec) | Registers a tool the model can call, or replaces the tool with the same name. |
| [`uji.tool.remove(name)`](tool.md#ujitoolremovename) | Removes a tool and returns `true` if it existed. |
| [`uji.tool.list()`](tool.md#ujitoollist) | Returns the names of every registered tool. |
| [`uji.tool.disable(names)`](tool.md#ujitooldisablenames) | Turns tools off. The model still sees them, and uji denies any call to them. |
| [`uji.tool.enable(names)`](tool.md#ujitoolenablenames) | Turns tools back on after `uji.tool.disable`. |
| [`uji.tool.policy(rules)`](tool.md#ujitoolpolicyrules) | Sets which tool calls run without asking, which ask first, and which uji refuses. |
| [`uji.tool.confine(enabled)`](tool.md#ujitoolconfineenabled) | With `true`, limits `read_file`, `edit_file` and `write_file` to the working directory and the roots from `uji.tool.roots`. |
| [`uji.tool.roots(paths)`](tool.md#ujitoolrootspaths) | Replaces the directories the file tools may reach besides the working directory, and returns the list. |

## Commands

| Name | Does |
|---|---|
| [`uji.command.add(name, spec)`](command.md#ujicommandaddname-spec) | Registers `/name`, or replaces the command with the same name, built-in or not. |
| [`uji.command.remove(name)`](command.md#ujicommandremovename) | Removes a command and returns `true` if it existed. |
| [`uji.command.list()`](command.md#ujicommandlist) | Returns the names of every command in alphabetical order. |

## Keys

| Name | Does |
|---|---|
| [`uji.keymap.add(mode, key, binding)`](keymap.md#ujikeymapaddmode-key-binding) | Binds a key in one mode, replacing what the key did there. |
| [`uji.keymap.remove(mode, key)`](keymap.md#ujikeymapremovemode-key) | Unbinds a key in one mode, including a default binding. |
| [`uji.keymap.reset()`](keymap.md#ujikeymapreset) | Restores the default bindings. |
| [`uji.keymap.list()`](keymap.md#ujikeymaplist) | Returns one row per binding, with `mode`, `key`, and one of `action`, `command` or `unbound = true`. |

## Actions

| Name | Does |
|---|---|
| [`uji.action.add(name, handler)`](action.md#ujiactionaddname-handler) | Registers an action. |
| [`uji.action.remove(name)`](action.md#ujiactionremovename) | Removes an action you added and returns `true` if it existed. |
| [`uji.action.list()`](action.md#ujiactionlist) | Returns the names of every action, built-in and added, in alphabetical order. |

## Windows, pickers and appearance

| Name | Does |
|---|---|
| [`uji.ui.open_win(opts)`](ui.md#ujiuiopen_winopts) | Opens a window and returns its id. |
| [`uji.ui.set_lines(id, lines)`](ui.md#ujiuiset_linesid-lines) | Replaces a window's content. |
| [`uji.ui.clear(id)`](ui.md#ujiuiclearid) | Empties a window. |
| [`uji.ui.set_size(id, size)`](ui.md#ujiuiset_sizeid-size) | Changes a window's size to rows or columns, `"fill"` or `"auto"`. |
| [`uji.ui.set_title(id, title)`](ui.md#ujiuiset_titleid-title) | Sets the title in a window's border, or removes it when `title` is `nil`. |
| [`uji.ui.close_win(id)`](ui.md#ujiuiclose_winid) | Closes a window and returns `true` if it was open. |
| [`uji.ui.list_wins()`](ui.md#ujiuilist_wins) | Returns every open window with its name, place and size. |
| [`uji.ui.size()`](ui.md#ujiuisize) | Returns the width and height of the terminal. |
| [`uji.ui.select(opts, on_done)`](ui.md#ujiuiselectopts-on_done) | Shows a list to choose from. |
| [`uji.ui.pick(opts, on_done)`](ui.md#ujiuipickopts-on_done) | Shows a fuzzy finder with a preview pane. |
| [`uji.ui.prompt(opts, on_done)`](ui.md#ujiuipromptopts-on_done) | Asks for a line of text. |
| [`uji.ui.confirm(opts, on_done)`](ui.md#ujiuiconfirmopts-on_done) | Asks a yes or no question, including uji's approval questions. |
| [`uji.ui.toggle_thinking()`](ui.md#ujiuitoggle_thinking) | Shows or hides the model's reasoning in the transcript. |
| [`uji.ui.exec(cmd)`](ui.md#ujiuiexeccmd) | Hides uji, runs a program in the terminal, and comes back when it exits. |
| [`uji.ui.configure(opts)`](ui.md#ujiuiconfigureopts) | Sets colours and screen behaviour. |

## Status and footer

| Name | Does |
|---|---|
| [`uji.status.provider()`](status.md#ujistatusprovider) | Returns the name of the current provider, or `nil` before one is set. |
| [`uji.status.model()`](status.md#ujistatusmodel) | Returns the current model id, or `nil` before one is set. |
| [`uji.status.effort()`](status.md#ujistatuseffort) | Returns the reasoning effort, such as `"medium"`, or `nil` when reasoning is off. |
| [`uji.status.context()`](status.md#ujistatuscontext) | Returns a table with `used`, the estimated tokens in the conversation, and `window`, the model's context size when uji knows it. |
| [`uji.status.queue()`](status.md#ujistatusqueue) | Returns the messages you typed while the model worked, which uji has not sent yet. |
| [`uji.status.state()`](status.md#ujistatusstate) | Returns `"working"` while a turn runs and `"idle"` otherwise. |
| [`uji.status.elapsed()`](status.md#ujistatuselapsed) | Returns the seconds since the current turn started, or `nil` when idle. |
| [`uji.status.loader_frame()`](status.md#ujistatusloader_frame) | Returns the loader frame to draw now, from `waiting.loader.frames` in [`uji.ui.configure`](ui.md#ujiuiconfigureopts). |
| [`uji.status.add(name, render, opts)`](status.md#ujistatusaddname-render-opts) | Registers a footer segment. |
| [`uji.status.remove(name)`](status.md#ujistatusremovename) | Removes a segment and returns `true` if it existed. |
| [`uji.status.list()`](status.md#ujistatuslist) | Returns the segment names in priority order. |
| [`uji.status.render(names)`](status.md#ujistatusrendernames) | Calls every segment, or the ones named, and returns the values that are not `nil`. |

## Model context

| Name | Does |
|---|---|
| [`uji.context.add(name, provide, opts)`](context.md#ujicontextaddname-provide-opts) | Registers a function that uji calls at the start of every turn. |
| [`uji.context.remove(name)`](context.md#ujicontextremovename) | Removes a context function and returns `true` if it existed. |
| [`uji.context.list()`](context.md#ujicontextlist) | Returns the names of the context functions, in the order uji calls them. |
| [`uji.context.configure(opts)`](context.md#ujicontextconfigureopts) | Sets how long the provider caches the conversation, and when uji compacts. |

## Events

| Name | Does |
|---|---|
| [`uji.on(event, handler, opts)`](events.md#ujionevent-handler-opts) | Adds a handler for an event and returns the handler's name. |
| [`uji.off(event, name)`](events.md#ujioffevent-name) | Removes the handler with that name and returns `true` if it existed. |
| [`uji.emit(event, payload)`](events.md#ujiemitevent-payload) | Runs the handlers of any event with the payload you give. |

## Session

| Name | Does |
|---|---|
| [`uji.session.info()`](session.md#ujisessioninfo) | Returns a table with the session's `id`, `title` and `directory`. |
| [`uji.session.messages()`](session.md#ujisessionmessages) | Returns the transcript as a list of tables with `type` and `text`. |
| [`uji.session.usage()`](session.md#ujisessionusage) | Returns the tokens spent in this session. |
| [`uji.session.set_title(title)`](session.md#ujisessionset_titletitle) | Renames the session, saves the name, and fires `session_titled`. |
| [`uji.session.submit(text)`](session.md#ujisessionsubmittext) | Sends a message as if you typed it. |
| [`uji.session.interrupt()`](session.md#ujisessioninterrupt) | Stops the current turn, or the running `!` command. |
| [`uji.session.compact()`](session.md#ujisessioncompact) | Summarises earlier messages to free context. |

## Input line

| Name | Does |
|---|---|
| [`uji.input.get()`](input.md#ujiinputget) | Returns the text on the input line. |
| [`uji.input.set(text)`](input.md#ujiinputsettext) | Replaces the text on the input line. |
| [`uji.input.append(text)`](input.md#ujiinputappendtext) | Adds text to the end of the input line. |
| [`uji.input.clear()`](input.md#ujiinputclear) | Empties the input line. |
| [`uji.input.attach(path)`](input.md#ujiinputattachpath) | Attaches an image file to the message on the input line. |
| [`uji.input.capture(handler)`](input.md#ujiinputcapturehandler) | Sends every key press to `handler` instead of the normal bindings, until `uji.input.release` runs. |
| [`uji.input.release()`](input.md#ujiinputrelease) | Returns the keyboard to the normal bindings. |

## Models

| Name | Does |
|---|---|
| [`uji.model.current()`](model.md#ujimodelcurrent) | Returns the provider, model, API root and effort the next turn uses. |
| [`uji.model.use(opts)`](model.md#ujimodeluseopts) | Changes the provider, model, API root or effort, and saves the choice. |
| [`uji.model.efforts()`](model.md#ujimodelefforts) | Returns the reasoning efforts the current model accepts. |

## Providers

| Name | Does |
|---|---|
| [`uji.provider.add(spec)`](provider.md#ujiprovideraddspec) | Adds a provider, or merges `spec` into the provider with the same `id`. |
| [`uji.provider.remove(id)`](provider.md#ujiproviderremoveid) | Removes a provider and returns `true` if it existed. |
| [`uji.provider.list()`](provider.md#ujiproviderlist) | Returns one table per provider with its settings and models. |
| [`uji.auth.configure(opts)`](auth.md#ujiauthconfigureopts) | Chooses between `auth.toml` and the system keychain for API keys and sign-ins. |
| [`uji.auth.authenticated(id)`](auth.md#ujiauthauthenticatedid) | Returns `true` when uji has a key or sign-in for a provider. |
| [`uji.auth.save_key(id, key)`](auth.md#ujiauthsave_keyid-key) | Saves an API key for a provider. |
| [`uji.auth.login(id, on_done)`](auth.md#ujiauthloginid-on_done) | Signs in to a provider with its subscription in the browser. |

## Provider APIs

| Name | Does |
|---|---|
| [`uji.class(parent)`](apis.md#ujiclassparent) | Makes a class, optionally from a parent class whose methods it keeps. |
| [`uji.api.openai`, `uji.api.responses`, `uji.api.anthropic`, `uji.api.gemini`](apis.md) | The API classes a provider's `api` is made from. |
| [`uji.api.stream.run(spec, reply)`](apis.md#ujiapistream) | Sends a request to a streaming endpoint and reads the events into an answer. |

## Processes

| Name | Does |
|---|---|
| [`uji.job.start(opts)`](job.md#ujijobstartopts) | Starts a process and returns a job table. |

## HTTP

| Name | Does |
|---|---|
| [`uji.http.request(opts, on_done)`](http.md#ujihttprequestopts-on_done) | Sends an HTTP request and returns a function that cancels it. |

## Files

| Name | Does |
|---|---|
| [`uji.fs.read(path, on_done)`](fs.md#ujifsreadpath-on_done) | Reads a whole file. |
| [`uji.fs.lines(path, opts, on_done)`](fs.md#ujifslinespath-opts-on_done) | Reads a range of lines from a text file. |
| [`uji.fs.write(path, content, on_done)`](fs.md#ujifswritepath-content-on_done) | Writes a file, creating missing directories. |
| [`uji.fs.list(path, on_done)`](fs.md#ujifslistpath-on_done) | Lists a directory. |
| [`uji.config.files(folder, opts, on_done)`](config.md#ujiconfigfilesfolder-opts-on_done) | Reads the files in a folder of your config, your packs and, if asked, the project. |

## JSON

| Name | Does |
|---|---|
| [`uji.json.encode(value)`](json.md#ujijsonencodevalue) | Turns a Lua value into a JSON string. |
| [`uji.json.decode(text, opts)`](json.md#ujijsondecodetext-opts) | Turns a JSON string into a Lua value. |
| [`uji.json.array(table)`](json.md#ujijsonarraytable) | Marks a table as a JSON array, so it encodes as `[]` even when empty. |

## Packs

| Name | Does |
|---|---|
| [`uji.pack.add(specs)`](pack.md#ujipackaddspecs) | Installs and loads packs. |
| [`uji.pack.list()`](pack.md#ujipacklist) | Returns every directory uji searches for modules and `plugin/` files, starting with your config directory. |
| [`uji.pack.update()`](pack.md#ujipackupdate) | Pulls every installed git pack and records the new commits in the lock file. |

## Timers and notices

| Name | Does |
|---|---|
| [`uji.schedule(callback)`](timers.md#ujischedulecallback) | Runs `callback` once the code that called it has finished. |
| [`uji.defer(seconds, callback)`](timers.md#ujideferseconds-callback) | Runs `callback` after a delay and returns a function that cancels it. |
| [`uji.notify(message)`](timers.md#ujinotifymessage) | Shows a notice in the transcript. |

## Quitting and reloading

| Name | Does |
|---|---|
| [`uji.quit()`](app.md#ujiquit) | Exits uji. |
| [`uji.reload()`](app.md#ujireload) | Restarts uji on the same session with your config read again. |

## Runtime

| Name | Does |
|---|---|
| [`uji.task.spawn(fn, ...)`](../runtime/tasks.md#ujitaskspawnfn-) | Starts a function as a task that runs alongside the rest of uji. |
| [`uji.sleep(seconds)`](../runtime/tasks.md#ujisleepseconds) | Pauses the current task. |
| [`uji.task.race(fn, ...)`](../runtime/tasks.md#ujitaskracefn-) | Runs functions at once and returns the first to finish. |
| [`uji.task.timeout(seconds, fn)`](../runtime/tasks.md#ujitasktimeoutseconds-fn) | Runs a function with a time limit. |
| [`uji.promise()`](../runtime/tasks.md#ujipromise) | Returns a promise that tasks can wait on. |
| [`uji.net.request(opts)`](../runtime/network.md#ujinetrequestopts) | Sends an HTTP request and returns the answer. |
| [`uji.net.open(opts)`](../runtime/network.md#ujinetopenopts) | Sends an HTTP request and streams the answer. |
| [`uji.net.listen(port)`](../runtime/network.md#ujinetlistenport) | Accepts connections on a local port. |
| [`uji.proc.spawn(argv, opts)`](../runtime/processes.md#ujiprocspawnargv-opts) | Starts a process. |
| [`uji.db.open(path)`](../runtime/storage.md#ujidbopenpath) | Opens a SQLite database. |
| [`uji.os`](../runtime/system.md) | Reads the platform, the environment and the clock. |
| [`uji.modules(namespace)`](../runtime/system.md#ujimodulesnamespace) | Lists the modules inside a namespace. |
| [`uji.keychain`](../runtime/system.md#ujikeychaingetservice-account) | Reads and writes secrets in the system keychain. |
| [`uji.clipboard`](../runtime/system.md#ujiclipboardget) | Reads and writes the system clipboard, and reads images from it. |
| [`uji.regex(pattern)`](../runtime/text.md#ujiregexpattern) | Compiles a regular expression. |
| [`uji.glob(pattern, opts)`](../runtime/text.md#ujiglobpattern-opts) | Compiles a glob. |
| [`uji.fuzzy(query, items)`](../runtime/text.md#ujifuzzyquery-items) | Ranks strings against a query. |
| [`uji.markdown(source)`](../runtime/text.md#ujimarkdownsource) | Parses Markdown into events. |
| [`uji.width(text)`](../runtime/text.md#ujiwidthtext) | Measures text in terminal columns. |
| [`uji.lossy(data)`](../runtime/text.md#ujilossydata) | Turns bytes into valid UTF-8. |
| [`uji.base64`](../runtime/encoding.md) | Encodes and decodes base64. |
| [`uji.toml`](../runtime/encoding.md) | Reads and writes TOML. |
| [`uji.sha256(data)`](../runtime/encoding.md) | Hashes data. |
| [`uji.random(count)`](../runtime/encoding.md) | Returns random bytes. |
| [`uji.image.fit(data, edge, bytes)`](../runtime/images.md#ujiimagefitdata-edge-bytes) | Checks an image and fits it to a size and a byte limit. |


# uji.input

These functions read and change what you have typed, and can take over the
keyboard.

## uji.input.get()

Returns the text on the input line.

```lua
local draft = uji.input.get()
```

## uji.input.set(text)

Replaces the text on the input line and puts the cursor at the end. Text such
as `/models` opens the command list, as typing it would.

```lua
uji.input.set("/models")
```

## uji.input.append(text)

Adds text at the end, with the cursor after it.

```lua
uji.input.append(" and add a test")
```

## uji.input.clear()

Empties the input line.

```lua
uji.input.clear()
```

## uji.input.attach(path)

Attaches the image at `path` to the message on the input line and adds its
`[image #n]` marker, then gives `true`, or `nil` and an error message when the
file is not a PNG, JPEG, GIF or WebP image. Relative paths start at the
session's directory.

```lua
uji.input.attach("screenshots/login.png")
```

## uji.input.capture(handler)

Sends every key press to `handler` instead of the normal bindings, until
`uji.input.release` runs. The handler receives a table with `key`, such as
`"<C-x>"`, `char` for a printable key, and `ctrl`, `alt` and `shift`. uji
releases the capture if the handler raises an error.

```lua
uji.input.capture(function(event)
  if event.key == "<Esc>" then
    uji.input.release()
  end
end)
```

## uji.input.release()

Returns the keyboard to the normal bindings.

```lua
uji.input.release()
```


# uji.job

`uji.job` runs a process in the background and streams its output to Lua.

## uji.job.start(opts)

Starts a process and returns a job table.

| Option | Type | Meaning |
|---|---|---|
| `cmd` | string or list | Required. A string runs through `sh -c`. A list is the program and its arguments. |
| `cwd` | string | The directory to run in. The default is uji's working directory. |
| `timeout` | number | Seconds before uji kills the process. |
| `on_stdout` | function | Receives each line the process writes to standard output. |
| `on_stderr` | function | Receives each line the process writes to standard error. |
| `on_exit` | function | Receives the exit code. When uji stopped the process, it receives `-1` and `"timeout"` or `"stopped"`. |

The job table has three functions:
- `job.send(text)` writes a line to the process's standard input, adding a
  newline if `text` lacks one.
- `job.close()` closes standard input.
- `job.stop()` kills the process.

Raises an error when `cmd` is missing or empty.

```lua
local job = uji.job.start({
  cmd = { "git", "status", "--short" },
  on_stdout = function(line)
    uji.notify(line)
  end,
  on_exit = function(code)
    if code ~= 0 then
      uji.notify("git status failed with " .. code)
    end
  end,
})
job.close()
```


# uji.json

Plugins use these to build request bodies and to read saved files and HTTP
answers.

## uji.json.encode(value)

Turns a Lua value into a JSON string, where an empty table becomes `{}` unless
[`uji.json.array`](#ujijsonarraytable) marked it. A string that is not valid
UTF-8 keeps its valid parts, and each invalid byte sequence becomes U+FFFD. A
function, a table that contains itself, or a key that is not a string or a
number raises an error.

```lua
local body = uji.json.encode({ model = "gpt-4.1", stream = true })
```

## uji.json.decode(text, opts)

Turns a JSON string into a Lua value. A JSON `null` becomes `uji.json.null`,
so it survives a round trip through `uji.json.encode`, unless you pass
`opts.nulls = false`, which turns it into `nil` and drops the key. Invalid JSON
raises an error.

```lua
local value = uji.json.decode('{"a": 1, "b": null}', { nulls = false })
```

## uji.json.array(table)

Marks a table as a JSON array, so it encodes as `[]` even when empty, and
returns the same table.

```lua
local body = uji.json.encode({ tools = uji.json.array({}) })
```

`uji.json.null` stands for JSON `null`.


# uji.keymap

A binding belongs to one of five modes.

| Mode | Where it applies |
|---|---|
| `normal` | The input line. |
| `suggest` | The command list that opens when you type `/`. |
| `select` | Pickers and lists. |
| `prompt` | Text prompts. |
| `confirm` | The approval question. |

A key is a single character such as `"q"`, or a chord in angle brackets.
`<C-x>` is Ctrl, `<A-x>` or `<M-x>` is Alt, `<S-x>` is Shift, and they
combine, as in `<C-A-x>`. The named keys are `CR`, `Esc`, `BS`, `Del`, `Tab`,
`S-Tab`, `Left`, `Right`, `Up`, `Down`, `Home`, `End`, `PageUp`, `PageDown`,
`Insert`, `Space`, `lt` for `<`, `gt` for `>`, and `F1` to `F12`.

## uji.keymap.add(mode, key, binding)

Binds a key in one mode, replacing what the key did there.

| Argument | Type | Meaning |
|---|---|---|
| `mode` | string | One of the five modes. |
| `key` | string | A key or chord. |
| `binding` | string, table or function | An action name from the list below, `{ command = "name" }` to run a slash command, or a function. |

Raises an error for an unknown mode, a key uji cannot parse, or a binding of
another type.

```lua
uji.keymap.add("normal", "<C-p>", { command = "models" })
uji.keymap.add("normal", "<C-l>", "clear_input")
uji.keymap.add("normal", "<A-i>", function()
  uji.session.interrupt()
end)
```

## uji.keymap.remove(mode, key)

Unbinds a key in one mode, including a default binding.

```lua
uji.keymap.remove("normal", "<C-t>")
```

## uji.keymap.reset()

Restores the default bindings.

```lua
uji.keymap.reset()
```

## uji.keymap.list()

Returns one row per binding, with `mode`, `key`, and one of `action`,
`command` or `unbound = true`.

```lua
for _, row in ipairs(uji.keymap.list()) do
  if row.command then
    uji.notify(row.key .. " runs /" .. row.command)
  end
end
```

## Default bindings

| Keys | Action | Modes |
|---|---|---|
| Ctrl+C | `quit` | all |
| Ctrl+A, Ctrl+E | `cursor_start`, `cursor_end` | normal, suggest, prompt, select |
| Ctrl+B, Ctrl+F | `cursor_left`, `cursor_right` | normal, suggest, prompt, select |
| Alt+B, Alt+F | `word_left`, `word_right` | normal, suggest, prompt, select |
| Ctrl+H | `backspace` | normal, suggest, prompt, select |
| Ctrl+D | `delete_forward` | normal, suggest, prompt, select |
| Ctrl+W, Alt+Backspace | `delete_word_back` | normal, suggest, prompt, select |
| Alt+D | `delete_word_forward` | normal, suggest, prompt, select |
| Ctrl+U, Ctrl+K | `delete_to_start`, `delete_to_end` | normal, suggest, prompt, select |
| Ctrl+Y | `yank` | normal, suggest, prompt, select |
| Ctrl+T | `transpose` | normal, suggest, prompt, select |
| Ctrl+P, Ctrl+N | `history_prev`, `history_next` | normal |
| Ctrl+P, Ctrl+N | `modal_up`, `modal_down` | select, suggest, confirm |
| Ctrl+G | `modal_cancel` | select, suggest, confirm |
| Shift+Enter, Alt+Enter, Ctrl+J | `insert_newline` | normal |
| Ctrl+V | `paste_image` | normal |

Enter, Esc, Tab, the arrow keys, and `y` and `n` in the approval question work
without a binding. A binding on one of these keys overrides it.

## Actions

`nothing`, `quit`, `interrupt`, `toggle_thinking`, `submit`, `clear_input`,
`backspace`, `delete_forward`, `delete_word_back`, `delete_word_forward`,
`delete_to_start`, `delete_to_end`, `yank`, `paste_image`, `transpose`, `insert_newline`,
`cursor_left`, `cursor_right`, `cursor_start`, `cursor_end`, `word_left`,
`word_right`, `scroll_up`, `scroll_down`, `page_up`, `page_down`,
`scroll_top`, `scroll_bottom`, `history_prev`, `history_next`, `modal_up`,
`modal_down`, `modal_accept`, `modal_cancel`, `suggest_complete`,
`confirm_allow`, `confirm_deny`, `confirm_toggle`.

[`uji.action.add`](action.md) adds your own.


# uji.model

These functions read and change the provider and model that uji sends turns
to, and the reasoning effort it asks for. `/models`, `/effort` and `/login` use them.

## uji.model.current()

Returns a table that describes what the next turn uses.

| Field | Meaning |
|---|---|
| `provider` | The provider's id, or `""` before one is set. |
| `name` | The provider's name, or `nil` before one is set. |
| `model` | The model id. |
| `base_url` | The API root the request goes to. |
| `effort` | The reasoning effort the next turn sends, or `nil` when the model does not reason. |
| `images` | `true` or `false` when uji knows whether the model takes images, and `nil` when it does not. |

```lua
local current = uji.model.current()
uji.notify(current.provider .. "/" .. current.model)
```

## uji.model.use(opts)

Changes the provider, model, API root or effort, saves the choice for the next
time uji starts, and fires [`model_changed`](events.md#model_changed).

| Field | Type | Meaning |
|---|---|---|
| `provider` | string | The id of the provider to switch to. |
| `model` | string | The model to use. Switching provider without a model picks the one you used last with that provider, or its first model. |
| `base_url` | string | An API root that overrides the provider's. `""` goes back to the provider's own. Switching provider clears it unless you give one. |
| `effort` | string | One of `off`, `minimal`, `low`, `medium`, `high`, `xhigh` and `max`. uji saves it, and each turn uses the nearest effort the current model accepts, so `medium` on a model that offers only `low` and `high` sends `high`. |

Fields you leave out stay as they are. Raises an error for an unknown provider
or effort.

```lua
uji.model.use({ provider = "anthropic", model = "claude-sonnet-4-5", effort = "high" })
```

## uji.model.efforts()

Returns the reasoning efforts the current model accepts, from the least
thinking to the most, such as `{ "off", "low", "medium", "high", "xhigh", "max" }`.
A model that does not reason gives an empty list. The model's `efforts` in
[`uji.provider.add`](provider.md#ujiprovideraddspec) set the list, and the
provider's API supplies it for a model without one.

```lua
local efforts = uji.model.efforts()
```


# uji.pack

Packs installed here come from GitHub, any git URL or a local folder, and
`/sync` updates them.

## uji.pack.add(specs)

Installs and loads packs. `specs` is a list, and each entry is one of these:
- a `"user/repo"` GitHub shorthand or a git URL
- a table with the URL or shorthand first, and one of `tag`, `branch` or
  `commit`
- a table with `url` instead of the first entry
- a table with `dir`, a local directory that uji never clones

A table may also set `name`, which defaults to the repository or directory
name. uji reports a pack it cannot install as a notice and keeps going.
Raises an error when `specs` is not a list.

```lua
uji.pack.add({
  { dir = "~/code/my-plugin" },
})
```

## uji.pack.list()

Returns every directory uji searches for modules and `plugin/` files, starting
with your config directory.

```lua
for _, root in ipairs(uji.pack.list()) do
  uji.notify(root)
end
```

## uji.pack.update()

Pulls every installed git pack and records the new commits in the lock file.
`/sync` does the same and then reloads.

```lua
uji.pack.update()
```


# uji.provider

uji ships 22 providers, and `/login` and `/models` offer every one you add
here as well.

## uji.provider.add(spec)

Adds a provider, or merges `spec` into the provider with the same `id`.

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Required. The provider's id. |
| `name` | string | The name `/login` shows. Required for a new provider. |
| `api` | object | The API the provider speaks, such as `uji.api.openai()`. [Provider APIs](apis.md) lists the built-in ones and how to change them. Required for a new provider. |
| `base_url` | string | The API root, such as `"https://api.openai.com/v1"`. Required for a new provider. |
| `auth_env` | list of strings | Environment variables that may hold the API key. |
| `models` | list or function | Model ids, or tables with `id`, `context`, `output`, `reasoning`, `cache`, `images` and `efforts`. `images` is `true` or `false` when you know whether the model takes images. `efforts` lists the reasoning efforts the model accepts, from `off`, `minimal`, `low`, `medium`, `high`, `xhigh` and `max`. Without it, uji asks the provider's `api`. A function returns that list, and uji calls it once, the first time it needs the provider's models. The function may wait, for example on `uji.http.request`. |
| `context_window` | integer | The context size to assume for a model that does not set one. |
| `oauth` | table | Subscription sign-in settings. The built-in Anthropic and OpenAI providers show the format. |

When the provider exists, each field you give replaces the old one, except
`models`, which merge by `id`. A model whose `id` is already listed replaces
the old one whole.

Raises an error for an unknown field, for an `api` without a `stream` method,
for `models` that are neither a list nor a function, for an unknown effort,
and for a new provider without `name`, `api` and `base_url`.

```lua
uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  api = uji.api.openai(),
  base_url = "http://localhost:4000",
  auth_env = { "LITELLM_API_KEY" },
  models = {
    { id = "claude-sonnet-4-5", context = 200000, output = 64000, reasoning = true },
  },
})

uji.provider.add({ id = "openai", base_url = "https://proxy.example.com/v1" })

uji.provider.add({
  id = "ollama",
  models = function()
    local response = uji.http.request({ url = "http://localhost:11434/api/tags", timeout = 5 })
    local models = {}
    for _, entry in ipairs(uji.json.decode(response.body).models) do
      models[#models + 1] = entry.name
    end
    return models
  end,
})
```

uji calls the function when the provider is the current one, when `/models`
lists it, and before the first request to it. The models it returns merge
with the ones the provider already has. When it raises an error, the provider
keeps its models, and uji calls it again the next time it needs them.

## uji.provider.remove(id)

Removes a provider and returns `true` if it existed.

```lua
uji.provider.remove("perplexity")
```

## uji.provider.list()

Returns one table per provider with `id`, `name`, `api`, `base_url`,
`auth_env`, `context_window`, `models`, `oauth`, which is `true` when the
provider offers subscription sign-in, `state` and `error`. Each model has `id`,
`context`, `output`, `reasoning`, `cache`, `images` and `efforts`.

`state` is one of the values in `uji.provider.STATE`:

| Value | Meaning |
|---|---|
| `STATE.IDLE` | The provider has a `models` function that uji has not called yet. |
| `STATE.LOADING` | The function is running. |
| `STATE.LOADED` | The models are in. A provider with a plain list starts here. |
| `STATE.FAILED` | The function raised an error, and `error` holds its message. uji calls it again the next time it needs the models. |

```lua
for _, provider in ipairs(uji.provider.list()) do
  if provider.base_url:find("localhost", 1, true) then
    uji.notify(provider.name)
  end
end
```

## uji.provider.get(id)

Returns the row for one provider, in the format `uji.provider.list()` uses, or
`nil` when no provider has that id. It does not load anything.

## uji.provider.load(id, on_done)

Calls the provider's `models` function if its models are not loaded yet,
waits for it, and returns the provider's row. The row's `state` is
`STATE.LOADED`, or `STATE.FAILED` with `error` set. With `on_done`, it returns
at once and calls `on_done` with the row. Raises an error when no provider has
that id.

```lua
local ollama = uji.provider.load("ollama")
if ollama.state == uji.provider.STATE.FAILED then
  uji.notify("could not list Ollama models: " .. ollama.error)
end
```


# uji.session

These functions read the open conversation, and can post to it, rename it,
compact it or stop the running turn.

## uji.session.info()

Returns a table with the session's `id`, `title` and `directory`.

```lua
local here = uji.session.info().directory
```

## uji.session.messages()

Returns the transcript as a list of tables with `type` and `text`, and tool
results also carry the tool's `name`.

```lua
local count = 0
for _, message in ipairs(uji.session.messages()) do
  if message.type == "user" then
    count = count + 1
  end
end
```

## uji.session.usage()

Counts the tokens spent in this session. The table it gives has `input`,
`output`, `cache_read`, `cache_write` and `total`, plus `last`, a table of the
same fields for the latest request, and `requests`, the number of requests so
far.

```lua
local usage = uji.session.usage()
local line = string.format("%d tokens over %d requests", usage.total, usage.requests)
```

## uji.session.set_title(title)

Renames the session, saves the name, and fires `session_titled`. An empty
title raises an error.

```lua
uji.session.set_title("fix the flaky login test")
```

## uji.session.submit(text)

Sends a message as if you typed it. While the model works, uji queues it
until the turn ends. Empty text raises an error.

```lua
uji.session.submit("Run the tests and fix what fails.")
```

## uji.session.interrupt()

Stops the current turn, or the running `!` command.

```lua
uji.session.interrupt()
```

## uji.session.compact()

Starts summarising the earlier messages to free context, the way `/compact`
does, and returns `true`. It returns `false` when a turn is running or there
is nothing to compact yet. uji fires
[`session_compacted`](events.md#session_compacted) when the summary is saved.

```lua
if not uji.session.compact() then
  uji.notify("nothing to compact")
end
```


# uji.status

These functions report what uji is doing right now, and keep the footer
segments that a statusline plugin draws.

## uji.status.provider()

Returns the name of the current provider, or `nil` before one is set.

```lua
local provider = uji.status.provider()
```

## uji.status.model()

Works like `uji.status.provider`, but gives the model id.

```lua
local model = uji.status.model()
```

## uji.status.effort()

The reasoning effort comes back as a string such as `"medium"`, or as `nil`
when reasoning is off.

```lua
local effort = uji.status.effort() or "off"
```

## uji.status.context()

Returns a table with `used`, the estimated tokens in the conversation, and
`window`, the model's context size when uji knows it.

```lua
local context = uji.status.context()
if context.window then
  uji.notify(string.format("%d%% of context used", context.used * 100 // context.window))
end
```

## uji.status.queue()

Lists the messages you typed while the model worked that uji has not sent
yet.

```lua
local waiting = #uji.status.queue()
```

## uji.status.state()

Gives `"working"` during a turn, and `"idle"` otherwise.

```lua
local busy = uji.status.state() == "working"
```

## uji.status.elapsed()

Counts the seconds since the current turn started. When idle, the result is
`nil`.

```lua
local seconds = math.floor(uji.status.elapsed() or 0)
```

## uji.status.loader_frame()

Picks the loader frame to draw now from `waiting.loader.frames` in
[`uji.ui.configure`](ui.md#ujiuiconfigureopts), or an empty string when idle.

```lua
local frame = uji.status.loader_frame()
```

## uji.status.add(name, render, opts)

Registers a footer segment. `render` returns any value the statusline plugin
understands, or `nil` to hide the segment. `opts.priority` orders segments,
lowest first, and defaults to 50.

```lua
uji.status.add("model", function()
  return { text = uji.status.model() or "no model", color = "cyan" }
end, { priority = 10 })
```

## uji.status.remove(name)

Removes a segment. The result is `true` if it existed.

```lua
uji.status.remove("model")
```

## uji.status.list()

Gives the segment names in priority order.

```lua
local segments = uji.status.list()
```

## uji.status.render(names)

Calls every segment in priority order and returns the values that are not
`nil`. With a list of names, it calls only those segments, in that order, and
skips names that are not segments. Footer plugins draw from it.

```lua
local parts = uji.status.render()
local right = uji.status.render({ "effort", "context" })
```


# Timers and notices

Both timers run their function as a [task](../runtime/tasks.md), so it can
wait.

## uji.schedule(callback)

Runs `callback` once the code that called it has finished. Called from your
config, it runs after uji has loaded the whole config and every plugin.

```lua
uji.schedule(function()
  uji.notify("config loaded")
end)
```

## uji.defer(seconds, callback)

Runs `callback` after a delay and returns a function that cancels it.

```lua
local cancel = uji.defer(30, function()
  uji.notify("thirty seconds passed")
end)
```

## uji.notify(message)

Shows a notice in the transcript.

```lua
uji.notify("hello from init.lua")
```


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
| `policy` | string | no | `"allow"`, `"ask"` or `"deny"`. Used when no policy rule matches. |
| `display.verb` | string | no | The transcript line, such as `"Read"`, which uji follows with the subject. |
| `display.question` | string | no | The title of the approval question. |

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


# uji.ui

## uji.ui.open_win(opts)

Opens a window and returns its id. The default config opens these four.

```lua
uji.ui.open_win({ name = "messages", view = "messages", split = "top", size = "fill", wrap = true })
uji.ui.open_win({ name = "input", view = "input", split = "bottom", size = "auto", border = "horizontal" })
uji.ui.open_win({ name = "modal", view = "modal", split = "bottom", size = "auto" })
uji.ui.open_win({ name = "activity", split = "bottom", size = 0, padding = 1 })
```

| Option | Values | Default |
|---|---|---|
| `name` | a name that [`uji.ui.list_wins`](#ujiuilist_wins) reports, so another plugin can find the window | none |
| `view` | `"messages"` for the transcript, `"input"` for the input line, `"modal"` for pickers, prompts and approval questions. Leave it out for a window you draw into. | none |
| `split` | `"top"`, `"bottom"`, `"left"` or `"right"` | `"top"` |
| `size` | rows or columns, `"fill"`, or `"auto"` to fit the content | `"fill"` |
| `border` | `"none"`, `"plain"`, `"rounded"` or `"horizontal"` | `"none"` |
| `border_color` | a [colour](#colours) | the theme's |
| `title` | text in the border | none |
| `wrap` | wrap long lines | `false` |
| `padding` | blank cells around the content | `0` |
| `priority` | layout order, lowest first. In a bottom split, lower sits closer to the bottom edge. | `50` |
| `float` | `{ width = ..., height = ... }`, each `"80%"` or a cell count | not floating |

Raises an error for an unknown view, split, border or size.

## uji.ui.list_wins()

Returns one table per open window, in layout order.

| Field | Meaning |
|---|---|
| `id` | The id that `uji.ui.open_win` returned. |
| `name` | The `name` the window was opened with, or `nil`. |
| `view` | `"messages"`, `"input"`, `"modal"`, or `nil` for a window a plugin draws into. |
| `split` | The side the window sits on. |
| `size` | The size it was given, such as `3`, `"fill"` or `"auto"`. |
| `priority` | Its layout order. |
| `float` | `true` for a floating window. |
| `x`, `y` | The column and row of its content, counted from 0 at the top left. |
| `width`, `height` | The size of its content in cells. |

The position and size fields stay `nil` until uji first draws the window.
uji fires [`layout_changed`](events.md#layout_changed) when any of them
changes.

```lua
for _, win in ipairs(uji.ui.list_wins()) do
  if win.name == "input" then
    uji.notify("the input line is " .. win.width .. " columns wide")
  end
end
```

## uji.ui.size()

Returns the width and height of the terminal in cells, or nothing when the
screen is not open, as in `uji run`.

```lua
local width, height = uji.ui.size()
```

## uji.ui.set_lines(id, lines)

Replaces a window's content. Each line is a list of spans. A span is a string,
or a table with `text` and any of `color`, `bg`, `bold`, `italic` and
`underline`. A line may also be a single span.

`{ fill = true }` is a span that takes the room the rest of the line leaves,
so the spans after it sit at the right edge. Several fills share that room
equally. A line too long for its window leaves them none.

```lua
local bar = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.set_lines(bar, { { "main", { fill = true }, { text = "3 files", color = "gray" } } })
```

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 2 })
uji.ui.set_lines(panel, {
  { { text = "build", bold = true }, " passing" },
  { text = "3 files changed", color = "gray" },
})
```

## uji.ui.clear(id)

Empties a window.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.clear(panel)
```

## uji.ui.set_size(id, size)

Changes a window's size to rows or columns, `"fill"` or `"auto"`.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 0 })
uji.ui.set_size(panel, 3)
```

## uji.ui.set_title(id, title)

Sets the title in a window's border, or removes it when `title` is `nil`.

```lua
local panel = uji.ui.open_win({ split = "right", size = 30, border = "plain" })
uji.ui.set_title(panel, "todo")
```

## uji.ui.close_win(id)

Closes a window and returns `true` if it was open.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.close_win(panel)
```

## uji.ui.select(opts, on_done)

Shows a list to choose from. `opts.title` is the title and `opts.items` is a
list of strings. `on_done` receives the chosen item, or `nil` if you cancel.
Without `on_done`, the call waits and returns the chosen item.

```lua
uji.ui.select({ title = "Branch", items = { "main", "dev" } }, function(choice)
  if choice then
    uji.notify("picked " .. choice)
  end
end)
```

## uji.ui.pick(opts, on_done)

Shows a fuzzy finder with a preview pane. `on_done` receives the chosen item,
or `nil` if you cancel. Without `on_done`, the call waits and returns the
chosen item.

| Option | Type | Meaning |
|---|---|---|
| `title` | string | The title. |
| `items` | list of strings | The items to filter. |
| `preview` | function | Receives the highlighted item and returns lines to show. Without it, an item like `path:line:` shows that part of the file. |
| `on_query` | function | Makes the list live. Receives the query each time typing pauses, and a `show(items)` function that replaces the list. |

```lua
uji.ui.pick({
  title = "Search",
  on_query = function(query, show)
    local hits = {}
    uji.job.start({
      cmd = { "rg", "--line-number", "--no-heading", query },
      on_stdout = function(line)
        hits[#hits + 1] = line
      end,
      on_exit = function()
        show(hits)
      end,
    })
  end,
}, function(choice)
  if choice then
    uji.notify(choice)
  end
end)
```

## uji.ui.prompt(opts, on_done)

Asks for a line of text. `opts.title` is the question, `opts.value` fills the
line, and `opts.hidden = true` masks the input. `on_done` receives the text,
or `nil` if you cancel. Without `on_done`, the call waits and returns the text.

```lua
uji.ui.prompt({ title = "Commit message" }, function(message)
  if message and message ~= "" then
    uji.session.submit("Commit the staged changes with the message: " .. message)
  end
end)
```

## uji.ui.confirm(opts, on_done)

Asks a yes or no question and gives `true` for yes and `false` for no. uji
asks its approval questions through this function, so a plugin that replaces
`uji.ui.confirm` answers them, or shows them its own way.

| Field | Meaning |
|---|---|
| `title` | The question. |
| `body` | Text under the question, such as the command a tool wants to run. |
| `timeout` | Seconds to wait. When they pass, the question closes and gives `nil`. |

```lua
local yes = uji.ui.confirm({ title = "Delete the build folder?" })
```

This replacement rings the terminal bell before each question, then asks it
the usual way:

```lua
local ask = uji.ui.confirm
uji.ui.confirm = function(request)
  io.stdout:write("\a")
  return ask(request)
end
```

## uji.ui.toggle_thinking()

Shows the model's reasoning in the transcript, or hides it again, and says
which in a notice. `/thinking` calls this.

```lua
uji.keymap.add("normal", "<C-t>", function()
  uji.ui.toggle_thinking()
end)
```

## uji.ui.exec(cmd)

Hides uji, runs a program in the terminal, and comes back when it exits.
`cmd` is a string, run through `sh -c`, or a list of the program and its
arguments.

```lua
uji.ui.exec("git log --oneline | less")
```

## uji.ui.configure(opts)

Sets colours and screen behaviour. Each call changes only the keys it names.
Raises an error for an unknown key or an invalid colour.

```lua
uji.ui.configure({
  theme = { accent = "#c65036", user_bg = "#2b2b2b" },
  input = { cursor_blink = false },
  waiting = { loader = { frames = { "-", "\\", "|", "/" }, interval = 0.1 } },
  confirm = { title = "Run this?", yes = "Run", no = "Skip" },
})
```

| Key | Meaning | Default |
|---|---|---|
| `show_thinking` | Show the model's reasoning. `/thinking` toggles it. | `false` |
| `input.cursor_blink` | Blink the cursor on the input line. | `true` |
| `suggest.enabled` | Show command suggestions when you type `/`. | `true` |
| `suggest.max_height` | Rows the suggestion list may use. | `5` |
| `waiting.loader.frames` | Strings the loader cycles through while the model works. | none |
| `waiting.loader.interval` | Seconds between loader frames. | `0.08` |
| `confirm.title` | The approval question's title. | `"Allow tool call?"` |
| `confirm.yes` | The allow label. | `"Yes"` |
| `confirm.no` | The deny label. | `"No"` |
| `theme.text` | Body text. | `#d4d4d4` |
| `theme.muted` | Secondary text and borders. | `#808080` |
| `theme.code` | Inline code. | `#e0af68` |
| `theme.accent` | Highlights. | `cyan` |
| `theme.user_bg` | The background of your messages. | `#343541` |
| `theme.selected_bg` | The selected row in lists. | `#3a3a4a` |
| `theme.cursor` | The cursor. | `white` |
| `theme.error` | Errors. | `red` |
| `theme.notice` | Notices. | `red` |
| `theme.input` | Text on the input line. | `theme.text` |
| `theme.confirm_title` | The approval question's title. | `theme.text` |
| `theme.confirm_body` | The approval question's details. | `theme.text` |
| `theme.confirm_selected` | The chosen answer. | the default style |
| `theme.confirm_unselected` | The other answer. | the default style |

## Colours

A colour is `#rrggbb` or one of `black`, `red`, `green`, `yellow`, `blue`,
`magenta`, `cyan`, `white`, `gray`, `dark_gray`, `light_red`, `light_green`,
`light_yellow`, `light_blue`, `light_magenta` and `light_cyan`. `grey` and
`dark_grey` also work.


# Where uji keeps its files

| Files | Default | Changed by |
|---|---|---|
| Config directory | `~/.config/uji` | `--config-dir`, `UJI_CONFIG_DIR` or `XDG_CONFIG_HOME` |
| Data directory | `~/.local/share/uji` | `--data-dir`, `UJI_DATA_DIR` or `XDG_DATA_HOME` |
| Session database | `uji.db` in the data directory | `--db` or `UJI_DB` |
| Installed packs | `site/` in the data directory | |
| Pack versions | `uji-lock.json` in the config directory | |
| Credentials | `auth.toml` in the data directory | [`uji.auth.configure`](../api/auth.md) |

An option on the command line wins over the `UJI_` variable, which wins over
the `XDG_` one. uji adds `/uji` to the `XDG_` directories.


# Configuration

uji reads `~/.config/uji`, or the directory in `UJI_CONFIG_DIR`.

```text
~/.config/uji/
  init.lua        runs first
  plugin/*.lua    runs after init.lua, sorted by file name
  lua/            modules for require()
```

`init.lua` replaces the default config. Start it with
`require("uji.builtin.defaults")` to keep the default screen.

```lua
require("uji.builtin.defaults")

uji.keymap.add("normal", "<C-p>", { command = "models" })
```


# Packs

[`uji.pack.add`](../api/pack.md) installs a directory or git repository with
its own `lua/` and `plugin/`. `/sync` updates them.

```lua
uji.pack.add({
  "uji-labs/uji-plugins",
  { "someone/tool", tag = "v1.2" },
  { dir = "~/code/my-plugin" },
})
```


# An approval rule

## Rules in the policy

Read-only git commands and the tests run without asking, and force-pushes are
refused.

```lua
uji.tool.policy({
  run_command = {
    allow = { "git status", "git diff*", "git log*", "cargo test*" },
    deny = { "/git push.*(--force|-f)/" },
  },
})
```

## A hook for decisions that need code

Refuses `git push`, and asks before commands that reach the network.

```lua
uji.on("before_tool", function(call)
  if call.name ~= "run_command" then
    return nil
  end
  local command = call.arguments.command or ""
  if command:match("^git push") then
    return { deny = "Pushing is my job. Tell me when the branch is ready." }
  end
  if command:match("curl") or command:match("wget") then
    return { ask = "This command reaches the network. Run it?" }
  end
end, { priority = 10 })
```


# A slash command

`/switch` lists your git branches in a picker and switches to the one you
choose. Alt+G opens it.

```lua
uji.command.add("switch", {
  desc = "switch git branch",
  handler = function()
    local branches = {}
    uji.job.start({
      cmd = { "git", "branch", "--format=%(refname:short)" },
      on_stdout = function(line)
        branches[#branches + 1] = line
      end,
      on_exit = function()
        uji.ui.select({ title = "Switch to", items = branches }, function(choice)
          if not choice then
            return
          end
          uji.job.start({
            cmd = { "git", "switch", choice },
            on_exit = function(code)
              uji.notify(code == 0 and ("on " .. choice) or ("git switch failed with " .. code))
              uji.emit("status_changed", {})
            end,
          })
        end)
      end,
    })
  end,
})

uji.keymap.add("normal", "<A-g>", { command = "switch" })
```

The handler receives the text typed after the command name.

```lua
uji.command.add("ask", function(args)
  uji.session.submit("Investigate before changing anything. " .. args)
end)
```


# A footer

A one-line footer with the model and the tokens spent.

```lua
require("uji.builtin.defaults")

local footer = uji.ui.open_win({ split = "bottom", size = 1, priority = 10 })

uji.status.add("model", function()
  return { text = uji.status.model() or "no model", color = "cyan" }
end, { priority = 10 })

uji.status.add("tokens", function()
  local usage = uji.session.usage()
  if usage.total > 0 then
    return { text = usage.total .. " tokens", color = "gray" }
  end
end, { priority = 20 })

local function draw()
  local spans = {}
  for _, part in ipairs(uji.status.render()) do
    if #spans > 0 then
      spans[#spans + 1] = "  "
    end
    spans[#spans + 1] = part
  end
  uji.ui.set_lines(footer, { spans })
end

uji.on("status_changed", draw)
uji.on("message_appended", draw)
```


# Examples

Each example is Lua that goes in `~/.config/uji/init.lua` or in a file in
`~/.config/uji/plugin/`.


# The system prompt

Your config can change the instructions that the model gets with every message
you send.

## Adding project notes

Adds `NOTES.md` from the working directory to the system prompt on every
turn.

```lua
uji.context.add("notes", function()
  local file = io.open(uji.session.info().directory .. "/NOTES.md")
  if not file then
    return nil
  end
  local notes = file:read("a")
  file:close()
  return "Project notes from NOTES.md:\n\n" .. notes
end)
```

## A reminder at the end of the turn

Text returned with `at = "turn"` goes after the conversation instead of into
the system prompt.

```lua
uji.context.add("reminder", function()
  return { text = "Run the tests before you say you are done.", at = "turn" }
end)
```

## Rewriting the whole prompt

A `before_turn` hook returns a new system prompt.

```lua
uji.on("before_turn", function(turn)
  return turn.system .. "\n\nWrite commit messages in the imperative mood."
end)
```

To replace the prompt entirely, override the built-in `uji.core.prompt`
module, as [Rebuilding uji](../rebuilding/index.md) shows.


# A provider

## An OpenAI-compatible endpoint

A LiteLLM proxy on your machine, or any server that speaks the OpenAI chat
format.

```lua
uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  api = uji.api.openai(),
  base_url = os.getenv("LITELLM_BASE_URL") or "http://localhost:4000",
  auth_env = { "LITELLM_API_KEY" },
  models = {
    { id = "claude-sonnet-4-5", context = 1000000, output = 64000, reasoning = true },
    { id = "glm-4.6", context = 204800, output = 131072, reasoning = true },
  },
})
```

## An endpoint with its own quirks

Some differences need only an option. This server wants the output limit in
`max_completion_tokens`:

```lua
uji.provider.add({
  id = "gateway",
  name = "Gateway",
  api = uji.api.openai({ max_tokens_field = "max_completion_tokens" }),
  base_url = "https://gateway.example.com/v1",
  auth_env = { "GATEWAY_API_KEY" },
  models = { { id = "qwen3-coder", reasoning = true, efforts = { "off", "high" } } },
})
```

For anything else, make a class from the API and redefine the method that
differs. This server turns thinking on and off with `enable_thinking`:

```lua
local Qwen = uji.class(uji.api.openai)

function Qwen:thinking(body, request)
  body.enable_thinking = request.effort ~= "off"
end

uji.provider.add({
  id = "dashscope",
  name = "DashScope",
  api = Qwen(),
  base_url = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  auth_env = { "DASHSCOPE_API_KEY" },
  models = { { id = "qwen3-max", reasoning = true, efforts = { "off", "high" } } },
})
```

[Provider APIs](../api/apis.md) lists the options and methods of each API.

## Reading model sizes from the endpoint

A LiteLLM proxy reports each model's context and output limits at
`/model/info`. This plugin reads them when uji starts and corrects the models
the provider lists. It sends back each model whole, with its `reasoning` and
other fields, because `uji.provider.add` replaces a model with the same `id`
as a whole.

```lua
local BASE_URL = os.getenv("LITELLM_BASE_URL") or "http://localhost:4000"

uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  api = uji.api.openai(),
  base_url = BASE_URL,
  auth_env = { "LITELLM_API_KEY" },
  models = {
    { id = "claude-sonnet-4-5", reasoning = true },
  },
})

local function listed(id)
  for _, provider in ipairs(uji.provider.list()) do
    if provider.id == id then
      local models = {}
      for _, model in ipairs(provider.models) do
        models[model.id] = model
      end
      return models
    end
  end
  return {}
end

uji.http.request({
  url = BASE_URL .. "/model/info",
  headers = { Authorization = "Bearer " .. (os.getenv("LITELLM_API_KEY") or "") },
}, function(response)
  if not response or response.status ~= 200 then
    return
  end
  local ok, info = pcall(uji.json.decode, response.body, { nulls = false })
  if not ok or type(info) ~= "table" or type(info.data) ~= "table" then
    return
  end
  local known, changed = listed("litellm"), {}
  for _, entry in ipairs(info.data) do
    local model = known[entry.model_name]
    local limits = entry.model_info or {}
    if model and (limits.max_input_tokens or limits.max_output_tokens) then
      model.context = limits.max_input_tokens or model.context
      model.output = limits.max_output_tokens or model.output
      changed[#changed + 1] = model
    end
  end
  if #changed > 0 then
    uji.provider.add({ id = "litellm", models = changed })
    uji.emit("status_changed", {})
  end
end)
```

## Changing a built-in provider

With the id of a built-in provider, `uji.provider.add` changes only the fields
you give.

```lua
uji.provider.add({ id = "openai", base_url = "https://llm-proxy.internal/v1" })

uji.provider.add({
  id = "anthropic",
  models = { { id = "claude-fable-5-1", context = 1000000, output = 128000, reasoning = true } },
})
```


# A tool of your own

Put these tools in `~/.config/uji/plugin/tools.lua`, or in `init.lua`.

## A tool that answers at once

`run` returns the result as a string.

```lua
uji.tool.add("branch", {
  description = "Name of the current git branch.",
  parameters = { type = "object", properties = {} },
  policy = "allow",
  display = { verb = "Checked the branch" },
  run = function()
    return io.popen("git branch --show-current"):read("*l") or "not a git repository"
  end,
})
```

## A tool that waits on a process

`run` starts a job and returns `job.stop`, so an interrupt kills it. The job
calls `ctx.done` when it exits.

```lua
uji.tool.add("count_todos", {
  description = "Count TODO comments per file in the working directory.",
  parameters = { type = "object", properties = {} },
  policy = "allow",
  display = { verb = "Counted TODOs" },
  run = function(_, ctx)
    local lines = {}
    local job = uji.job.start({
      cmd = { "rg", "--count-matches", "TODO" },
      on_stdout = function(line)
        lines[#lines + 1] = line
        ctx.progress(line)
      end,
      on_exit = function(code)
        if code == 1 then
          ctx.done("no TODO comments")
        else
          ctx.done(table.concat(lines, "\n"))
        end
      end,
    })
    return job.stop
  end,
})
```

## A tool with arguments and a subject

`subject` returns the URL, so the approval question shows it and the policy
matches it.

```lua
uji.tool.add("fetch_url", {
  description = "Download a web page and return its body.",
  parameters = {
    type = "object",
    properties = { url = { type = "string", description = "The page to fetch." } },
    required = { "url" },
  },
  subject = function(args)
    return args.url
  end,
  policy = "ask",
  display = { verb = "Fetched", question = "Fetch this page?" },
  run = function(args, ctx)
    return uji.http.request({ url = args.url }, function(response, err)
      if not response then
        ctx.done("error: " .. err)
      else
        ctx.done(response.body:sub(1, 20000))
      end
    end)
  end,
})

uji.tool.policy({
  fetch_url = { allow = { "https://docs.rs/*" } },
})
```


# Commands

## Running uji

| Run | Does |
|---|---|
| `uji`, `uji new` | Starts a new session. |
| `uji resume` | Resumes the latest session in the current directory. |
| `uji resume --id <ID>` | Resumes the session with that id. |
| `uji list` | Opens a picker of the sessions in the current directory. |
| `uji delete <ID>` | Deletes a session. |
| `uji run <PROMPT>` | Sends one prompt without the screen and prints the answer. See [Running without the screen](run.md). |
| `uji --help` | Prints the usage. |
| `uji --version` | Prints the version. |

Any of them takes these options. [Where uji keeps its files](../configuration/files.md)
lists the environment variables that do the same.

| Option | Sets |
|---|---|
| `--config-dir <DIR>` | The config directory. |
| `--data-dir <DIR>` | The data directory. |
| `--db <FILE>` | The session database. |

## Slash commands

| Command | Does |
|---|---|
| `/login` | Adds a provider. |
| `/models` | Picks the model. |
| `/effort` | Sets the reasoning effort, from the levels the current model accepts. |
| `/thinking` | Shows or hides the model's reasoning. |
| `/compact` | Summarises earlier messages to free context. |
| `/sync` | Updates installed packs and reloads. |
| `/reload` | Starts uji again with your current config and files, keeping the conversation and your draft. |
| `/help` | Lists every command, including the ones plugins add. |
| `/quit` | Quits. |

## Keys

[Default bindings](../api/keymap.md#default-bindings) lists every key uji
binds, and [uji.keymap](../api/keymap.md) changes them.


# First run

Start uji in the directory you want to work on.

```sh
cd ~/code/project
uji
```

## Signing in

Type `/login` and pick a provider from the list.

- Anthropic and OpenAI ask how you want to sign in. "Subscription (sign in
  with browser)" opens the provider's sign-in page, and "API key" asks for a
  key.
- A provider that needs a key asks for it. The prompt names the environment
  variable uji also reads, such as `ANTHROPIC_API_KEY`, and pressing Enter on
  an empty prompt uses that variable instead.
- Custom asks for the `base_url` and model of a server that takes OpenAI chat
  requests.

uji saves keys in `auth.toml` in the
[data directory](../configuration/files.md), readable only by you. To keep them
in the system keychain instead, call
[`uji.auth.configure`](../api/auth.md) in your config.

## Choosing a model

`/models` lists the models of every provider you are signed in to. `/effort`
sets how much the model reasons, from the levels that model accepts.

## Working with the model

- Enter sends your message. Shift+Enter, Alt+Enter or Ctrl+J start a new line.
- A message you send while the model works waits, and goes out when the turn
  ends.
- Esc clears the input line. On an empty line, Esc stops the turn.
- A line that starts with `!` runs in your shell, in the session's directory.
  Its output shows in the transcript, and the model does not see it.
- When a tool call needs your approval, `y` lets it run. `n` or Esc refuses
  it, and you can then tell the model what to do instead.

## Sending images

Ctrl+V attaches the image on the clipboard, or pastes its text when it holds
no image. Pasting the path of an image file attaches that file, which is what
dragging a file into most terminals does, and `@screenshot.png` in a message
attaches the file when you send it.

Each attached image shows as `[image #1]` on the input line, and deleting the
marker drops the image. uji takes PNG, JPEG, GIF and WebP files. It turns
photos upright and scales images down to 1568 pixels on their long side, then
to a smaller size or JPEG when they would still pass 5 MB.

A request carries the 20 newest images of the conversation, and a note takes
the place of older ones. A model that takes no images gets the text with the
same kind of note. uji knows this for most built-in models, and learns it for
others the first time a model refuses a request with images.

The model can open images on its own as well. `read_file` on a PNG, JPEG, GIF
or WebP file in the working directory gives it the image.

uji saves every conversation as a session.
[Commands](commands.md#running-uji) shows how to go back to one.


# Getting started

This chapter installs uji, signs you in to a provider, and lists the commands
and keys you use while you work.


# Installation

On macOS and Linux, install uji with Homebrew:

```sh
brew install uji-labs/uji/uji
```

`brew upgrade uji` moves to a newer release. Macs with Apple silicon and
64-bit Intel Linux get a ready-made build. On other machines Homebrew builds
uji from source, which takes a few minutes.

## With Cargo

```sh
cargo install --git https://github.com/uji-labs/uji --locked uji
```

The build needs Rust 1.88 or newer, a C compiler and `make`. Cargo puts the
`uji` binary in `~/.cargo/bin`, and `uji --version` prints the version once
your shell finds it.

From a clone of the repository, run `cargo install --path crates/uji --locked`
in its top folder instead. Adding `--force` to either command replaces an
installed uji with a newer one.


# Running a prompt without the screen

`uji run` sends one prompt, lets the model work until it answers, prints the
answer and exits. Scripts and other programs use it, and so do the agents of
the [subagent](../plugins/subagent.md) plugin. It reads the same config,
plugins and packs as uji does on the screen, and saves the conversation as a
session.

```sh
uji run "Summarise what changed in the last commit"
```

The words after the options form the prompt. The exit code is `0` when the
model answers and `1` when the turn fails, with the reason on standard error.

| Option | Does |
|---|---|
| `--json` | Prints every event as a line of JSON instead of the answer alone. |
| `--model <PROVIDER/ID>` | Uses this model instead of the one you picked with `/models`. |
| `--effort <LEVEL>` | Uses this reasoning effort: `off`, `minimal`, `low`, `medium`, `high`, `xhigh` or `max`. uji uses the nearest level the model accepts. |
| `--tools <A,B>` | Offers the model only these tools, separated by commas. |
| `--append-prompt <TEXT>` | Adds the text to the end of the system prompt. |
| `--title <TEXT>` | Titles the session. The default is the first line of the prompt. |
| `--parent <ID>` | Saves the session under another one. `uji list` leaves it out, and `uji resume --id` opens it. |

Nobody can answer an approval question here, so a call your
[policy](../api/tool.md#ujitoolpolicyrules) would ask about runs without
asking. Calls your policy denies stay denied.

The options `--config-dir`, `--data-dir` and `--db` work as they do for the
other commands.

## JSON events

With `--json`, each line is one event.

| `type` | Fields | When |
|---|---|---|
| `session` | `id` | First, with the id of the new session. |
| `message` | `message` | A message joined the conversation, in the form uji saves it. |
| `progress` | `tool`, `line` | A running tool printed a line. |
| `notice` | `text` | uji has something to tell you, such as a plugin error. |
| `done` | `text` or `error`, and `usage` | Last. `usage` has `input`, `output`, `cache_read` and `cache_write` tokens for the whole run. |

```sh
uji run --json --tools read_file "What does src/main.rs do?" | jq -r 'select(.type == "done") | .text'
```


<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/readme-header-dark.png">
  <img src="images/readme-header-light.png" width="640" alt="uji. A coding agent you can shape with Lua.">
</picture>

# Introduction

uji is a coding agent for your terminal, configured in Lua. This is a
complete `~/.config/uji/init.lua`:

```lua
require("uji.builtin.defaults")

uji.pack.add({ "uji-labs/uji-plugins" })
require("statusline").setup({})
require("planmode").setup({})

uji.tool.policy({
  run_command = { allow = { "git status", "cargo test*" } },
})

uji.keymap.add("normal", "<C-p>", { command = "models" })

uji.command.add("standup", function()
  uji.session.submit("Summarise the commits since yesterday.")
end)
```

- [Getting started](getting-started/index.md) installs uji and signs you in.
- [Configuration](configuration/index.md) shows where your config goes.
- [Plugins](plugins/index.md) lists the plugins and their options.
- [Examples](examples/index.md) build tools, commands, a footer, providers and approval rules.
- [Rebuilding uji](rebuilding/index.md) replaces any part of uji with your own Lua.
- [API reference](api/index.md) lists every `uji.*` function.
- [Runtime](runtime/index.md) covers tasks, the network, processes, storage and the system.


# Plugins

The [uji-plugins](https://github.com/uji-labs/uji-plugins) pack holds
optional features. Install it once, then call `setup` for each plugin you
want.

```lua
uji.pack.add({ "uji-labs/uji-plugins" })
```


# mcp

Tools from MCP servers, over stdio or HTTP.

```lua
require("mcp").setup({
  servers = {
    files = { cmd = { "npx", "-y", "@modelcontextprotocol/server-filesystem", "." } },
    linear = { url = "https://mcp.linear.app/mcp" },
  },
})
```

A server has `cmd` and optional `cwd`, or `url` and optional `token`. Its
tools are named `server__tool`, and each call asks you first unless your
[policy](../api/tool.md#ujitoolpolicyrules) allows it. `/mcp add URL` connects a
server and signs you in when it asks, `/mcp remove` disconnects one, and
`/mcp` lists them.


# planmode

A read-only mode. The model investigates and writes a plan, then you accept
it, keep planning, or leave.

```lua
require("planmode").setup({ allow = { "npm test" } })
```

| Option | Meaning | Default |
|---|---|---|
| `allow` | Command prefixes that run without asking while planning. | none |
| `confirm` | `false` skips the accept picker at the end of a turn. | `true` |
| `keys` | `false` leaves Ctrl+B unbound. | `true` |
| `priority` | The priority of its `before_tool` hook. | `10` |

Commands are `/plan`, `/plan <task>` and `/approve`. Ctrl+B toggles plan mode.


# readonly

Refuses edits in the directories you list, so the model can read them but not
change them.

```lua
uji.tool.roots({ "~/reference/other-project" })
require("readonly").setup({ "~/reference/other-project" })
```


# skills

Announces Agent Skills folders to the model.

```lua
require("skills").setup({ roots = { "~/.agents/skills", ".agents/skills" } })
```

`roots` defaults to `~/.agents/skills`, `.uji/skills` and `.agents/skills`.
`/skills` lists what it found.


# statusline

Status lines built from segments. By default it draws one line below the input
with the directory, model, reasoning effort, context use, tokens, cache hit
rate and turns.

```lua
require("statusline").setup({})
```

| Option | Meaning | Default |
|---|---|---|
| `lines` | The lines to draw. See below. | one line below the input with every segment |
| `logo` | `true` shows the uji logo while the session is empty. A table `{ lines = { ... }, color = "#f9e2af" }` shows your own. | `false` |
| `defaults` | `false` registers none of the built-in segments. | `true` |
| `separator` | Text between segments. | `"  ·  "` |

## Segments

A segment is a function registered with
[`uji.status.add`](../api/status.md#ujistatusaddname-render-opts). The built-in
ones are `cwd`, `model`, `effort`, `context`, `tokens`, `cache` and `turns`.
Adding a segment with one of these names after `setup` replaces it.

## Lines

Each line has these fields.

| Field | Meaning |
|---|---|
| `at` | `"top"` above the conversation, `"above"` just above the input, or `"below"` under it. The default is `"below"`. Lines at the same place stack in the order you list them. |
| `left`, `center`, `right` | The names of the segments on each side. `"*"` stands for every segment that no line names, so segments from other plugins still show. |
| `priority` | The layout priority of the line's window, when the place's default is not what you want. |

This setup puts the model and effort above the input, the directory and
context use below it, and the logo on an empty session.

```lua
require("statusline").setup({
  logo = true,
  lines = {
    { at = "above", left = { "model" }, right = { "effort" } },
    { at = "below", left = { "cwd", "*" }, right = { "context" } },
  },
})

uji.status.add("model", function()
  local provider = uji.status.provider()
  return provider and { text = uji.status.model() .. " · " .. provider, bold = true }
end)

uji.status.add("effort", function()
  local effort = uji.status.effort()
  return effort and { text = "effort " .. effort, color = "yellow", bold = true }
end)
```


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


# telescope

A fuzzy finder.

```lua
require("telescope").setup({})
```

| Key | Command | Does |
|---|---|---|
| Ctrl+P | `/find` | Opens a file in your editor. |
| Ctrl+A | `/attach` | Adds `@path` to the input line. |
| Ctrl+G | `/branch` | Asks the model about a git branch. |
| Ctrl+R | `/history` | Refills the input with a past message. |
| Ctrl+F | | Searches file contents as you type. |
| | `/grep <pattern>` | Opens a matching file. |

`editor` sets the program that opens files. It defaults to `UJI_EDITOR`, then
`VISUAL`, then `EDITOR`. `keys = false` leaves the keys unbound.


# websearch

`web_search` and `web_fetch` tools. Both go through Exa's public search
service, so they need no key.

```lua
require("websearch").setup({ count = 8 })
```

| Option | Meaning | Default |
|---|---|---|
| `policy` | Whether the tools ask before they run: `"allow"`, `"ask"` or `"deny"`. | `"allow"` |
| `count` | Results per search. | `5` |
| `chars` | Characters of a page that `web_fetch` returns at most. | `20000` |
| `timeout` | Seconds per request. | `30` |


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


# Replacing everything

Copy the whole `lua/uji` folder of the uji source into
`~/.config/uji/lua/uji`. Every module then comes from your copy. A file you
delete from your copy falls back to the built-in one.

To run a complete tree kept somewhere else, set `UJI_RUNTIME` to the directory
that contains its `uji` folder. uji then uses none of its built-in files, and
replacements in your config and packs still apply on top.

Such a tree needs one module. `uji.boot` returns the function that uji runs
with the command line as the first task. uji stops when no task is left, or
after `uji.os.exit` or `uji.os.restart`. The modules built into uji stay
available to the tree, such as `require("uji.sys.fs")`, and
[Native modules](../runtime/native.md#replacing-a-built-in-module) describes
how to replace them.


# Rebuilding uji

Everything uji does, from startup to the screen, is written in Lua in the
`uji` module tree, and you can replace any file in it. A file at
`lua/uji/<path>.lua` in your config directory or in a pack replaces the
built-in module `uji.<path>`. A module that is a folder, such as
`uji.core.agent`, lives in `lua/uji/core/agent/init.lua`.

A replacement is a whole file. uji loads yours instead of the built-in one, so
the easiest start is a copy of the original from the `lua/uji` folder of the
uji source.

For example, `~/.config/uji/lua/uji/core/prompt.lua`:

```lua
local M = {}

function M.system(env)
  return "You are a careful coding agent. Work in " .. env.directory .. "."
end

return M
```


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
| `core/ui/` | Draws the screen, with its layout, windows, input line, markdown, keys and theme. |
| `core/ui/views/` | The transcript, the input line, pickers, prompts and the approval question. |
| `core/images.lua` | Attaching images from files, pasted paths and the clipboard. |
| `core/event.lua`, `core/task.lua`, `core/plugin.lua`, `core/registry.lua`, `core/class.lua` | Events, tasks, plugin ownership and the building blocks the rest is made of. |
| `builtin/providers/` | The providers `/login` lists, each with the API it speaks and its own changes to it. |
| `builtin/apis/` | The Chat Completions, Responses, Anthropic and Gemini API classes, and the streaming they share. |
| `builtin/tools/` | `read_file`, `edit_file`, `write_file` and `run_command`. |
| `builtin/commands/` | The built-in slash commands, one file each. |
| `builtin/defaults.lua` | The default screen and bindings that `require("uji.builtin.defaults")` loads. |
| `sys/` | `require("uji.sys")`, a table with a field for each [Runtime](../runtime/index.md) module, such as `fs` or `json`. A field loads its module, `uji.sys.fs` or `uji.sys.json`, the first time it is read. `uji.*` falls back to the same fields for anything `api/` does not define. |

The Runtime modules are built into the uji program, and a module with the same
name replaces any of them, as
[Native modules](../runtime/native.md#replacing-a-built-in-module) describes.
Everything built on them, `sys/` included, can be replaced too.


# If a replacement breaks uji

When uji cannot start, it prints the error and the file it came from. Fix or
remove that file, or start uji with `--config-dir` pointing at another
directory.


# When a replacement takes effect

A replacement is used from the first file uji loads, `boot.lua` included. The
first time a pack that replaces modules is added, uji starts over once while it
starts up, so that the pack's files are used from the beginning. It remembers
those packs for later starts.

`/reload` and `/sync` restart uji with your current files. The
conversation, what you are typing and the screen stay as they are. A turn in
progress has to finish, or be interrupted with Esc, before a reload. Processes
that plugins started, such as MCP servers, are started again.


# Encoding

| Function | Gives |
|---|---|
| `uji.base64.encode(data, opts)` | `data` in base64. `opts.url = true` uses the URL alphabet and `opts.pad = false` leaves out padding. |
| `uji.base64.decode(text, opts)` | The decoded bytes. It takes the same options and raises an error for text that is not base64. |
| `uji.sha256(data)` | The SHA-256 digest of `data`, as 32 raw bytes. |
| `uji.random(count)` | `count` random bytes. |
| `uji.toml.decode(text)` | A table with the values in the TOML document `text`. It raises an error for text that is not valid TOML. |
| `uji.toml.encode(table)` | `table` written as a TOML document. It raises an error for a value TOML cannot hold, such as a list at the top. |


# Images

## uji.image.fit(data, edge, bytes)

Checks that `data` holds a PNG, JPEG, GIF or WebP image and returns it ready to
send. A photo with an EXIF orientation is turned upright, and an image whose
long side passes `edge` pixels is scaled down. When the result is still larger
than `bytes`, it is saved as JPEG at lower quality, and then at half the size
until it fits.

The result is a table with four fields. `data` holds the image encoded as
base64, `media_type` names its type such as `"image/png"`, and `width` and
`height` give its size in pixels. An image that needs no change keeps its
original bytes. Anything else gives `nil` and an error message.

```lua
local image = uji.image.fit(uji.fs.read("shot.png"), 1568, 3 * 1024 * 1024)
```


# Runtime

A plugin uses these functions to run work in the background, talk to the
network, start processes, keep data in SQLite and read the system.


# Native modules

A native module is a shared library that Lua loads with `require`. uji looks
for it in `native/` in the [config directory](../configuration/files.md) and
in every [pack](../configuration/packs.md). `require("name")` finds
`name.dylib` on macOS and `name.so` on Linux. A dotted name looks in folders,
so `require("tools.fast")` finds `native/tools/fast.dylib`. Native modules
work on macOS and Linux only.

The library is a Lua C module for LuaJIT. It exports a function named
`luaopen_` followed by the module name, with each dot written as an
underscore, and whatever that function returns is the module. A module can be
written in any language that can export such a function, such as C, Zig or
Rust.

The library does not link LuaJIT itself. It uses the LuaJIT inside uji, which
on macOS needs the linker flag `-undefined dynamic_lookup`.

A native function runs while every task waits, so a slow one holds up the
screen until it returns.

## Loading

uji loads a library the first time `require` asks for it, and keeps it until
uji restarts. After you rebuild a library, `/reload` loads the new
one.

## Errors

An error raised inside a native function, such as an argument of the wrong
type, reaches Lua like any other error. `pcall` catches it, and
`uji.message(err)` gives its text without a stack trace.

```lua
local ok, err = pcall(require("loadavg").get)
if not ok then
    uji.notify(uji.message(err))
end
```

## Writing one in C

The module needs LuaJIT's headers, for example from `brew install luajit` or a
`libluajit-5.1-dev` package. This one gives a status segment the system's load
average.

```c
#include <stdlib.h>
#include <lua.h>
#include <lauxlib.h>

static int get(lua_State *L) {
    double average;
    if (getloadavg(&average, 1) != 1) {
        return luaL_error(L, "the load average is not available");
    }
    lua_pushnumber(L, average);
    return 1;
}

int luaopen_loadavg(lua_State *L) {
    lua_newtable(L);
    lua_pushcfunction(L, get);
    lua_setfield(L, -2, "get");
    return 1;
}
```

On macOS:

```sh
cc -shared -undefined dynamic_lookup -I"$(brew --prefix luajit)/include/luajit-2.1" -o loadavg.dylib loadavg.c
mkdir -p ~/.config/uji/native && cp loadavg.dylib ~/.config/uji/native/
```

On Linux:

```sh
cc -shared -fPIC -I/usr/include/luajit-2.1 -o loadavg.so loadavg.c
mkdir -p ~/.config/uji/native && cp loadavg.so ~/.config/uji/native/
```

```lua
uji.status.add("load", function()
  return { text = string.format("load %.2f", require("loadavg").get()), color = "gray" }
end)
```

## Writing one in Rust

A Rust module is a crate with `crate-type = ["cdylib"]` that depends on mlua
with the `luajit52` and `module` features. `#[mlua::lua_module]` on a function
that takes `&Lua` and returns the module exports it as `luaopen_` followed by
the function's name, and `#[mlua::lua_module(name = "tools_fast")]` exports it
under the name you give instead. This one gives the number of CPU cores, which
sizes how many subagents run at once.

`Cargo.toml`:

```toml
[package]
name = "cpus"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]

[dependencies]
mlua = { version = "0.12", features = ["luajit52", "module"] }
```

`build.rs`, which passes the macOS linker flag:

```rust
fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        println!("cargo::rustc-cdylib-link-arg=-undefined");
        println!("cargo::rustc-cdylib-link-arg=dynamic_lookup");
    }
}
```

`src/lib.rs`:

```rust
use mlua::prelude::*;

#[mlua::lua_module]
fn cpus(lua: &Lua) -> LuaResult<LuaTable> {
    let module = lua.create_table()?;
    module.set(
        "count",
        lua.create_function(|_, ()| {
            Ok(std::thread::available_parallelism().map_or(1, std::num::NonZero::get))
        })?,
    )?;
    Ok(module)
}
```

Build it and copy the library under the module's name, `cpus.dylib` on macOS
or `cpus.so` on Linux:

```sh
cargo build --release
cp target/release/libcpus.dylib ~/.config/uji/native/cpus.dylib
```

```lua
require("subagent").setup({ concurrency = require("cpus").count() })
```

## Replacing a built-in module

Every part of the [Runtime](index.md) is a module named `uji.sys.` followed by
its name. `require` looks in these places, in order, and uses the first module
it finds:

1. Lua in your config and packs, such as `~/.config/uji/lua/uji/sys/fs.lua`.
2. The Lua that comes with uji.
3. Native modules in `native/` in your config and packs, such as
   `native/uji/sys/fs.dylib`, which exports `luaopen_uji_sys_fs`.
4. The modules built into uji.

A module you provide under one of these names replaces the built-in one, and
everything in uji that uses it uses yours. The other modules stay built in.

| Module | What it is |
|---|---|
| `uji.sys.task` | `spawn`, `race`, `timeout` and `on_error`, in [Tasks](tasks.md). |
| `uji.sys.sleep` | The `sleep` function, in [Tasks](tasks.md). |
| `uji.sys.promise` | The `promise` function, in [Tasks](tasks.md). |
| `uji.sys.fs` | Files and folders, in [uji.fs](../api/fs.md). |
| `uji.sys.net` | Requests and the local server, in [Network](network.md). |
| `uji.sys.proc` | Processes, in [Processes](processes.md). |
| `uji.sys.db` | SQLite databases, in [Storage](storage.md). |
| `uji.sys.os` | The system and restarting, in [System](system.md). |
| `uji.sys.keychain` | The keychain, in [System](system.md). |
| `uji.sys.clipboard` | The clipboard, in [System](system.md). |
| `uji.sys.modules` | The `modules` function, in [System](system.md). |
| `uji.sys.message` | The `message` function, in [System](system.md). |
| `uji.sys.json` | JSON, in [uji.json](../api/json.md). |
| `uji.sys.toml` | TOML, in [Encoding](encoding.md). |
| `uji.sys.base64` | Base64, in [Encoding](encoding.md). |
| `uji.sys.sha256` | The `sha256` function, in [Encoding](encoding.md). |
| `uji.sys.random` | The `random` function, in [Encoding](encoding.md). |
| `uji.sys.regex` | The `regex` function, in [Text](text.md). |
| `uji.sys.glob` | The `glob` function, in [Text](text.md). |
| `uji.sys.fuzzy` | The `fuzzy` function, in [Text](text.md). |
| `uji.sys.width` | The `width` function, in [Text](text.md). |
| `uji.sys.lossy` | The `lossy` function, in [Text](text.md). |
| `uji.sys.markdown` | The `markdown` function, in [Text](text.md). |
| `uji.sys.image` | Image fitting, in [Images](images.md). |
| `uji.sys.tty` | The screen and its input, in [Terminal](terminal.md). |

This file at `~/.config/uji/lua/uji/sys/width.lua` counts every character as
one column. `/reload` puts it to use.

```lua
return function(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end
```


# Network

Each call here waits inside the current [task](tasks.md), so the rest of uji
keeps drawing and taking keys meanwhile.

## uji.net.request(opts)

Sends an HTTP request and waits for the answer, a table with `status`,
`headers` and `body`. When no answer comes back the result is `nil` and an
error message. An error status still counts as an answer.

| Option | Type | Meaning |
|---|---|---|
| `url` | string | The address. Required. |
| `method` | string | The method. The default is `"GET"`. |
| `headers` | table | Header names and values. |
| `body` | string | The request body. |
| `timeout` | number | Seconds to wait for the whole answer. |

## uji.net.open(opts)

Sends a request like `uji.net.request`, but hands back a response object as
soon as the headers arrive, so the body can be read while it streams. It takes
the same options plus `idle`, the seconds without data after which reading
fails, 120 by default. A failed request gives `nil` and an error message.

| Member | Meaning |
|---|---|
| `response.status` | The status code. |
| `response.headers` | Header names and values. |
| `response:line(seconds)` | The next line, `nil` at the end of the body, or `false` if `seconds` pass first. Without `seconds` it waits as long as the line takes. |
| `response:lines()` | An iterator over the remaining lines, for a `for` loop. |
| `response:read()` | Everything left in the body, once it has arrived. |

## uji.net.listen(port)

Listens on `port` on the local machine, or on a free port when `port` is `0`.
The result is a server, or `nil` and an error message.

| Member | Meaning |
|---|---|
| `server.port` | The port it listens on. |
| `server:accept()` | The next connection, or `nil` and an error message once the server is closed. |
| `server:close()` | Stops listening. |
| `conn:line(seconds)` | The next line, `nil` when the other side closes, or `false` if `seconds` pass first. Without `seconds` it waits as long as the line takes. |
| `conn:read(count)` | Exactly `count` bytes. |
| `conn:write(data)` | Sends `data`. |
| `conn:close()` | Closes the connection. |


# Processes

## uji.proc.spawn(argv, opts)

Starts the program named by the first item of the list `argv`, with the rest
as its arguments. The result is a process, or `nil` and an error message. The
process is killed when nothing refers to it any more.

| Option | Type | Meaning |
|---|---|---|
| `cwd` | string | The directory to run in. |
| `env` | table | Extra environment variables. |
| `stdio` | string | `"pipe"`, the default, to read and write the process, or `"inherit"` to give it the terminal. |

| Member | Meaning |
|---|---|
| `proc.pid` | The process id. |
| `proc:line()` | The next line of output with `"stdout"` or `"stderr"`, or `nil` once both streams end. |
| `proc:lines()` | An iterator over the remaining lines and their streams. |
| `proc:write(data)` | Writes `data` to the process's input. |
| `proc:close()` | Closes the process's input. |
| `proc:kill()` | Kills the process. |
| `proc:wait()` | Waits for the process to exit and gives a table with `code`, `signal` and `success`. |


# Storage

## uji.db.open(path)

Opens or creates the SQLite database at `path`. The result is a database, or
`nil` and an error message. Parameters are a list that fills the `?` marks in
the statement, and `uji.db.null` stands for `NULL` in that list. A statement
that SQLite rejects raises an error, in every method below.

| Member | Meaning |
|---|---|
| `db:exec(sql, params)` | Runs a statement and gives the number of rows it changed. Without `params`, `sql` may hold several statements. |
| `db:query(sql, params)` | The rows, as a list of tables keyed by column name. |
| `db:transaction(fn)` | Runs `fn` in a transaction and gives back what it returns. An error inside `fn` rolls the transaction back and raises again. `fn` cannot wait, so no other task can write in the middle of the transaction. |
| `db:close()` | Closes the database. |


# System

These describe the machine and the current run, and give access to saved
passwords and to what you last copied.

| Function | Gives |
|---|---|
| `uji.os.platform` | `"macos"`, `"linux"`, `"windows"` or `"other"`. |
| `uji.os.env(name)` | The value of an environment variable, or `nil` when it is unset or empty. |
| `uji.os.cwd()` | The directory uji started in. |
| `uji.os.home()` | Your home directory, or `nil`. |
| `uji.os.now()` | The time in milliseconds since the Unix epoch. |
| `uji.os.clock()` | Seconds since uji started, for measuring how long something took. |
| `uji.os.executable` | The path of the program running uji, or `nil` when the system cannot tell. |
| `uji.os.argv` | The arguments uji started with, the program name first. |
| `uji.os.roots` | The directories whose `lua/` and `native/` folders are searched before the built-in modules. |
| `uji.os.carry` | The text handed over by the last `uji.os.restart`, or `nil`. |
| `uji.os.library` | The file extension of a native module on this system, `"dylib"` or `"so"`. |
| `uji.message(err)` | The text of an error caught with `pcall`, without the stack trace that errors from the runtime carry. |

## uji.os.restart(opts)

Restarts uji once the current code waits, keeping the screen.
Every task, connection and process from this run stops. `opts.args` is the
command line for the new run, `opts.roots` sets `uji.os.roots` for it, and
`opts.carry` is text it can read from `uji.os.carry`.

## uji.modules(namespace)

Lists the modules directly inside `namespace`, such as `"uji.builtin.commands"`, as
full names in alphabetical order. It looks in the `lua/` folder of every
directory in `uji.os.roots` and in the built-in modules. A folder with an
`init.lua` counts as one module.

## uji.keychain.get(service, account)

Looks up the secret saved in the system keychain for `service` and `account`,
and gives `nil` when there is none.

## uji.keychain.set(service, account, secret)

Saves `secret` in the system keychain, then gives `true`, or `nil` and an
error message.

## uji.keychain.delete(service, account)

Removes the secret, with the same result as `uji.keychain.set`.

## uji.clipboard.get()

Reads the text on the system clipboard, or gives `nil` and an error message.

## uji.clipboard.set(text)

Puts `text` on the system clipboard and gives `true`, or `nil` and an error
message.

## uji.clipboard.image(edge, bytes)

Takes the image on the system clipboard and fits it the way
[`uji.image.fit`](images.md#ujiimagefitdata-edge-bytes) does, and gives the
same table. A clipboard without an image gives `nil` and "the clipboard has
no image".


# Tasks

Your config, slash commands, key bindings, actions, tool functions and the
timers from `uji.schedule` and `uji.defer` run as tasks. Any of them can wait
on the network, a process, the keychain or a timer while the screen keeps
working.

One task runs at a time, until it waits, so a loop that never waits holds up
the screen and every other task. Waiting outside a task raises an error, and a
coroutine you create yourself cannot wait.

## uji.task.spawn(fn, ...)

Starts `fn` as a new task with the arguments that follow, and returns a task
object. It begins once the current task waits. Errors show as notices.

## task:cancel()

Stops the task where it waits, together with the functions that
`uji.task.race` and `uji.task.timeout` run for it. What it was waiting on stops
too, and uji closes the connections and processes that only this task used. A
task that cancels itself stops at its next wait.

## uji.sleep(seconds)

Pauses the task for `seconds`. Fractions work. With `0` the task pauses only
long enough for every other task that is ready to run first, which is how a
long loop can give the screen and the rest of uji their turn. With `math.huge`
it waits until it is cancelled. Anything other than a number of seconds raises
an error.

## uji.task.race(fn, ...)

Runs every function at once inside the current task, and waits for the first
to finish. The result is its position followed by what it
returned, and the others stop there. An error in the first to finish is raised
again, and cancelling the current task stops all of them.

## uji.task.timeout(seconds, fn)

Runs `fn` inside the current task for at most `seconds`, where `math.huge`
means no limit.
When `fn` finishes in time the result is `true` followed by what it returned.
Otherwise `fn` stops and the result is `false`.

## uji.promise()

Creates a promise. Tasks wait on it until another task settles it.

| Member | Meaning |
|---|---|
| `promise:resolve(...)` | Settles the promise with the values given, and wakes every task waiting on it. The result is `true` the first time and `false` after. |
| `promise:await()` | Waits until the promise is settled and gives back its values. A settled promise gives them back at once. |
| `promise.settled` | `true` once the promise is settled. |


# Terminal

## uji.tty.open()

Opens the terminal and gives two values: the screen and its input. Every call
gives the same two, and they stay open across `/reload`. This is the terminal
uji draws its own screen on, so anything else drawn on it is replaced at uji's
next frame. It is mainly for a tree that
[replaces everything](../rebuilding/everything.md).

Rows and columns count from 0 at the top left. Drawing only changes the screen
in memory, and `screen:flush()` shows the changes. A position outside the
screen draws nothing.

```lua
local tty = require("uji.sys.tty")

return function()
    local screen, input = tty.open()
    local title = screen:style({ fg = "cyan", bold = true })
    local width, height = screen:size()
    screen:clear()
    screen:line(0, 0, { { "hello ", title }, "from uji" })
    screen:line(1, 0, "the screen is " .. width .. " by " .. height)
    screen:line(2, 0, "press q to quit")
    screen:cursor(3, 0, "bar")
    screen:flush()
    for event in input:events() do
        if event.type == "key" and event.key == "q" then
            break
        end
        screen:line(3, 0, "you pressed " .. (event.key or event.type) .. "      ")
        screen:flush()
    end
    screen:close()
end
```

## The screen

| Member | Meaning |
|---|---|
| `screen:size()` | The width and the height, in columns and rows. |
| `screen:style(spec)` | Makes a style and gives its number, for use in spans, `fill` and `paint`. Style `0` is the terminal's default. |
| `screen:line(row, col, spans, width)` | Draws `spans` from `row` and `col`, and gives the column after the last character. `spans` is a string, or a list whose items are strings or `{ text, style }` pairs. `width` stops the text after that many columns. |
| `screen:fill(row, col, width, height, style, symbol)` | Fills the area with `symbol`, a space when it is left out, in `style`. |
| `screen:paint(row, col, width, height, style)` | Sets the style of the area and keeps its text. |
| `screen:text(row)` | The text on `row`, or `nil` outside the screen. |
| `screen:clear()` | Empties the whole screen. |
| `screen:cursor(row, col, shape)` | Shows the cursor at the position, as `"block"`, the default, `"bar"` or `"underline"`. With no position it hides the cursor. |
| `screen:flush()` | Shows what changed since the last flush, and puts the cursor in place. |
| `screen:write(bytes)` | Sends `bytes` to the terminal as they are. |
| `screen:suspend()` | Gives the terminal back, for a program that needs it. |
| `screen:resume()` | Takes the terminal again and clears it, ready for the next flush. |
| `screen:close()` | Gives the terminal back for good. |

A style spec has these fields, and each one can be left out.

| Field | Type | Meaning |
|---|---|---|
| `fg` | string | The text colour. |
| `bg` | string | The background colour. |
| `bold`, `dim`, `italic`, `underline`, `blink`, `reverse`, `strikethrough` | boolean | Turns the attribute on. |

A colour is a name, a number from `0` to `255`, or `"#rrggbb"`. The names are
`black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `gray`,
`darkgray`, `lightred`, `lightgreen`, `lightyellow`, `lightblue`,
`lightmagenta`, `lightcyan`, `white` and `reset`.

A span that is neither a string nor a pair, a colour that is not one of these,
an unknown cursor shape, and a style number that `style` never gave all raise
an error.

## The input

| Member | Meaning |
|---|---|
| `input:event()` | Waits for the next event and gives it as a table. |
| `input:events()` | An iterator over the events, for a `for` loop. |

Each event has a `type` field.

| `type` | Fields |
|---|---|
| `"key"` | `key`, and `ctrl`, `alt`, `shift`, `meta` and `repeat` as booleans. |
| `"mouse"` | `kind`, `button`, `row`, `col`, and `ctrl`, `alt` and `shift` as booleans. |
| `"paste"` | `text`, the pasted text. |
| `"resize"` | `width` and `height`, the new size. |
| `"focus"` | `focused`, `true` when the terminal gains focus and `false` when it loses it. |

`key` is the character typed, such as `"a"` or `"A"`, or one of `"enter"`,
`"esc"`, `"backspace"`, `"delete"`, `"tab"`, `"backtab"`, `"left"`, `"right"`,
`"up"`, `"down"`, `"home"`, `"end"`, `"pageup"`, `"pagedown"`, `"insert"` and
`"f1"` to `"f12"`.

A mouse `kind` is `"down"`, `"up"`, `"drag"`, `"move"`, `"scroll_up"`,
`"scroll_down"`, `"scroll_left"` or `"scroll_right"`. `button` is `"left"`,
`"right"` or `"middle"` for presses, releases and drags, and `nil` otherwise.


# Text

## uji.regex(pattern)

Compiles a regular expression into a matcher, or gives `nil` and an error
message.

## uji.glob(pattern, opts)

Compiles a glob such as `*.rs` into a matcher, or gives `nil` and an error
message. With `opts.separator = true`, `*` does not match `/`.

| Member | Meaning |
|---|---|
| `matcher:test(text)` | `true` when the pattern matches somewhere in `text`. |
| `matcher:find(text)` | The start and end positions of the first match, or `nil`. |

## uji.fuzzy(query, items)

Ranks the list of strings `items` against `query` the way the pickers do, as
positions in `items` with the best match first. An empty query gives every
position in order.

## uji.markdown(source)

Parses Markdown into a list of events. Each event is itself a list that starts
with its kind, one of `"start"`, `"end"`, `"text"`, `"code"`, `"html"`,
`"math"`, `"break"`, `"rule"` and `"task"`. The details of that event come next,
then its start and end byte positions in `source`.

Math between `$` and `$`, or `\(` and `\)`, gives a `"math"` event with its TeX
source and `false`. Math between `$$` and `$$`, or `\[` and `\]`, gives one with
`true`.

## uji.width(text)

Counts the terminal columns `text` takes.

## uji.lossy(data)

Turns `data` into valid UTF-8, replacing each invalid byte sequence with
U+FFFD.


# Summary

[Introduction](introduction.md)

- [Getting started](getting-started/index.md)
  - [Installation](getting-started/install.md)
  - [First run](getting-started/first-run.md)
  - [Commands](getting-started/commands.md)
  - [Running without the screen](getting-started/run.md)
- [Configuration](configuration/index.md)
  - [Where uji keeps its files](configuration/files.md)
  - [Packs](configuration/packs.md)
- [Plugins](plugins/index.md)
  - [statusline](plugins/statusline.md)
  - [planmode](plugins/planmode.md)
  - [mcp](plugins/mcp.md)
  - [telescope](plugins/telescope.md)
  - [skills](plugins/skills.md)
  - [websearch](plugins/websearch.md)
  - [subagent](plugins/subagent.md)
  - [readonly](plugins/readonly.md)
- [Examples](examples/index.md)
  - [A tool of your own](examples/tool.md)
  - [A slash command](examples/command.md)
  - [A footer](examples/footer.md)
  - [A provider](examples/provider.md)
  - [An approval rule](examples/approval.md)
  - [The system prompt](examples/prompt.md)
- [Rebuilding uji](rebuilding/index.md)
  - [Where things live](rebuilding/modules.md)
  - [Adding a module](rebuilding/adding.md)
  - [When a replacement takes effect](rebuilding/reload.md)
  - [Replacing everything](rebuilding/everything.md)
  - [If a replacement breaks uji](rebuilding/recovery.md)
- [API reference](api/index.md)
  - [uji.tool](api/tool.md)
  - [uji.command](api/command.md)
  - [uji.keymap](api/keymap.md)
  - [uji.action](api/action.md)
  - [uji.ui](api/ui.md)
  - [uji.status](api/status.md)
  - [uji.context](api/context.md)
  - [Events](api/events.md)
  - [uji.session](api/session.md)
  - [uji.input](api/input.md)
  - [uji.model](api/model.md)
  - [uji.provider](api/provider.md)
  - [uji.auth](api/auth.md)
  - [Provider APIs](api/apis.md)
  - [uji.job](api/job.md)
  - [uji.http](api/http.md)
  - [uji.fs](api/fs.md)
  - [uji.json](api/json.md)
  - [uji.pack](api/pack.md)
  - [uji.config](api/config.md)
  - [Timers and notices](api/timers.md)
  - [Quitting and reloading](api/app.md)
- [Runtime](runtime/index.md)
  - [Tasks](runtime/tasks.md)
  - [Network](runtime/network.md)
  - [Processes](runtime/processes.md)
  - [Storage](runtime/storage.md)
  - [System](runtime/system.md)
  - [Text](runtime/text.md)
  - [Encoding](runtime/encoding.md)
  - [Images](runtime/images.md)
  - [Terminal](runtime/terminal.md)
  - [Native modules](runtime/native.md)


