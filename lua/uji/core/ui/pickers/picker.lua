local ito = require("ito")
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
    local results = ito.List(props.matches, function(match, _, active)
        local item = props.items[match]
        if active then
            return ito.Text(ctx.symbols.prompt .. " " .. item):style(styles.chosen)
        end
        return ito.Text("  " .. item):style(styles.text)
    end)
        :selection(props.selection)
        :passive()
        :border(plain)
        :title({ { " " .. props.title .. " ", styles.accent } })
        :width(split)
    local preview = {}
    for index, line in ipairs(props.preview) do
        preview[index] = { { tostring(line), styles.muted } }
    end
    return ito.VStack({
        ito.HStack({ results, ito.Lines(preview):border(plain):grow() }):grow(),
        ito.HStack({
            Query({ marker = "", field = props.query }),
            ito.Text(string.format("   %d/%d", #props.matches, props.total)):style(styles.dim),
        })
            :border(plain)
            :height(PROMPT_ROWS),
    })
end)
