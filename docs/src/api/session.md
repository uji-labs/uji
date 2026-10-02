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
