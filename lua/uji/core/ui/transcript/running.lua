local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local prefix = " " .. ctx.symbols.running .. " "
    return ito.Lines(function(width)
        local value = props.name .. "  " .. ctx:clip(props.line, width)
        return ctx:wrap(value, { prefix = prefix, style = ctx.styles.dim, width = width })
    end)
end)
