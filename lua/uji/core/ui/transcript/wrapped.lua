local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local build = ito.remember(function()
        return function(width)
            return ctx:wrap(props.text, { prefix = props.prefix, style = props.style, fill = props.fill, width = width })
        end
    end, props.text, props.prefix, props.style, props.fill, ctx)
    return ito.Lines(build)
end)
