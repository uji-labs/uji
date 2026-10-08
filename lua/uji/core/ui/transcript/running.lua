local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    return ito.HStack({
        ito.Text(ctx.symbols.running):style(ctx.styles.dim):padding({ leading = 1, trailing = 1 }):repeating(),
        ito.Text(props.name .. "  " .. props.line):style(ctx.styles.dim):grow(),
    })
end)
