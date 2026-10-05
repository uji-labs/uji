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
    local list = ito.List(props.matches, function(match, _, active)
        local item = props.items[match]
        local marker = active and ctx.symbols.pointer .. " " or "  "
        local line = { { marker .. item, active and styles.accent or styles.text } }
        if item == props.current then
            line[#line + 1] = { " " .. ctx.text.current, styles.muted }
        end
        return ito.Lines({ line })
    end)
        :selection(props.selection)
        :passive()
    if count > visible then
        list:footer(function(first, last, total)
            return ito.Text("  " .. string.format(ctx.text.range, first, last, total)):style(styles.dim)
        end)
    end
    return ito.VStack({
        Titled({ title = props.title, field = props.query }),
        list:height(visible + (count > visible and 1 or 0)),
    })
end)
