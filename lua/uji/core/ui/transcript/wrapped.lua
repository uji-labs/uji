local ito = require("ito")

local function lines(width, value)
    local props = value.props
    return value.ctx:wrap(props.text, { prefix = props.prefix, style = props.style, fill = props.fill, width = width })
end

return ito.view(function(props)
    return ito.Lines(lines, { ctx = ito.theme(), props = props })
end)
