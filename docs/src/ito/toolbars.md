# Toolbars

A toolbar item is a view that names the section of the screen it belongs in.
The screen decides where each section sits, so a plugin says what it shows and
which section it goes in, never a row or a column.

## ito.ToolbarPlacement

| Placement | Where uji's default screen shows it |
|---|---|
| `top_bar_leading` | The left end of the top row. |
| `top_bar_trailing` | The right end of the top row. |
| `keyboard` | Directly above the input line, the section for things that go with typing. |
| `bottom_bar` | Under the input line, at the bottom of the screen. |

A theme's [screen](../configuration/themes.md#the-screen) can put any section
somewhere else, or leave it out.

## ito.ToolbarItem(placement, content)

Makes one item. `content` is a view of your own, or a function that returns a
view, and it is built again on every frame. Layout modifiers go on the view you
return, so the item reads as both the section and the place inside it:

```lua
local ito = require("ito")

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.keyboard, function()
    return ito.Text("ctrl+b toggles plan mode"):dim():align(ito.Alignment.leading)
  end),
})
```

`item:id(...)` gives the item an [id](modifiers.md#id), so its state stays with
it when items before it come and go. An item that draws nothing takes no room.
An item that raises an error draws nothing either, and the error is reported
once while the other items keep drawing.

`ito.ToolbarItem` raises an error when `placement` is not one of
`ito.ToolbarPlacement`, or when `content` is neither a view nor a function.

## view:toolbar(items)

Declares `items`, a list of `ito.ToolbarItem`, from inside the screen. The
items go to the nearest `ito.ToolbarHost` around the view. On uji's screen,
[`uji.ui.toolbar`](../api/ui.md#ujiuitoolbaritems) declares items the same
way from a plugin.

```lua
local Editor = ito.view(function(props)
  return ito.Lines(props.lines):toolbar({
    ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
      return ito.Text(#props.lines .. " lines"):dim()
    end),
  })
end)
```

## ito.ToolbarHost(content)

Collects the items that the views in `content` declare, its own first and then
in the order the views appear, and shows them in the sections inside
`content`. A host inside another host keeps the items declared inside it for
itself, so an overlay can have its own bar. uji's screen is a host already.

When a host has items for a placement that no section shows, it says so once:
`toolbar: nothing shows the items placed at bottom_bar`.

## ito.ToolbarItems(placement, arrange)

The section that shows the host's items for `placement`. `arrange` lays them
out: `ito.VStack`, the default, puts them in a column, and `ito.HStack` puts
them in a row. A section with no items takes no room.

```lua
ito.VStack({
  slots.transcript():grow(),
  ito.ToolbarItems(ito.ToolbarPlacement.keyboard, ito.HStack),
  slots.composer(),
  ito.ToolbarItems(ito.ToolbarPlacement.bottom_bar),
})
```
