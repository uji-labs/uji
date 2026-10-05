local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles = ctx.styles
    return ito.HStack({
        ito.Text(props.marker .. ctx.symbols.prompt .. " "):style(styles.accent),
        ito.Lines({ ctx:typed(props.field, { text = styles.text, cursor = styles.muted }) }),
    })
end)
