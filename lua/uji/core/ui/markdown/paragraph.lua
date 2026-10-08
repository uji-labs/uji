local ito = require("ito")

local function spans(tokens)
    local out = {}
    for _, token in ipairs(tokens) do
        if token.spaced and #out > 0 then
            out[#out + 1] = { " " }
        end
        out[#out + 1] = { token.text, token.style }
    end
    return out
end

return ito.view(function(props)
    local ctx = ito.theme()
    local row = { ito.Spacer():width(props.indent) }
    if props.quote then
        row[#row + 1] = ito.Text(ctx.symbols.quote):repeating():padding({ trailing = 1 })
    end
    if props.marker then
        row[#row + 1] = ito.Text(props.marker):padding({ trailing = 1 })
    end
    row[#row + 1] = ito.Text(spans(props.tokens)):wrap():grow()
    return ito.HStack(row)
end)
