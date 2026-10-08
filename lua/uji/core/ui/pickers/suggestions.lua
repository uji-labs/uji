local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, limits = ctx.styles, ctx.limits
    return ito.List(props.items, function(item, _, active)
        local row = ito.HStack({
            ito.Text(item.name):style(active and styles.chosen_name or styles.text):width(limits.suggest_name),
            ito.Text(item.desc):style(active and styles.chosen_desc or styles.muted):grow(),
        }):padding({ leading = 2 })
        return active and row:background(ctx.colors.selected_bg) or row
    end)
        :selection(props.selection)
        :passive()
        :max_height(limits.suggest_rows)
        :shrink()
end)
