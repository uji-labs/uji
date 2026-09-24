# uji.wire

A wire turns uji's request into an HTTP call to one kind of API and streams
the answer back. uji ships three: `openai-chat`, `anthropic` and `gemini`.
They are Lua modules in `uji.wires`, and the easiest way to write a new wire
is to copy one of them.

### uji.wire.add(name, spec)

Registers a wire, or replaces the wire with the same name. `spec.stream` is a
function that receives a request and a reply table. It may return a function
that cancels the call.

The request has these fields:
- `model`, the model id
- `system`, the system prompt
- `messages`, the conversation in uji's message format
- `tools`, a list of `name`, `description` and `parameters`
- `effort`, one of `off`, `minimal`, `low`, `medium` and `high`
- `max_output`, the output token limit
- `cache`, one of `off`, `short` and `long`
- `session`, the session id
- `provider`, with `id`, `base_url` and `compat`
- `auth`, with `key`, and `oauth` for subscription sign-in

The reply table has four functions:
- `reply.text(delta)` streams answer text.
- `reply.reasoning(delta)` streams reasoning text.
- `reply.done(answer)` finishes the call. `answer` has `text`, and optionally
  `reasoning`, `tool_calls` and `usage`. Each tool call has `id`, `name` and
  `arguments`, where `arguments` is a JSON string. `usage` has `input`,
  `output`, `cache_read` and `cache_write`.
- `reply.fail(failure)` ends the call with an error. `failure.kind` is
  `"http"`, with `status`, `message` and `retry_after`, or `"auth"`, with
  `status`, or `"provider"`, with `message`. uji retries `http` failures with a
  status of 408, 409, 425, 429 or 5xx, and `http` failures with no status,
  such as a dropped connection.

```lua
uji.wire.add("echo", {
  stream = function(request, reply)
    local last = request.messages[#request.messages]
    reply.text("you said: ")
    reply.done({ text = "you said: " .. (last.text or "") })
  end,
})
```

### uji.wire.remove(name)

Removes a wire and returns `true` if it existed.

```lua
uji.wire.remove("echo")
```

### uji.wire.list()

Returns the names of the registered wires.

```lua
local wires = uji.wire.list()
```
