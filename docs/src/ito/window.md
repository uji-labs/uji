# Window

## ito.Window(screen, invalidate)

Draws views on a screen and sends input to them. `screen` comes from
[`ito.open()`](terminal.md#itoopen), and `invalidate` is called whenever a
state changes and the window needs a new frame. uji draws its own screen
through a window, and a window of your own draws a tree that
[replaces everything](../rebuilding/everything.md).

| Member | Meaning |
|---|---|
| `window:render(view, theme)` | Builds `view` with `theme` and draws it on the whole screen, then gives the keys to a control. |
| `window:key(chord)` | Gives a key to the control that has the keys, and returns `true` when it used it. |
| `window:wheel(row, col, rows)` | Scrolls whatever scrolls at that position, and returns `true` when something did. |
| `window:press(row, col)`, `window:drag(row, col)` | Start and extend a selection, or a click. |
| `window:release(event)` | Ends the selection and returns its text, or calls the click target under the press. |
| `window.scope` | The [focus scope](modifiers.md#focus_scopevalue) whose controls get the keys. `nil` means controls outside any scope. |
| `window.focused` | The key handler of the control that has the keys. |

## ito.SelectionHighlight()

Paints the window's selection in the theme's `selection` style. Put it last in
a `ito.ZStack` over the screen.

```lua
local ito = require("ito")

local screen, input = ito.open()
local window = ito.Window(screen, function() end)
local themes = ito.Themes({ default = require("uji.themes.default")() })

local function draw()
  window:render(
    ito.ZStack({ ito.Text("select me with the mouse"), ito.SelectionHighlight() }),
    themes:context()
  )
  screen:flush()
end
```
