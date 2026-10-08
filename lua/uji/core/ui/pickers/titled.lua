local ito = require("ito")
local Query = require("uji.core.ui.pickers.query")

return ito.view(function(props)
    return ito.VStack({
        ito.Spacer():height(1),
        ito.Text(props.title):style(ito.theme().styles.bold):padding({ leading = 2 }),
        ito.Spacer():height(1),
        Query({ indent = 2, field = props.field }),
    })
end)
