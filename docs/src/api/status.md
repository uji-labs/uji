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
