local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, limits = ctx.styles, ctx.limits
    local items = props.items
    local visible = math.max(math.min(#items, math.max(limits.suggest_rows, 1), props.height), 1)
    return ito.List(items, function(item, _, active)
        local name = "  " .. ctx:pad(item.name, limits.suggest_name)
        if active then
            local line = { { name, styles.chosen_name }, { item.desc, styles.chosen_desc } }
            return ito.Lines({ line }):background(ctx.colors.selected_bg)
        end
        return ito.Lines({ { { name, styles.text }, { item.desc, styles.muted } } })
    end)
        :selection(props.selection)
        :passive()
        :height(math.min(visible, #items))
end)
