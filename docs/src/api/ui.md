# uji.ui

### uji.ui.open_win(opts)

Opens a window and returns its id. The default config opens three.

```lua
uji.ui.open_win({ view = "messages", split = "top", size = "fill", wrap = true })
uji.ui.open_win({ view = "input", split = "bottom", size = "auto", border = "horizontal" })
uji.ui.open_win({ view = "modal", split = "bottom", size = "auto" })
```

| Option | Values | Default |
|---|---|---|
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

### uji.ui.set_lines(id, lines)

Replaces a window's content. Each line is a list of spans. A span is a string,
or a table with `text` and any of `color`, `bg`, `bold`, `italic` and
`underline`. A line may also be a single span.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 2 })
uji.ui.set_lines(panel, {
  { { text = "build", bold = true }, " passing" },
  { text = "3 files changed", color = "gray" },
})
```

### uji.ui.clear(id)

Empties a window.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.clear(panel)
```

### uji.ui.set_size(id, size)

Changes a window's size to rows or columns, `"fill"` or `"auto"`.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 0 })
uji.ui.set_size(panel, 3)
```

### uji.ui.set_title(id, title)

Sets the title in a window's border, or removes it when `title` is `nil`.

```lua
local panel = uji.ui.open_win({ split = "right", size = 30, border = "plain" })
uji.ui.set_title(panel, "todo")
```

### uji.ui.close_win(id)

Closes a window and returns `true` if it was open.

```lua
local panel = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.close_win(panel)
```

### uji.ui.select(opts, on_done)

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

### uji.ui.pick(opts, on_done)

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

### uji.ui.prompt(opts, on_done)

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

### uji.ui.exec(cmd)

Hides uji, runs a program in the terminal, and comes back when it exits.
`cmd` is a string, run through `sh -c`, or a list of the program and its
arguments.

```lua
uji.ui.exec("git log --oneline | less")
```

### uji.ui.configure(opts)

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
