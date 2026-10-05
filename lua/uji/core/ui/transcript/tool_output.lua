local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local build = ito.remember(function()
        local style = props.failed and ctx.styles.error or ctx.styles.muted
        local branch = "   " .. ctx.symbols.branch .. " "
        local indent = string.rep(" ", ctx:measure(branch))
        return function(width)
            local limit = not props.expanded and ctx.limits.tool_preview or nil
            local rows, hidden = ctx:fold(props.content, { width = math.max(width - ctx:measure(branch), 1), limit = limit })
            local toggle = (props.expanded or hidden > 0) and props.toggle or nil
            local lines = {}
            for index, row in ipairs(rows) do
                lines[index] = { { (index == 1 and branch or indent) .. row, style }, on_click = toggle }
            end
            if hidden > 0 then
                local more = indent .. ctx.symbols.more .. " " .. string.format(ctx.text.hidden, hidden)
                lines[#lines + 1] = { { more, ctx.styles.dim }, on_click = toggle }
            end
            return lines
        end
    end, props.content, props.failed, props.expanded, ctx)
    return ito.Lines(build)
end)
