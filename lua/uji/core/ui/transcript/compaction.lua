local ito = require("ito")

return ito.view(function()
    local ctx = ito.theme()
    local label = " " .. ctx.text.compacted .. " "
    return ito.Lines(function(width)
        local bar = string.rep(ctx.symbols.rule, math.floor(math.max(width - ctx:measure(label) - 2, 0) / 2))
        return { { { " " .. bar .. label .. bar, ctx.styles.dim } } }
    end)
end)
