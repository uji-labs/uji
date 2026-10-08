# uji.session

These functions read the open conversation, and can post to it, rename it,
compact it or stop the running turn.

## uji.session.info()

Returns a table with the session's `id`, `title` and `directory`, and
`short_directory`, the directory with your home folder written as `~`.

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

## uji.session.context()

Returns a table with `used`, the estimated tokens in the conversation, and
`window`, the model's context size when uji knows it.

```lua
local context = uji.session.context()
if context.window then
  uji.notify(string.format("%d%% of context used", context.used * 100 // context.window))
end
```

## uji.session.queue()

Lists the messages you typed while the model worked that uji has not sent
yet.

```lua
local waiting = #uji.session.queue()
```

## uji.session.state()

Gives `"working"` during a turn, and `"idle"` otherwise.

```lua
local busy = uji.session.state() == "working"
```

## uji.session.elapsed()

Counts the seconds since the current turn started. When idle, the result is
`nil`.

```lua
local seconds = math.floor(uji.session.elapsed() or 0)
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
does, and returns `true`. It returns `false` and the reason when a turn is
running, when there is nothing to compact yet, or when the provider runs its
own loop and keeps its own context. uji fires
[`session_compacted`](events.md#session_compacted) when the summary is saved.

```lua
local started, reason = uji.session.compact()
if not started then
  uji.notify(reason)
end
```

## uji.session.list(opts)

Returns the stored sessions, newest first, as a list of tables with `id`,
`title`, `directory` and `updated` (milliseconds since the Unix epoch).
Sessions saved under another one with `uji run --parent` are not listed.
`opts` is optional, and without `directory` the list covers every directory.

| Option | Type | Meaning |
|---|---|---|
| `directory` | string | List only the sessions started in this directory. |

```lua
local here = uji.session.info().directory
for _, session in ipairs(uji.session.list({ directory = here })) do
  uji.notify(session.title)
end
```

## uji.session.delete(id)

Deletes a stored session and the sessions saved under it, and returns `true`.
It returns `nil` and a message when the id is not a session id, when no session
has that id, or when deleting it would delete the session open in this uji.
Anything other than a string raises an error.

```lua
local ok, err = uji.session.delete(id)
if not ok then
  uji.notify(err)
end
```
