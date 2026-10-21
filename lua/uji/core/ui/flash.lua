local host = require("uji.core.ui.host")
local ito = require("ito")

return ito.view(function()
    local flashed = host.Host.current.flashed
    if not flashed then
        return nil
    end
    local ctx = ito.theme()
    if flashed.kind == "warning" then
        return ito.Text(flashed.text):style(ctx.styles.warning):padding({ horizontal = 1 })
    end
    return ito.Text(flashed.text):style(ctx.styles.reverse):padding({ horizontal = 1 }):background(ctx.styles.reverse)
end)
