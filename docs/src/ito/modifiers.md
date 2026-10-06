# Modifiers

A modifier changes one view and gives the same view back, so modifiers chain
one after another with `:`.

```lua
ito.Text("3 files changed")
  :foreground(ito.Color.yellow)
  :padding({ horizontal = 1 })
  :border(ito.theme().borders.rounded)
  :title("git")
```

A value a modifier cannot use raises an error that names it, such as
`grow takes a weight above 0, not -1`.

## :padding(cells)

Leaves `cells` blank cells on every side of the content. A table sets only
the sides it names: `top`, `bottom`, `leading` and `trailing` one at a time,
`vertical` for the rows above and below, and `horizontal` for the columns on
the left and right. A side it leaves out keeps what it had.

Order matters, as it reads. Padding added before `:background` or `:border`
sits inside them, and padding added after sits outside, so the background and
the box leave it blank.

```lua
ito.Text("note"):padding({ leading = 2 })
ito.Text("panel"):padding({ vertical = 1, horizontal = 2 })
```

## :border(set, opts)

Draws a box around the view with the characters in `set`. A theme's borders
are in `ito.theme().borders`, such as `plain` and `rounded`, and a table of
your own needs all six fields that
[Borders](../configuration/themes.md#borders) lists.

| Option | Meaning | Default |
|---|---|---|
| `edges` | `ito.Edges.all` for the whole box, or `ito.Edges.horizontal` for only the lines above and below. | `ito.Edges.all` |
| `color` | The box's colour, an [`ito.Color`](#colours). | the theme's `border` style |

```lua
ito.Text("ready"):border(ito.theme().borders.plain, { edges = ito.Edges.horizontal, color = ito.Color.green })
```

## :title(title)

Puts `title` in the top border. It is a string, or a line of spans as
[`ito.Lines`](views.md#itolineslines-value) takes.

## :background(colour)

Fills the whole view with `colour`, an [`ito.Color`](#colours), before its
content is drawn. An [`ito.TextStyle`](../configuration/themes.md#styles)
works too, and sets the text colour and flags of the whole view as well.

```lua
ito.Text(" deploying "):background(ito.rgb(0x2b2b2b))
```

## :opaque()

Clears the view's whole rectangle before it draws, so nothing drawn under it
shows through.

## :hidden(hide)

Keeps the view and its state but neither draws it nor gives it room. `false`
shows it again.

```lua
Editor():hidden(not open.value)
```

## :focus_scope(value)

Marks the controls drawn inside the view with `value`. A
[window](window.md) gives the keys only to controls in its own scope.

## :height(rows) and :width(columns)

Fix the view's size in cells, whatever its content needs.

## :share(fraction)

Gives the view `fraction` of the room in its stack, from `0` to `1`.
`:share(0.3)` in an `ito.HStack` takes 30% of the columns.

## :grow(weight)

Gives the view a part of the room the other views in its stack leave.
The parts follow the weights, and a view with no weight given has `1`.

```lua
ito.HStack({
  ito.Lines(files):grow(),
  ito.Lines(diff):grow(2),
})
```

## :align(alignment)

Places the view at one of `ito.Alignment`: `top_leading`, `top`,
`top_trailing`, `leading`, `center`, `trailing`, `bottom_leading`, `bottom`
or `bottom_trailing`. In an `ito.VStack` the view keeps its own width and moves
left or right, and in an `ito.HStack` it keeps its own height and moves up or
down. An `ito.ZStack` and an overlay use both directions. Without it, a stack
stretches the view across.

```lua
ito.VStack({
  ito.Text("uji"),
  ito.Text("v0.4"):align(ito.Alignment.trailing),
})
```

## :overlay(content, alignment)

Draws `content` in front of the view, at `alignment`, `center` by default.
The view keeps its own size, and `content` is fitted inside it. `false` draws
nothing. Several overlays are drawn in the order you add them.

```lua
ito.Text("build"):overlay(ito.Text("●"):foreground(ito.theme().colors.accent), ito.Alignment.trailing)
```

## :layout_id(tag)

Gives the view a tag that an [`ito.Layout`](views.md#itolayoutmeasure) it sits
in reads as `layout_id`. Unlike `:id`, it has nothing to do with state.

## :id(...)

Gives the view an identity of its own. Its [state](state.md), and the state of
the views inside it, then stays with it when the views around it change order,
and starts fresh when the id changes.

Several values make one id, so `:id(job.kind, job.number)` tells two jobs with
the same number apart. An id only has to differ from its siblings' ids. Two
siblings with one id raise an error, and so does an id of `nil`, `false` or
NaN. Your own views take an id the same way, as in `Badge():id(name)`.

```lua
for _, job in ipairs(jobs) do
  rows[#rows + 1] = JobRow({ job = job }):id(job.kind, job.number)
end
```

## :on_tap(handler)

Calls `handler` when you click anywhere on the view.

```lua
ito.Text("[run the tests]"):on_tap(function()
  uji.session.submit("Run the tests and fix what fails.")
end)
```

## Colours

A colour is an `ito.Color` value. `ito.rgb(0xff8800)` gives one from its red,
green and blue parts and raises an error for a number outside `0x000000` to
`0xffffff`. `ito.Color.indexed(245)` gives one of the terminal's 256 colours,
and `ito.Color.cyan` one of its named colours, which
[Colours](../configuration/themes.md#colours) lists. A string or a number
where a colour belongs raises an error, such as
`foreground must be an ito.Color, not a string`. The theme's own colours are
in `ito.theme().colors`.

```lua
ito.Text("warning"):foreground(ito.rgb(0xff8800))
ito.Text("note"):foreground(ito.theme().colors.accent)
```
