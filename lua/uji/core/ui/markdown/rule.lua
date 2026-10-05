local ito = require("ito")

return ito.view(function()
    local ctx = ito.theme()
    return ito.Lines(function(width)
        return { { { string.rep(ctx.symbols.rule, math.min(width, ctx.limits.rule_width)), ctx.styles.muted } } }
    end)
end)
