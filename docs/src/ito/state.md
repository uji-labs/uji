# State

## ito.state(initial)

Gives a value you read and set through `.value`, starting with the one you
pass. Set a different one and every view that read it while it was built
draws again.

Inside the body of a view, the view keeps the same state from one frame to the
next, for as long as it stays on the screen. Made anywhere else, such as at the top of a plugin, a state holds data
the plugin sets from outside its views.

```lua
local ito = require("ito")

local Output = ito.view(function(props)
  local open = ito.state(false)
  local shown = open.value and props.lines or { props.lines[#props.lines] }
  local rows = {}
  for index, line in ipairs(shown) do
    rows[index] = { { line, ito.theme().styles.muted } }
  end
  return ito.Lines(rows):on_tap(function()
    open.value = not open.value
  end)
end)
```

Order matters. A view finds its states by the order of its calls, so a body
calls `ito.state` the same number of times, in the same order, on every
frame.

```lua
local ito = require("ito")

local tests = ito.state("not run")

uji.command.add("test", {
  desc = "run the tests",
  handler = function()
    tests.value = "running"
    uji.job.start({
      cmd = { "cargo", "test", "--quiet" },
      on_exit = function(code)
        tests.value = code == 0 and "passing" or "failing"
      end,
    })
  end,
})

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
    return ito.Text("tests " .. tests.value):dim()
  end),
})
```

## ito.remember(factory)

Calls `factory` the first time the view is built and gives the same value
back on every later frame. Unlike a state, it never draws a new frame. Use it
only inside the body of a view. Anywhere else it raises an error.

```lua
local Uptime = ito.view(function()
  local started = ito.remember(os.time)
  return ito.Text(os.difftime(os.time(), started) .. " seconds")
end)
```

## ito.Local(default)

Makes a value a view hands down to every view inside it, while the frame is
built. `:provide(value,
view)` gives `view` with `value` set for itself and everything inside it, and
`.current` reads the value inside a body. Where no view above provided one,
`.current` is `default`.

```lua
local ito = require("ito")

local Accent = ito.Local(ito.Color.cyan)

local Label = ito.view(function(props)
  return ito.Text(props.text):foreground(Accent.current)
end)

local Panel = ito.view(function()
  return Accent:provide(ito.Color.magenta, ito.VStack({
    Label({ text = "plan" }),
    Label({ text = "build" }),
  }))
end)
```

## ito.theme()

Returns the theme in use, the same `ctx` that templates take. It has `styles`,
`colors`, `symbols`, `borders`, `text`, `limits`, `options` and `templates`,
and the helpers that [Templates](../configuration/themes.md#templates) lists.
It works in views, toolbar items and
[`render_message`](../api/events.md#render_message) handlers alike.

```lua
local ito = require("ito")

local Status = ito.view(function(props)
  local theme = ito.theme()
  return ito.Lines({
    { { theme.symbols.pointer .. " ", theme.styles.accent }, { props.text, theme.styles.text } },
  })
end)
```

Changing themes redraws every view that used the old one.

## ito.PreferenceKey(spec)

Makes a key for a value that views hand up to the views around them. `spec`
has `default`, the value when nothing reports one, and `reduce(value,
next_value)`, which combines two values. Views report in the order they appear
in the tree.

| Modifier | Effect |
|---|---|
| `view:preference(key, value)` | Reports `value` for `key`. |
| `view:overlay_preference_value(key, build, alignment)` | Combines what the views inside report for `key`, and draws `build(value)` in front of the view at `alignment`, in the same frame. |

```lua
local ito = require("ito")

local Failing = ito.PreferenceKey({
  default = 0,
  reduce = function(value, next_value)
    return value + next_value
  end,
})

local Suite = ito.view(function(props)
  local rows = {}
  for index, result in ipairs(props.results) do
    rows[index] = ito.Text(result.name):preference(Failing, result.ok and 0 or 1)
  end
  return ito.VStack(rows):overlay_preference_value(Failing, function(count)
    return ito.Text(count .. " failing")
  end, ito.Alignment.top_trailing)
end)
```
