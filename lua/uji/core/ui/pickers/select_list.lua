local ito = require("ito")
local Titled = require("uji.core.ui.pickers.titled")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles = ctx.styles
    local list = ito.List(props.matches, function(match, _, active)
        local item = props.items[match]
        local style = active and styles.accent or styles.text
        local spans = { { item, style } }
        if item == props.current then
            spans[2] = { " " .. ctx.text.current, styles.muted }
        end
        return ito.HStack({
            ito.Text(ctx.symbols.pointer):style(style):invisible(not active),
            ito.Text(spans),
        }):spacing(1)
    end)
        :selection(props.selection)
        :passive()
        :footer(function(first, last, total)
            return ito.HStack({
                ito.Text(ctx.symbols.pointer):invisible(),
                ito.Text(string.format(ctx.text.range, first, last, total)):style(styles.dim),
            }):spacing(1)
        end)
        :max_height(ctx.limits.select_rows)
        :shrink()
    return ito.VStack({
        Titled({ title = props.title, field = props.query }),
        list,
    })
end)
