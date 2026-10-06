# uji.ui

## uji.ui.toolbar(items)

Declares toolbar items on uji's screen and gives back a handle. `items` is a
list of [`ito.ToolbarItem`](../ito/toolbars.md), and each one names the
section it belongs in. The theme's screen decides where each section sits.
The default screen shows them like this:

| Placement | Where |
|---|---|
| `ito.ToolbarPlacement.top_bar_leading` | The left end of the top row. |
| `ito.ToolbarPlacement.top_bar_trailing` | The right end of the top row. |
| `ito.ToolbarPlacement.keyboard` | Directly above the input line. |
| `ito.ToolbarPlacement.bottom_bar` | Under the input line, at the bottom of the screen. |

Items in one section stack in the order they were declared. A section with no
items takes no room.

An item draws again when something it reads changes: its
[state](../ito/state.md), or what it reads through `uji.session` and
`uji.model`.

| Handle | Meaning |
|---|---|
| `handle:remove()` | Takes the items off the screen, and returns `true` if they were on it. |

Raises an error when `items` is not a list of `ito.ToolbarItem`. An item that
raises an error draws nothing, and uji says why once in a notice.

```lua
local ito = require("ito")

local branch = ito.state("")
uji.job.start({
  cmd = { "git", "branch", "--show-current" },
  on_stdout = function(line)
    branch.value = line
  end,
})

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.keyboard, function()
    return ito.Text(branch.value):foreground(ito.Color.green):align(ito.Alignment.trailing)
  end),
})
```

The branch name sits at the right end of the row above the input, and it
redraws when the job sets `branch.value`, as
[State](../ito/state.md#itostateinitial) describes.

## uji.ui.size()

Returns the width and height of the terminal in cells, or nothing when the
screen is not open, as in `uji run`.

```lua
local width, height = uji.ui.size()
```

## uji.ui.select(opts, on_done)

Shows a list to choose from. `on_done` receives the chosen item, or `nil` if
you cancel. Without `on_done`, the call waits and returns the chosen item.

| Option | Type | Meaning |
|---|---|---|
| `title` | string | The title. |
| `items` | list of strings | The items to choose from. |
| `current` | string | The item in use. The list opens on it and labels it with the theme's `text.current`. |

```lua
uji.ui.select({ title = "Branch", items = { "main", "dev" }, current = "main" }, function(choice)
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
| `current` | string | The item in use. The list opens on it and labels it with the theme's `text.current`. |
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

## uji.ui.overlay(content, opts)

Shows `content`, a function that returns a [view](../ito/views.md), in a box
over the middle of the screen, and returns a handle. Esc closes it, and
so does Enter when no control in it uses the key.

| Option | Meaning | Default |
|---|---|---|
| `float` | `false` shows the box with the other pickers, above the input line on the default screen. A screen with no place for pickers floats it anyway. | `true` |

| Handle | Meaning |
|---|---|
| `handle:close(value)` | Closes the overlay and gives `value` to `wait`. |
| `handle:wait()` | Waits until the overlay closes, then returns the value `close` gave, or `nil` after Esc or Enter. |

Raises an error when `content` is not a function.

Overlays, pickers, prompts and approvals stack. Opening one keeps the ones
already open, and closing it shows the one under it again. Only the one on
top gets the keys, so a focused control on the screen or in a lower overlay
waits until the top one closes. The command suggestions are the exception:
they close when anything else opens.

The content can declare its own [toolbar items](../ito/toolbars.md) with
`:toolbar`. Items placed at `top_bar_leading` and `top_bar_trailing` show at
the top of the box, and items placed at `bottom_bar` show at its bottom.

```lua
local ito = require("ito")

uji.command.add("commands", {
  desc = "list every command",
  handler = function()
    uji.ui.overlay(function()
      local rows = {}
      for _, name in ipairs(uji.command.list()) do
        rows[#rows + 1] = ito.Text("/" .. name)
      end
      return ito.VStack(rows):padding({ horizontal = 1 }):border(ito.theme().borders.rounded):title("Commands")
    end)
  end,
})
```

[Controls](../ito/controls.md) has an overlay with a text field that returns
what you type.

## uji.ui.Markdown(text)

A view that draws `text` as markdown, the way the transcript draws replies.

```lua
local ito = require("ito")

uji.ui.overlay(function()
  return uji.ui.Markdown("# Release\n\n- tag `v0.4.0`\n- push the tag"):padding(1):border(ito.theme().borders.rounded)
end)
```

Raises an error when `text` is not a string.

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

Sets the theme and screen behaviour. Each call changes only the keys it names.
Raises an error for an unknown key or a theme with a mistake, and keeps the
theme in use.

```lua
local ito = require("ito")

uji.ui.configure({
  theme = require("uji.themes.default")({
    colors = { accent = ito.rgb(0xc65036), user_bg = ito.rgb(0x2b2b2b) },
  }),
  show_thinking = true,
})
```

| Key | Meaning | Default |
|---|---|---|
| `theme` | A theme name or a theme table. See [Themes](../configuration/themes.md). | `"default"` |
| `show_thinking` | Show the model's reasoning. `/thinking` toggles it. | `false` |
| `suggest.enabled` | Show command suggestions when you type `/`. | `true` |

The cursor, the spinner, the size of the suggestion list and the words of an
approval belong to the theme, under `styles`, `symbols`, `limits` and `text`, as
[Themes](../configuration/themes.md) describes.

## uji.ui.theme()

Returns the theme in use: its name, or the table you gave
`uji.ui.configure`.

```lua
local before = uji.ui.theme()
uji.ui.configure({ theme = "harbor" })
uji.ui.configure({ theme = before })
```

## uji.ui.save_theme(name)

Keeps `name` as your theme for the next time uji starts. It doesn't change the
theme in use, so call `uji.ui.configure` for that.

```lua
uji.ui.configure({ theme = "harbor" })
uji.ui.save_theme("harbor")
```

uji puts the saved theme on before it runs your config, so a theme your config
sets with `uji.ui.configure` still wins. When the saved theme no longer loads,
for example after you remove the pack it came from, uji shows a notice and
starts without it.

Raises an error when `name` is empty or not a string.
