local ito = require("ito")

local function lines(width, ctx)
    return { { { string.rep(ctx.symbols.rule, math.min(width, ctx.limits.rule_width)), ctx.styles.muted } } }
end

return ito.view(function()
    return ito.Lines(lines, ito.theme())
end)
