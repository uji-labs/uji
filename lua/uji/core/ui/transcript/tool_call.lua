local calls = require("uji.core.ui.transcript.calls")
local ito = require("ito")

local function heading(ctx, call)
    local called = ctx.text.called
    if call.verb and call.detail then
        return call.verb .. " " .. call.detail
    elseif call.verb then
        return call.verb .. " " .. call.name
    elseif call.detail then
        return called .. " " .. call.name .. " " .. call.detail
    end
    return called .. " " .. call.name .. " " .. ctx:first(call.arguments, ctx.limits.argument_preview)
end

return ito.view(function(props)
    local ctx = ito.theme()
    local build = ito.remember(function()
        local head = heading(ctx, calls.describe(props.call)):gsub("\n", " ")
        local marker = " " .. ctx.symbols.tool .. " "
        local indent = string.rep(" ", ctx:measure(marker))
        return function(width)
            local chunks = ctx:chunks(head, math.max(width - ctx:measure(marker) - 1, 1))
            local lines = { { { marker, ctx.styles.muted }, { chunks[1] or "", ctx.styles.bold } } }
            for index = 2, #chunks do
                lines[index] = { { indent .. chunks[index], ctx.styles.text } }
            end
            return lines
        end
    end, props.call, ctx)
    return ito.Lines(build)
end)
