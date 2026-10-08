local ito = require("ito")
local Wrapped = require("uji.core.ui.transcript.wrapped")

return ito.view(function(props)
    return Wrapped({ text = props.text, style = ito.theme().styles.system })
end)
