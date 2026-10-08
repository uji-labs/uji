local ito = require("ito")
local Titled = require("uji.core.ui.pickers.titled")

local HEAD = 4

return ito.view(function(props)
    local ctx = ito.theme()
    local styles = ctx.styles
    if props.height < HEAD then
        return nil
    end
    local count = #props.matches
    local visible = math.min(count, ctx.limits.select_rows, props.height - HEAD)
    local pointer = ctx.symbols.pointer
    local list = ito.List(props.matches, function(match, _, active)
        local item = props.items[match]
        local style = active and styles.accent or styles.text
        local spans = { { item, style } }
        if item == props.current then
            spans[2] = { " " .. ctx.text.current, styles.muted }
        end
        return ito.HStack({
            ito.Text(active and pointer or ""):style(style):width(ctx:measure(pointer) + 1),
            ito.Text(spans),
        })
    end)
        :selection(props.selection)
        :passive()
    if count > visible then
        list:footer(function(first, last, total)
            return ito.Text(string.format(ctx.text.range, first, last, total)):style(styles.dim):padding({ leading = 2 })
        end)
    end
    return ito.VStack({
        Titled({ title = props.title, field = props.query }),
        list:height(visible + (count > visible and 1 or 0)),
    })
end)
