# Events

Handlers run lowest priority first. For the events under
[Hooks](#hooks), uji uses what the handlers return.

```lua
uji.on("tool_started", function(event)
  uji.notify("running " .. event.name)
end)
```

Every payload also has an `event` field that holds the event's name.

### uji.on(event, handler, opts)

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

### uji.off(event, name)

Removes the handler with that name and returns `true` if it existed.

```lua
local name = uji.on("turn_finished", function() end)
uji.off("turn_finished", name)
```

### uji.emit(event, payload)

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
