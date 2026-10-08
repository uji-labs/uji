local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local style = props.active and ctx.styles.confirm_selected or ctx.styles.confirm_unselected
    local pointer = ctx.symbols.pointer
    return ito.HStack({
        ito.Text(props.active and pointer or ""):style(style):width(ctx:measure(pointer) + 1),
        ito.Text({ { props.index .. ". " .. props.label, style }, { " (" .. props.key .. ")", ctx.styles.dim } }),
    })
end)
