local ito = require("ito")
local Wrapped = require("uji.core.ui.transcript.wrapped")

return ito.view(function(props)
    local style = ito.theme().styles.user
    return ito.VStack({
        ito.Spacer():height(1):background(style),
        Wrapped({ text = props.message.text or "", prefix = " ", style = style, fill = true }),
        ito.Spacer():height(1):background(style),
    })
end)
