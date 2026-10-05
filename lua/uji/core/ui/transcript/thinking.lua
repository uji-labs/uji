local ito = require("ito")
local Wrapped = require("uji.core.ui.transcript.wrapped")

return ito.view(function(props)
    local ctx = ito.theme()
    return Wrapped({ text = props.text, prefix = " " .. ctx.symbols.thinking .. " ", style = ctx.styles.faint })
end)
