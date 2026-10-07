# Controls

Controls are the views you type into and move through.

## ito.TextField(state)

A line you type into. `state` comes from [`ito.state`](state.md#itostateinitial)
and holds the text, so typing changes `state.value` and setting `state.value`
changes the line.

| Modifier | Effect |
|---|---|
| `:placeholder(text)` | Shows `text` dimmed while the line is empty. |
| `:hidden()` | Draws the theme's `mask` symbol for each character, for secrets. |
| `:on_submit(handler)` | Calls `handler(text)` when you press Enter. |
| `:focused()` | Asks for the keys when the field first shows. |

Typed characters go in at the cursor. Left, Right, Home and End move the
cursor, and Backspace and Delete erase. `ito.TextField` raises an error when
`state` is not a state.

```lua
local ito = require("ito")

uji.command.add("branch", {
  desc = "create a branch",
  handler = function()
    local overlay
    overlay = uji.ui.overlay(function()
      local name = ito.state("")
      return ito.VStack({
        ito.Text("New branch"):bold(),
        ito.TextField(name):placeholder("feature/name"):focused():on_submit(function(text)
          overlay:close(text)
        end),
      }):padding({ horizontal = 1 }):border(ito.theme().borders.rounded)
    end)
    local branch = overlay:wait()
    if branch and branch ~= "" then
      uji.session.submit("Create the branch " .. branch .. " and switch to it.")
    end
  end,
})
```

## ito.List(items, row)

Shows `items`, one row for each. ito calls `row(item, index, selected)` to
build each row as a view, and only for the rows that fit. `selected` is true
for the chosen row. The list scrolls to keep the chosen row in view.

| Modifier | Effect |
|---|---|
| `:selection(state)` | Keeps the chosen index in a state, so you can read or set it. Without it, the list keeps the index itself. |
| `:on_choose(handler)` | Calls `handler(item, index)` when you press Enter. |
| `:focused()` | Asks for the keys when the list first shows. |
| `:passive()` | Leaves the keys to the views around the list, which move it through `:selection`. |
| `:footer(builder)` | Draws `builder(first, last, total)` under the rows, where `first` and `last` are the rows in view. |
| `:item_id(fn)` | Gives each item the id `fn(item, index)`. A row's state, the chosen row and the first row in view then follow their items when items are added, removed or moved. Without it they stay at their positions. |

Up and Down move the choice by one row, Page Up and Page Down by a page, and
Home and End go to the first and last rows. The mouse wheel over the list
moves it too. `ito.List` raises an error unless `items` is a list and `row` is
a function, and `:item_id` raises one when two items share an id.

```lua
local ito = require("ito")

local overlay
overlay = uji.ui.overlay(function()
  local styles = ito.theme().styles
  return ito.List(uji.session.list(), function(session, _, selected)
    local style = selected and styles.chosen or styles.text
    return ito.Lines({ { { session.title, style } } })
  end)
    :item_id(function(session)
      return session.id
    end)
    :focused()
    :on_choose(function(session)
      overlay:close(session)
    end)
    :footer(function(first, last, total)
      return ito.Text(first .. "-" .. last .. " of " .. total):dim()
    end)
    :border(ito.theme().borders.rounded)
    :title("Sessions")
end)
```

## ito.ScrollView(child)

Shows `child` at its full height and scrolls it with the mouse wheel.
`:state(scroll)` scrolls by an [`ito.ScrollState`](#itoscrollstateopts) instead,
so code of your own can move it too.
`:follow_end()` keeps the bottom in view while the content grows, stops when
you scroll up, and follows again once you scroll back to the bottom.

```lua
local ito = require("ito")

uji.fs.read("CHANGELOG.md", function(text)
  if not text then
    return
  end
  uji.ui.overlay(function()
    return ito.ScrollView(ito.Text(text)):border(ito.theme().borders.plain):title("CHANGELOG")
  end)
end)
```

## ito.ScrollState(opts)

Holds where a scrolling view is. `opts.follow` starts it at the end. Pass it
to `ito.ScrollView(child):state(scroll)` or `ito.LazyVStack(...):state(scroll)`.

| Member | Meaning |
|---|---|
| `scroll:scroll(rows)` | Moves down by `rows`, or up when it is negative. |
| `scroll:to_top()` | Goes to the top. |
| `scroll:to_end()` | Goes to the end and follows it while the content grows. |
| `scroll.following` | Whether it is at the end and following it. |
| `scroll.page` | The rows that show, for paging. |
| `scroll.offset` | The first row that shows, counted from `0`. |
| `scroll.total` | The rows the content of an `ito.ScrollView` has. |

`page`, `offset` and `total` are set when the scrolling view is laid out. A
view that shows them, such as a "rows 1-10 of 40" line under it, reads them in
an [`ito.SubcomposeLayout`](views.md#itosubcomposelayoutbuild-opts), which is
built after the views above it are laid out.

## ito.LazyVStack(items, row)

Shows `items` one under another and builds only the rows that show, so a list
of thousands stays fast. `row(item, index)` gives the view of an item, and an
[`ito.Group`](views.md#itogroupchildren) makes each of its children a row.
Without a state it follows nothing and starts at the top.

| Modifier | Meaning |
|---|---|
| `:item_id(id)` | Gives each item a lasting id, so its place and state follow it when items come and go. Two items with one id raise an error. |
| `:state(scroll)` | The [`ito.ScrollState`](#itoscrollstateopts) it scrolls by. |
| `:footer(view)` | A view under the rows, right after the last one when they do not fill the room. |

```lua
local ito = require("ito")

local scroll = ito.ScrollState({ follow = true })

local Log = ito.view(function(props)
  return ito.LazyVStack(props.lines, function(line)
    return ito.Text(line.text)
  end)
    :item_id(function(line)
      return line.id
    end)
    :state(scroll)
end)
```

## ito.Spinner()

Draws the frames of the theme's `symbols.spinner`, one after another every
`limits.spinner_interval` seconds, in the theme's `accent` style.

```lua
ito.HStack({ ito.Spinner(), ito.Text(" indexing"):dim() })
```

## Focus

Keys go to one control at a time. The control that has them keeps them while
it is on the screen. When no control has them, the first one drawn with
`:focused()` takes them, or else the first one drawn. A key the control does
not use, such as Ctrl-C, goes on to uji's [keymap](../api/keymap.md).

While a picker, prompt, approval or [overlay](../api/ui.md#ujiuioverlaycontent-opts)
is open, only the controls inside the one on top can take the keys. A control
on the screen gets them back once it closes.
