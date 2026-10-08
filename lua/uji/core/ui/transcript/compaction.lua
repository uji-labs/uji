local ito = require("ito")

return ito.view(function()
    local ctx = ito.theme()
    local dim = ctx.styles.dim
    return ito.HStack({
        ito.Text(ctx.symbols.rule):style(dim):repeating():grow(),
        ito.Text(ctx.text.compacted):style(dim):padding({ horizontal = 1 }),
        ito.Text(ctx.symbols.rule):style(dim):repeating():grow(),
    }):padding({ horizontal = 1 })
end)
