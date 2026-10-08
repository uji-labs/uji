local ito = require("ito")
local list = require("uji.utils.list")
local Query = require("uji.core.ui.pickers.query")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, plain = ctx.styles, ctx.borders.plain
    local prompt = ctx.symbols.prompt
    local function results()
        return ito.List(props.matches, function(match, _, active)
            local item = props.items[match]
            local style = active and styles.chosen or styles.text
            local spans = { { item, style } }
            if item == props.current then
                spans[2] = { " " .. ctx.text.current, active and style or styles.muted }
            end
            return ito.HStack({
                ito.Text(prompt):style(style):padding({ trailing = 1 }):background(style):invisible(not active),
                ito.Text(spans):grow(),
            })
        end)
            :selection(props.selection)
            :passive()
            :border(plain)
            :title({ { props.title, styles.accent } })
    end
    local function preview()
        return ito.Text(table.concat(list.mapped(props.preview, tostring), "\n")):style(styles.muted):border(plain)
    end
    return ito.VStack({
        ito.SubcomposeLayout(function(room)
            if room.width < ctx.limits.preview_min * 2 then
                return results()
            end
            return ito.HStack({ results():share(0.5), preview():grow() })
        end):grow(),
        ito.HStack({
            Query({ field = props.query }),
            ito.Text(string.format("%d/%d", #props.matches, props.total)):style(styles.dim),
        })
            :spacing(3)
            :border(plain),
    })
end)
