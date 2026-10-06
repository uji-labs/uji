local ito = require("ito")

local function lines(width, ctx)
    local label = " " .. ctx.text.compacted .. " "
    local bar = string.rep(ctx.symbols.rule, math.floor(math.max(width - ctx:measure(label) - 2, 0) / 2))
    return { { { " " .. bar .. label .. bar, ctx.styles.dim } } }
end

return ito.view(function()
    return ito.Lines(lines, ito.theme())
end)
