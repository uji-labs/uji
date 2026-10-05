# statusline

Views for status lines. `setup` declares the default bar as a
[`bottom_bar` item](../ito/toolbars.md), with the directory, model, reasoning
effort, context use, tokens, cache hit rate and turns. Calling it again
replaces the bar.

```lua
require("statusline").setup()
```

## Segments

Each segment is an [ito view](../ito/views.md) that draws nothing while it has
nothing to show.

| View | Shows |
|---|---|
| `statusline.Cwd()` | The session's directory. |
| `statusline.Model()` | The provider and model. |
| `statusline.Effort()` | The reasoning effort, while reasoning is on. |
| `statusline.Context()` | The context use, in the theme's `notice` colour from 80%. |
| `statusline.Tokens()` | The tokens spent. |
| `statusline.Cache()` | The cache hit rate of the last request. |
| `statusline.Turns()` | The number of your messages. |
| `statusline.Logo()` | The uji logo while the session is empty. A screen shows it over the transcript with `screen.transcript():overlay(statusline.Logo())`. |

## statusline.Bar(children)

A one-row `ito.HStack` that puts a separator between neighbouring segments.
A segment that draws nothing gets none, and neither does an `ito.Spacer`, so
spacers split the bar into left, centre and right. `separator` in the props
changes the text between segments, `"  ·  "` by default.

`statusline.Default` is the bar `setup` adds.

```lua
local ito = require("ito")
local statusline = require("statusline")

local branch = ito.state("")
uji.job.start({
  cmd = { "git", "branch", "--show-current" },
  on_stdout = function(line)
    branch.value = line
  end,
})

local Branch = ito.view(function()
  return branch.value ~= "" and ito.Text(branch.value):foreground(ito.theme().colors.accent)
end)

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.keyboard, function()
    return statusline.Bar({ statusline.Model(), ito.Spacer(), statusline.Effort() })
  end),
  ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
    return statusline.Bar({ statusline.Cwd(), Branch(), ito.Spacer(), statusline.Context() })
  end),
})
```
