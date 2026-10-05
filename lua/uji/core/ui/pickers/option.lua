local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local style = props.active and ctx.styles.confirm_selected or ctx.styles.confirm_unselected
    return ito.Lines({
        {
            { props.active and ctx.symbols.pointer .. " " or "  ", style },
            { props.index .. ". " .. props.label, style },
            { " (" .. props.key .. ")", ctx.styles.dim },
        },
    })
end)
