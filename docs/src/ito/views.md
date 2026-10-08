# Views

Each one fills a rectangle of the screen. One built from a list skips any
`false` entry in it, so `busy and ito.Spinner()` shows a spinner only while
`busy` is true. A `nil` ends the list.

## ito.view(body)

Makes a view out of `body`, a function that takes the view's props and
returns the view to draw. Calling the result with a props table gives a view
to place inside another.

```lua
local ito = require("ito")

local Branch = ito.view(function(props)
  return ito.Text(props.name):foreground(ito.Color.green)
end)

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
    return Branch({ name = "main" })
  end),
})
```

A view of your own takes the same [modifiers](modifiers.md) as ito's views,
and they apply to the view its body returns.

A view keeps its [state](state.md) by its place among its siblings. Give it an
id with [`:id`](modifiers.md#id), on ito's views and your own alike, and the
state follows the view when the list around it changes order.

`ito.view` raises an error when `body` is not a function.

## ito.VStack(children)

Stacks `children` from the top down. A child is as tall as its content,
unless it has [`height`](modifiers.md#heightrows-and-widthcolumns),
[`share`](modifiers.md#sharefraction) or [`grow`](modifiers.md#growweight).
The children that grow split the rows the others leave, by their weights.

```lua
ito.VStack({
  ito.Text("Build"):bold(),
  ito.Text("3 warnings"):foreground(ito.Color.yellow),
  ito.Spacer(),
  ito.Text("updated just now"):dim(),
})
```

## ito.HStack(children)

Places `children` side by side from the left. A child is as wide as its
`width`, its `share`, or its text, and one that has `grow` or no natural width
takes a part of the columns the others leave.

```lua
ito.HStack({ ito.Text("main"), ito.Spacer(), ito.Text("3 files changed") })
```

## ito.Spacer()

Fills the room the rest of its stack leaves. Whatever follows it sits at the
far edge.

## ito.Text(text)

Draws `text`, one row for each line in it. `text` is a string, or a list of
spans, each `{ text, style }`, for text in more than one style. A line too
long for the view is cut at its edge unless the text wraps. These modifiers
style the whole text, and a span's own style goes on top.

| Modifier | Effect |
|---|---|
| `:foreground(colour)` | The text colour, an [`ito.Color`](modifiers.md#colours). |
| `:bold()`, `:dim()`, `:italic()`, `:underline()`, `:reverse()`, `:strikethrough()`, `:blink()` | Turns on that attribute. |
| `:style(style)` | Merges an [`ito.TextStyle`](../configuration/themes.md#styles) on top of the text's style so far. |
| `:wrap()` | Wraps each line to the width the view gets. |
| `:repeating()` | Repeats the text across and down all the room the view gets, such as a bar beside a column or a rule across a row. |

```lua
ito.Text("build failed"):foreground(ito.Color.red):bold()
ito.Text("3 files"):style(ito.theme().styles.muted)
ito.HStack({
  ito.Text("│"):repeating():padding({ trailing = 1 }),
  ito.Text({ { "Note", ito.theme().styles.bold }, { " the build is slow on a cold cache" } }):wrap():grow(),
})
```

`ito.Text` raises an error when `text` is neither a string nor a list.

## ito.Fold(content, opts)

Shows `content` up to `opts.rows` rows. When `content` is taller, it shows the
first `opts.rows` rows and, under them, the view `opts.more(hidden)` gives,
where `hidden` is the number of rows left out. Without `opts.rows` it shows all
of `content`.

```lua
ito.Fold(ito.Text(log):wrap(), {
  rows = 8,
  more = function(hidden)
    return ito.Text("… " .. hidden .. " more"):dim()
  end,
})
```

Raises an error when `opts.rows` is not a whole number or `opts.more` is not a
function.

## ito.Lines(lines, value)

Draws `lines`, a list of lines, where each line is a list of spans. `lines`
can also be a function that takes the width the view gets and `value`, and
returns the lines, for text that wraps. Its lines are kept until the function,
`value` or the width changes. A span is
`{ text, style }`, and the style is an
[`ito.TextStyle`](../configuration/themes.md#styles), such as one of the
theme's `ito.theme().styles.muted`. A span without a style is drawn in the
terminal's own style. A line with an `on_click` function calls it when you
click that line.

```lua
local ito = require("ito")

local Summary = ito.view(function()
  local styles = ito.theme().styles
  return ito.Lines({
    { { "tests ", styles.muted }, { "passing", styles.accent } },
    {
      { "open the build log", styles.highlight },
      on_click = function()
        uji.ui.exec("less build.log")
      end,
    },
  })
end)
```

[Styles](../configuration/themes.md#styles) lists the styles every theme has.

```lua
local function note(width, value)
  return value.theme:wrap(value.text, { width = width, style = value.theme.styles.text })
end

local Note = ito.view(function(props)
  return ito.Lines(note, { theme = ito.theme(), text = props.text })
end)
```

## ito.spans.wrap(line, width)

Breaks one line of spans into lines no wider than `width`, and keeps each
piece in its span's style. It breaks at the last space that fits and drops
that space, keeps leading spaces with the text after them, and cuts a word
that is wider than `width`. A line's `on_click` and a span's other fields go
to every piece. It suits an `ito.Lines` function, which gets the width.

```lua
local function code(width, value)
  local out = {}
  for _, line in ipairs(value.lines) do
    for _, row in ipairs(ito.spans.wrap(line, width)) do
      out[#out + 1] = row
    end
  end
  return out
end

local Code = ito.view(function(props)
  return ito.Lines(code, { lines = props.lines })
end)
```

## ito.Group(children)

Draws `children` one under another, like `ito.VStack`. Inside an
[`ito.LazyVStack`](controls.md#itolazyvstackitems-row), each child becomes a row
of its own, and only the ones that show are built.

## ito.ZStack(children)

Draws `children` on top of each other in the order of the list, so the last
one is in front. Each child sits at the stack's `alignment`, `center` unless
the props name another from [`ito.Alignment`](modifiers.md#alignalignment), and
a child's own `:align` wins over it. A child takes its fixed size, the whole
stack when it grows, or else the size its content needs.

```lua
ito.ZStack({
  alignment = ito.Alignment.top_trailing,
  ito.Lines(log):grow(),
  ito.Text(" 3 new "):background(ito.theme().colors.accent),
})
```

## ito.Subviews(children, builder)

Builds `children`, then calls `builder(subviews)` with the ones that drew
something, in order. The builder returns the view to draw and places each
subview in it at most once. A subview keeps its state, and it carries the
hints its parent would read: `weight`, `width`, `height`, `alignment` and
`layout_id`. Modifiers on `ito.Subviews(...)` apply to the view the builder
returns.

This puts a bar between neighbours, but not next to a spacer or a segment that
drew nothing:

```lua
local function joined(children)
  return ito.Subviews(children, function(subviews)
    local row = {}
    for index, subview in ipairs(subviews) do
      local before = subviews[index - 1]
      if before and not before.weight and not subview.weight then
        row[#row + 1] = ito.Text(" | ")
      end
      row[#row + 1] = subview
    end
    return ito.HStack(row)
  end)
end
```

Placing one subview twice raises "a subview can be placed once".

## ito.Layout(measure)

Makes a container from one function. `measure(children, room)` returns the
container's width, its height and a `place(x, y)` function. `room.width` and
`room.height` are cells, or `nil` while the parent asks for a natural size.
Each child has `child:measure(room)`, which gives the width and height it
wants, and `child:place(x, y, width, height)`, plus the `weight`,
`alignment` and `layout_id` hints. A child that `place` never places is not
drawn.

Lay children out from `children` and `room` alone. ito lays a container out
again only when its room or its children change.

```lua
local Corners = ito.Layout(function(children, room)
  return room.width, room.height, function(x, y)
    for _, child in ipairs(children) do
      local width, height = child:measure(room)
      if child.layout_id == "end" then
        child:place(x + room.width - width, y + room.height - height, width, height)
      else
        child:place(x, y, width, height)
      end
    end
  end
end)

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
    return Corners({ ito.Text("uji"), ito.Text("v0.4"):layout_id("end") }):height(1)
  end),
})
```

## ito.SubcomposeLayout(build, opts)

Calls `build(room)` with the room the view gets, `{ width, height }` in cells,
and draws the view it returns. While its parent measures it, the height is
`math.huge`. The content keeps its state across frames. An error while
building is passed to `opts.failed(message)` when you give one, and the view
then draws nothing. In an `ito.HStack` it takes the room the other views
leave, unless it has a `width`.

```lua
ito.SubcomposeLayout(function(room)
  if room.width < 60 then
    return ito.Text(uji.model.current().model)
  end
  return ito.Text(uji.model.current().name .. "/" .. uji.model.current().model)
end)
```
