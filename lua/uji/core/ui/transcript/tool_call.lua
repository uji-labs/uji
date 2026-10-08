local calls = require("uji.core.ui.transcript.calls")
local ito = require("ito")

local function heading(ctx, call)
    local look = ctx.styles.call
    local spans = { { call.label or call.name, look.label } }
    local detail = call.detail or ctx:first(call.arguments, ctx.limits.argument_preview)
    if detail ~= "" then
        spans[2] = { "(" .. detail:gsub("\n", " ") .. ")", look.detail }
    end
    return spans
end

return ito.view(function(props)
    local ctx = ito.theme()
    return ito.HStack({
        ito.Text(ctx.symbols.tool):style(ctx.styles.call[props.status]):padding({ trailing = 1 }),
        ito.Text(heading(ctx, calls.describe(props.call))):wrap():grow(),
    })
end)
