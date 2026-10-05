local ito = require("ito")
local Query = require("uji.core.ui.pickers.query")

return ito.view(function(props)
    return ito.VStack({
        ito.Spacer():height(1),
        ito.Text("  " .. props.title):style(ito.theme().styles.bold),
        ito.Spacer():height(1),
        Query({ marker = "  ", field = props.field }),
    })
end)
