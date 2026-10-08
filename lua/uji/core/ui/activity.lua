local host = require("uji.core.ui.host")
local ito = require("ito")

return ito.view(function()
    local activity = host.Host.current.activity
    if not activity then
        return nil
    end
    local ctx = ito.theme()
    return ito.HStack({
        ito.Text(activity.frame):style(ctx.styles.accent):padding({ trailing = 1 }),
        ito.Text(string.format(ctx.text.working, activity.elapsed)):style(ctx.styles.muted),
    })
end)
