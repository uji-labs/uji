local M = {}

function M.prefix(ctx)
    local branch = "   " .. ctx.symbols.branch .. " "
    return branch, string.rep(" ", ctx:measure(branch))
end

function M.hidden(ctx, indent, count, toggle)
    return { { indent .. ctx.symbols.more .. " " .. string.format(ctx.text.hidden, count), ctx.styles.dim }, on_click = toggle }
end

return M
