local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local style = props.active and ctx.styles.confirm_selected or ctx.styles.confirm_unselected
    return ito.HStack({
        ito.Text(ctx.symbols.pointer):style(style):invisible(not props.active),
        ito.Text({ { props.index .. ". " .. props.label, style }, { " (" .. props.key .. ")", ctx.styles.dim } }),
    }):spacing(1)
end)
