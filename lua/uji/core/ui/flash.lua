local host = require("uji.core.ui.host")
local ito = require("ito")

return ito.view(function()
    local flashed = host.Host.current.flashed
    if not flashed then
        return nil
    end
    return ito.Text(" " .. flashed.text .. " "):style(ito.theme().styles.reverse)
end)
