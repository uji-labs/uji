local ito = require("ito")
local list = require("uji.utils.list")
local Query = require("uji.core.ui.pickers.query")

local PROMPT_ROWS = 3
local NARROWEST = 20

return ito.view(function(props)
    local ctx = ito.theme()
    if props.height < PROMPT_ROWS + 3 or props.width < NARROWEST then
        return nil
    end
    local styles, plain = ctx.styles, ctx.borders.plain
    local split = props.width < ctx.limits.preview_min * 2 and props.width or math.floor(props.width / 2)
    local prompt = ctx.symbols.prompt
    local results = ito.List(props.matches, function(match, _, active)
        local item = props.items[match]
        local style = active and styles.chosen or styles.text
        local spans = { { item, style } }
        if item == props.current then
            spans[2] = { " " .. ctx.text.current, active and style or styles.muted }
        end
        return ito.HStack({
            ito.Text(active and prompt or ""):style(style):width(ctx:measure(prompt) + 1):background(style),
            ito.Text(spans):grow(),
        })
    end)
        :selection(props.selection)
        :passive()
        :border(plain)
        :title({ { " " .. props.title .. " ", styles.accent } })
        :width(split)
    local preview = table.concat(list.mapped(props.preview, tostring), "\n")
    return ito.VStack({
        ito.HStack({ results, ito.Text(preview):style(styles.muted):border(plain):grow() }):grow(),
        ito.HStack({
            Query({ field = props.query }),
            ito.Text(string.format("%d/%d", #props.matches, props.total)):style(styles.dim):padding({ leading = 3 }),
        })
            :border(plain)
            :height(PROMPT_ROWS),
    })
end)
