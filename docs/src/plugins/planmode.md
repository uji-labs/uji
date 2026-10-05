# planmode

A read-only mode. The model investigates and writes a plan, then you accept
it, keep planning, or leave.

```lua
require("planmode").setup({ allow = { "npm test" } })
```

| Option | Meaning | Default |
|---|---|---|
| `allow` | Command prefixes that run without asking while planning. | none |
| `confirm` | `false` skips the accept picker at the end of a turn. | `true` |
| `badge` | `false` leaves `planmode.Badge` off the screen, for a bar that shows it itself. | `true` |
| `keys` | `false` leaves Ctrl+B unbound. | `true` |
| `priority` | The priority of its `before_tool` hook. | `10` |

Commands are `/plan`, `/plan <task>` and `/approve`. Ctrl+B toggles plan mode.

`planmode.Badge()` is a view that says `plan` while plan mode is on. planmode
declares it as a [`bottom_bar` item](../ito/toolbars.md), and a
[statusline](statusline.md) bar can show it instead:

```lua
local ito = require("ito")
local statusline = require("statusline")

require("planmode").setup({ badge = false })

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
    return statusline.Bar({ require("planmode").Badge(), statusline.Cwd(), ito.Spacer(), statusline.Context() })
  end),
})
```
