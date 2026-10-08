local ito = require("ito")

local M = {}

function M.mark(ctx)
    return ito.Text(ctx.symbols.branch):style(ctx.styles.muted):padding({ leading = 2, trailing = 2 })
end

function M.hidden(ctx, count)
    return ito.Text(ctx.symbols.more .. " " .. string.format(ctx.text.hidden, count)):style(ctx.styles.dim)
end

return M
