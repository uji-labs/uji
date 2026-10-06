local ito = require("ito")

local function lines(width, value)
    local ctx, props = value.ctx, value.props
    local style = props.failed and ctx.styles.error or ctx.styles.muted
    local branch = "   " .. ctx.symbols.branch .. " "
    local indent = string.rep(" ", ctx:measure(branch))
    local limit = not props.expanded and ctx.limits.tool_preview or nil
    local rows, hidden = ctx:fold(props.content, { width = math.max(width - ctx:measure(branch), 1), limit = limit })
    local toggle = (props.expanded or hidden > 0) and props.toggle or nil
    local out = {}
    for index, row in ipairs(rows) do
        out[index] = { { (index == 1 and branch or indent) .. row, style }, on_click = toggle }
    end
    if hidden > 0 then
        local more = indent .. ctx.symbols.more .. " " .. string.format(ctx.text.hidden, hidden)
        out[#out + 1] = { { more, ctx.styles.dim }, on_click = toggle }
    end
    return out
end

return ito.view(function(props)
    return ito.Lines(lines, { ctx = ito.theme(), props = props })
end)
