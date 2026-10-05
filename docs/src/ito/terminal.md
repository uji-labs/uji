# Terminal

## ito.open()

Opens the terminal and gives two values, one to draw with and one that reads
keys and clicks. Every call gives the same two, and they survive `/reload`.
uji draws on this terminal too, so anything else drawn on it is replaced at
uji's next frame. It is mainly for a tree that
[replaces everything](../rebuilding/everything.md).

Rows and columns count from 0 at the top left. Drawing only changes the screen
in memory, and `screen:flush()` shows the changes. A position outside the
screen draws nothing.

```lua
local ito = require("ito")

return function()
    local screen, input = ito.open()
    local title = ito.TextStyle({ foreground = ito.Color.cyan, bold = true })
    local width, height = screen:size()
    screen:clear()
    screen:line(0, 0, { { "hello ", title }, "from uji" })
    screen:line(1, 0, "the screen is " .. width .. " by " .. height)
    screen:line(2, 0, "press q to quit")
    screen:cursor(3, 0, "bar")
    screen:flush()
    for event in input:events() do
        if event.type == "key" and event.key == "q" then
            break
        end
        screen:line(3, 0, "you pressed " .. (event.key or event.type) .. "      ")
        screen:flush()
    end
    screen:close()
end
```

## The screen

| Member | Meaning |
|---|---|
| `screen:size()` | The width and the height, in columns and rows. |
| `screen:line(row, col, spans, width)` | Draws `spans` from `row` and `col`, and gives the column after the last character. `spans` is a string, or a list whose items are strings or `{ text, style }` pairs, where the style is an [`ito.TextStyle`](../configuration/themes.md#styles) or is left out for the terminal's own style. `width` stops the text after that many columns. The list's `on_click` field is a function that `screen:clicked` gives for a click anywhere on the line. |
| `screen:clicked(row, col)` | The `on_click` function of the line drawn last at the position, or `nil` when that line has none. |
| `screen:fill(area, style, symbol)` | Fills `area`, a table with `x`, `y`, `width` and `height`, with `symbol` in `style`, an `ito.TextStyle`. With no style it uses the terminal's own, and `symbol` is a space when it is left out. |
| `screen:paint(area, style)` | Sets the style of `area` to `style`, an `ito.TextStyle`, and keeps its text. |
| `screen:text(row)` | The text on `row`, or `nil` outside the screen. |
| `screen:spans(row)` | The text on `row` split where the style changes, as a list of `{ text, fg, bg, modifiers }`, or `nil` outside the screen. `fg` and `bg` are left out for the terminal's default colour, and `modifiers` lists names such as `"bold"`. |
| `screen:clear()` | Empties the whole screen. |
| `screen:cursor(row, col, shape)` | Shows the cursor at the position, as `"block"`, the default, `"bar"` or `"underline"`. With no position it hides the cursor. |
| `screen:flush()` | Shows what changed since the last flush, and puts the cursor in place. |
| `screen:write(bytes)` | Sends `bytes` to the terminal as they are. |
| `screen:suspend()` | Gives the terminal back, for a program that needs it. |
| `screen:resume()` | Takes the terminal again and clears it, ready for the next flush. |
| `screen:close()` | Gives the terminal back for good. |

Colours come from `ito.Color` and `ito.rgb`, as
[Colours](../configuration/themes.md#colours) describes.

A span that is neither a string nor a pair, a style that is not an
`ito.TextStyle`, and an unknown cursor shape all raise an error.

## The input

| Member | Meaning |
|---|---|
| `input:event()` | Waits for the next event and gives it as a table. |
| `input:events()` | An iterator over the events, for a `for` loop. |

Each event has a `type` field.

| `type` | Fields |
|---|---|
| `"key"` | `key`, and `ctrl`, `alt`, `shift`, `meta` and `repeat` as booleans. |
| `"mouse"` | `kind`, `button`, `row`, `col`, and `ctrl`, `alt` and `shift` as booleans. |
| `"paste"` | `text`, the pasted text. |
| `"resize"` | `width` and `height`, the new size. |
| `"focus"` | `focused`, `true` when the terminal gains focus and `false` when it loses it. |

`key` is the character typed, such as `"a"` or `"A"`, or one of `"enter"`,
`"esc"`, `"backspace"`, `"delete"`, `"tab"`, `"backtab"`, `"left"`, `"right"`,
`"up"`, `"down"`, `"home"`, `"end"`, `"pageup"`, `"pagedown"`, `"insert"` and
`"f1"` to `"f12"`.

A mouse `kind` is `"down"`, `"up"`, `"drag"`, `"move"`, `"scroll_up"`,
`"scroll_down"`, `"scroll_left"` or `"scroll_right"`. `button` is `"left"`,
`"right"` or `"middle"` for presses, releases and drags, and `nil` otherwise.

A click handler sees the frame on the screen. The lines that one frame
draws keep their handlers until the next frame starts drawing after a
flush, and a later line or `fill` over the same cells hides the handler
under it.

```lua
local screen, input = require("ito").open()
local count = 0
local function draw()
    screen:clear()
    screen:line(0, 0, {
        "clicked " .. count .. " times",
        on_click = function()
            count = count + 1
        end,
    })
    screen:flush()
end
draw()
for event in input:events() do
    if event.type == "mouse" and event.kind == "up" then
        local click = screen:clicked(event.row, event.col)
        if click then
            click(event)
            draw()
        end
    end
end
```
