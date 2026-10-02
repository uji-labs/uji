# A footer

A one-line footer with the model and the tokens spent.

```lua
require("uji.builtin.defaults")

local footer = uji.ui.open_win({ split = "bottom", size = 1, priority = 10 })

uji.status.add("model", function()
  return { text = uji.status.model() or "no model", color = "cyan" }
end, { priority = 10 })

uji.status.add("tokens", function()
  local usage = uji.session.usage()
  if usage.total > 0 then
    return { text = usage.total .. " tokens", color = "gray" }
  end
end, { priority = 20 })

local function draw()
  local spans = {}
  for _, part in ipairs(uji.status.render()) do
    if #spans > 0 then
      spans[#spans + 1] = "  "
    end
    spans[#spans + 1] = part
  end
  uji.ui.set_lines(footer, { spans })
end

uji.on("status_changed", draw)
uji.on("message_appended", draw)
```
