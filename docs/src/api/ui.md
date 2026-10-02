# uji.ui

## uji.ui.open_win(opts)

Opens a window and returns its id. The default config opens these four.

```lua
uji.ui.open_win({ name = "messages", view = "messages", split = "top", size = "fill", wrap = true })
uji.ui.open_win({ name = "input", view = "input", split = "bottom", size = "auto", border = "horizontal" })
uji.ui.open_win({ name = "modal", view = "modal", split = "bottom", size = "auto" })
uji.ui.open_win({ name = "activity", split = "bottom", size = 0, padding = 1 })
```

| Option | Values | Default |
|---|---|---|
| `name` | a name that [`uji.ui.list_wins`](#ujiuilist_wins) reports, so another plugin can find the window | none |
| `view` | `"messages"` for the transcript, `"input"` for the input line, `"modal"` for pickers, prompts and approval questions. Leave it out for a window you draw into. | none |
| `split` | `"top"`, `"bottom"`, `"left"` or `"right"` | `"top"` |
| `size` | rows or columns, `"fill"`, or `"auto"` to fit the content | `"fill"` |
| `border` | `"none"`, `"plain"`, `"rounded"` or `"horizontal"` | `"none"` |
| `border_color` | a [colour](#colours) | the theme's |
| `title` | text in the border | none |
| `wrap` | wrap long lines | `false` |
| `padding` | blank cells around the content | `0` |
| `priority` | layout order, lowest first. In a bottom split, lower sits closer to the bottom edge. | `50` |
| `float` | `{ width = ..., height = ... }`, each `"80%"` or a cell count | not floating |

Raises an error for an unknown view, split, border or size.

## uji.ui.list_wins()

Returns one table per open window, in layout order.

| Field | Meaning |
|---|---|
| `id` | The id that `uji.ui.open_win` returned. |
| `name` | The `name` the window was opened with, or `nil`. |
| `view` | `"messages"`, `"input"`, `"modal"`, or `nil` for a window a plugin draws into. |
| `split` | The side the window sits on. |
| `size` | The size it was given, such as `3`, `"fill"` or `"auto"`. |
| `priority` | Its layout order. |
| `float` | `true` for a floating window. |
| `x`, `y` | The column and row of its content, counted from 0 at the top left. |
| `width`, `height` | The size of its content in cells. |

The position and size fields stay `nil` until uji first draws the window.
uji fires [`layout_changed`](events.md#layout_changed) when any of them
changes.

```lua
for _, win in ipairs(uji.ui.list_wins()) do
  if win.name == "input" then
    uji.notify("the input line is " .. win.width .. " columns wide")
  end
end
```

## uji.ui.size()

Returns the width and height of the terminal in cells, or nothing when the
screen is not open, as in `uji run`.

```lua
local width, height = uji.ui.size()
```

## uji.ui.set_lines(id, lines)

Replaces a window's content. Each line is a list of spans. A span is a string,
or a table with `text` and any of `color`, `bg`, `bold`, `italic` and
`underline`. A line may also be a single span.

`{ fill = true }` is a span that takes the room the rest of the line leaves,
so the spans after it sit at the right edge. Several fills share that room
equally. A line too long for its window leaves them none.

```lua
local bar = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.set_lines(bar, { { "main", { fill = true }, { text = "3 files", color = "gray" } } })
```

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 2 })
uji.ui.set_lines(panel, {
  { { text = "build", bold = true }, " passing" },
  { text = "3 files changed", color = "gray" },
})
```

## uji.ui.clear(id)

Empties a window.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.clear(panel)
```

## uji.ui.set_size(id, size)

Changes a window's size to rows or columns, `"fill"` or `"auto"`.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 0 })
uji.ui.set_size(panel, 3)
```

## uji.ui.set_title(id, title)

Sets the title in a window's border, or removes it when `title` is `nil`.

```lua
local panel = uji.ui.open_win({ split = "right", size = 30, border = "plain" })
uji.ui.set_title(panel, "todo")
```

## uji.ui.close_win(id)

Closes a window and returns `true` if it was open.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.close_win(panel)
```

## uji.ui.select(opts, on_done)

Shows a list to choose from. `opts.title` is the title and `opts.items` is a
list of strings. `on_done` receives the chosen item, or `nil` if you cancel.
Without `on_done`, the call waits and returns the chosen item.

```lua
uji.ui.select({ title = "Branch", items = { "main", "dev" } }, function(choice)
  if choice then
    uji.notify("picked " .. choice)
  end
end)
```

## uji.ui.pick(opts, on_done)

Shows a fuzzy finder with a preview pane. `on_done` receives the chosen item,
or `nil` if you cancel. Without `on_done`, the call waits and returns the
chosen item.

| Option | Type | Meaning |
|---|---|---|
| `title` | string | The title. |
| `items` | list of strings | The items to filter. |
| `preview` | function | Receives the highlighted item and returns lines to show. Without it, an item like `path:line:` shows that part of the file. |
| `on_query` | function | Makes the list live. Receives the query each time typing pauses, and a `show(items)` function that replaces the list. |

```lua
uji.ui.pick({
  title = "Search",
  on_query = function(query, show)
    local hits = {}
    uji.job.start({
      cmd = { "rg", "--line-number", "--no-heading", query },
      on_stdout = function(line)
        hits[#hits + 1] = line
      end,
      on_exit = function()
        show(hits)
      end,
    })
  end,
}, function(choice)
  if choice then
    uji.notify(choice)
  end
end)
```

## uji.ui.prompt(opts, on_done)

Asks for a line of text. `opts.title` is the question, `opts.value` fills the
line, and `opts.hidden = true` masks the input. `on_done` receives the text,
or `nil` if you cancel. Without `on_done`, the call waits and returns the text.

```lua
uji.ui.prompt({ title = "Commit message" }, function(message)
  if message and message ~= "" then
    uji.session.submit("Commit the staged changes with the message: " .. message)
  end
end)
```

## uji.ui.confirm(opts, on_done)

Asks a yes or no question and gives `true` for yes and `false` for no. uji
asks its approval questions through this function, so a plugin that replaces
`uji.ui.confirm` answers them, or shows them its own way.

| Field | Meaning |
|---|---|
| `title` | The question. |
| `body` | Text under the question, such as the command a tool wants to run. |
| `timeout` | Seconds to wait. When they pass, the question closes and gives `nil`. |

```lua
local yes = uji.ui.confirm({ title = "Delete the build folder?" })
```

This replacement rings the terminal bell before each question, then asks it
the usual way:

```lua
local ask = uji.ui.confirm
uji.ui.confirm = function(request)
  io.stdout:write("\a")
  return ask(request)
end
```

## uji.ui.toggle_thinking()

Shows the model's reasoning in the transcript, or hides it again, and says
which in a notice. `/thinking` calls this.

```lua
uji.keymap.add("normal", "<C-t>", function()
  uji.ui.toggle_thinking()
end)
```

## uji.ui.exec(cmd)

Hides uji, runs a program in the terminal, and comes back when it exits.
`cmd` is a string, run through `sh -c`, or a list of the program and its
arguments.

```lua
uji.ui.exec("git log --oneline | less")
```

## uji.ui.configure(opts)

Sets colours and screen behaviour. Each call changes only the keys it names.
Raises an error for an unknown key or an invalid colour.

```lua
uji.ui.configure({
  theme = { accent = "#c65036", user_bg = "#2b2b2b" },
  input = { cursor_blink = false },
  waiting = { loader = { frames = { "-", "\\", "|", "/" }, interval = 0.1 } },
  confirm = { title = "Run this?", yes = "Run", no = "Skip" },
})
```

| Key | Meaning | Default |
|---|---|---|
| `show_thinking` | Show the model's reasoning. `/thinking` toggles it. | `false` |
| `input.cursor_blink` | Blink the cursor on the input line. | `true` |
| `suggest.enabled` | Show command suggestions when you type `/`. | `true` |
| `suggest.max_height` | Rows the suggestion list may use. | `5` |
| `waiting.loader.frames` | Strings the loader cycles through while the model works. | none |
| `waiting.loader.interval` | Seconds between loader frames. | `0.08` |
| `confirm.title` | The approval question's title. | `"Allow tool call?"` |
| `confirm.yes` | The allow label. | `"Yes"` |
| `confirm.no` | The deny label. | `"No"` |
| `theme.text` | Body text. | `#d4d4d4` |
| `theme.muted` | Secondary text and borders. | `#808080` |
| `theme.code` | Inline code. | `#e0af68` |
| `theme.accent` | Highlights. | `cyan` |
| `theme.user_bg` | The background of your messages. | `#343541` |
| `theme.selected_bg` | The selected row in lists. | `#3a3a4a` |
| `theme.cursor` | The cursor. | `white` |
| `theme.error` | Errors. | `red` |
| `theme.notice` | Notices. | `red` |
| `theme.input` | Text on the input line. | `theme.text` |
| `theme.confirm_title` | The approval question's title. | `theme.text` |
| `theme.confirm_body` | The approval question's details. | `theme.text` |
| `theme.confirm_selected` | The chosen answer. | the default style |
| `theme.confirm_unselected` | The other answer. | the default style |

## Colours

A colour is `#rrggbb` or one of `black`, `red`, `green`, `yellow`, `blue`,
`magenta`, `cyan`, `white`, `gray`, `dark_gray`, `light_red`, `light_green`,
`light_yellow`, `light_blue`, `light_magenta` and `light_cyan`. `grey` and
`dark_grey` also work.
