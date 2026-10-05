# A footer

A one-line footer with the model on the left and the tokens spent on the
right.

```lua
require("uji.builtin.defaults")

local ito = require("ito")

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
    local usage = uji.session.usage()
    return ito.HStack({
      ito.Text(uji.model.current().model or "no model"):foreground(ito.Color.cyan),
      ito.Spacer(),
      usage.total > 0 and ito.Text(usage.total .. " tokens"):foreground(ito.Color.gray),
    })
  end),
})
```

uji draws the footer again whenever the model, the session or the running
state changes.
