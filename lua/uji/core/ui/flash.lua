local host = require("uji.core.ui.host")
local ito = require("ito")

return ito.view(function()
    local flashed = host.Host.current.flashed
    if not flashed then
        return nil
    end
    local reverse = ito.theme().styles.reverse
    return ito.Text(flashed.text):style(reverse):padding({ horizontal = 1 }):background(reverse)
end)
