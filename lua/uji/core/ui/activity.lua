local host = require("uji.core.ui.host")
local ito = require("ito")

return ito.view(function()
    local activity = host.Host.current.activity
    if not activity then
        return nil
    end
    local styles = ito.theme().styles
    local waiting = string.format(ito.theme().text.working, activity.elapsed)
    return ito.Lines({ { { activity.frame .. " ", styles.accent }, { waiting, styles.muted } } })
end)
