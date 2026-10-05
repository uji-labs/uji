# ito

ito is the terminal UI library uji draws its screen with, and
`require("ito")` gives it to your config, your plugins and your themes. You
build what the screen shows out of views, change how each view looks with
modifiers, and keep values between frames with state. uji draws a new frame
whenever one of those values changes.

```lua
local ito = require("ito")

local Clock = ito.view(function()
  local shown = ito.state(os.date("%H:%M"))
  return ito.HStack({
    ito.Text("uji"):bold(),
    ito.Spacer(),
    ito.Text(shown.value):foreground(ito.Color.cyan),
  }):on_tap(function()
    shown.value = os.date("%H:%M:%S")
  end)
end)

uji.ui.toolbar({ ito.ToolbarItem(ito.ToolbarPlacement.top_bar_leading, Clock) })
```

This puts a bar at the top of the screen with the time on the right. A click
on the bar adds the seconds.

## Where views go

| Place | How |
|---|---|
| A section of the screen | [`uji.ui.toolbar`](../api/ui.md#ujiuitoolbaritems) declares [toolbar items](toolbars.md) for the top bar, the row above the input or the bottom bar. |
| A box over the screen | [`uji.ui.overlay`](../api/ui.md#ujiuioverlaycontent-opts) shows a view until you close it. |
| A part a theme can replace | Any view made with `ito.view`. A theme gives its own in `views`, keyed by the view. See [Views](../configuration/themes.md#views). |
| The whole screen | A theme replaces `uji.ui.Screen`. See [The screen](../configuration/themes.md#the-screen). |

## Pages

| Page | Contents |
|---|---|
| [Views](views.md) | `ito.view`, the stacks, text, lines and layouts of your own. |
| [Modifiers](modifiers.md) | Borders, padding, colours, sizes, alignment, overlays and clicks. |
| [State](state.md) | Values a view keeps between frames, values it hands to the views inside it, and the theme. |
| [Toolbars](toolbars.md) | Items a plugin puts in a section of the screen, and the sections that show them. |
| [Controls](controls.md) | A text field, a list, a scrolling view and a spinner, and which of them gets the keys. |
| [Terminal](terminal.md) | The screen and the input uji draws on. |
