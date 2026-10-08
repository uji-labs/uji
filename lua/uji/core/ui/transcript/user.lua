local ito = require("ito")
local Wrapped = require("uji.core.ui.transcript.wrapped")

return ito.view(function(props)
    local style = ito.theme().styles.user
    return Wrapped({ text = props.message.text or "", style = style, fill = true }):padding({ vertical = 1 }):background(style)
end)
