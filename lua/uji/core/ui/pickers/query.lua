local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles = ctx.styles
    return ito.HStack({
        ito.Text(ctx.symbols.prompt):style(styles.accent):padding({ leading = props.indent or 0, trailing = 1 }),
        ito.Text(ctx:typed(props.field, { text = styles.text, cursor = styles.muted })),
    })
end)
