local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, limits = ctx.styles, ctx.limits
    local items = props.items
    local visible = math.max(math.min(#items, math.max(limits.suggest_rows, 1), props.height), 1)
    return ito.List(items, function(item, _, active)
        local row = ito.HStack({
            ito.Text(item.name):style(active and styles.chosen_name or styles.text):width(limits.suggest_name + 2):padding({ leading = 2 }),
            ito.Text(item.desc):style(active and styles.chosen_desc or styles.muted):grow(),
        })
        return active and row:background(ctx.colors.selected_bg) or row
    end)
        :selection(props.selection)
        :passive()
        :height(math.min(visible, #items))
end)
