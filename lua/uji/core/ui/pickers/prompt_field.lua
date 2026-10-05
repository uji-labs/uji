local ito = require("ito")
local Titled = require("uji.core.ui.pickers.titled")

return ito.view(function(props)
    return Titled({ title = props.title, field = props.value })
end)
