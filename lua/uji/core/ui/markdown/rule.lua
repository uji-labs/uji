local ito = require("ito")

return ito.view(function()
    local ctx = ito.theme()
    return ito.HStack({ ito.Text(ctx.symbols.rule):style(ctx.styles.muted):repeating():width(ctx.limits.rule_width) })
end)
