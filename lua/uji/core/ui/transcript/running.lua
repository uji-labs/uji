local ito = require("ito")

local function lines(width, value)
    local ctx, props = value.ctx, value.props
    local text = props.name .. "  " .. ctx:clip(props.line, width)
    return ctx:wrap(text, { prefix = " " .. ctx.symbols.running .. " ", style = ctx.styles.dim, width = width })
end

return ito.view(function(props)
    return ito.Lines(lines, { ctx = ito.theme(), props = props })
end)
