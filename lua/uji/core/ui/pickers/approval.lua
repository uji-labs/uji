local Diff = require("uji.core.ui.transcript.diff")
local ito = require("ito")
local Option = require("uji.core.ui.pickers.option")

local function rows(text, style)
    local lines = {}
    for index, chunk in ipairs(text) do
        lines[index] = { { "  " .. chunk, style } }
    end
    return lines
end

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, words = ctx.styles, ctx.text
    local inner = math.max(props.width - 2, 1)
    local head = rows(ctx:chunks(props.title, inner), styles.confirm_title)
    local body = { ito.Lines(rows(ctx:chunks(props.body, inner), styles.confirm_body)) }
    if props.preview then
        body[2] = Diff({ diff = props.preview, indent = "  " })
    end
    local scroll = props.scroll
    local hint = ito.SubcomposeLayout(function()
        if scroll.total <= scroll.page then
            return ito.Spacer():height(1)
        end
        local shown = string.format(words.scroll, scroll.offset + 1, scroll.offset + scroll.page, scroll.total)
        return ito.Text("  " .. shown):style(styles.dim)
    end)
    return ito.VStack({
        ito.Spacer():height(1),
        ito.Lines(head),
        ito.Spacer():height(1),
        ito.ScrollView(ito.VStack(body)):state(scroll):max_height(math.max(props.height - #head - 2 - 4, 1)),
        hint,
        Option({ index = 1, label = words.confirm_yes .. ", " .. words.confirm_allow, key = props.keys.allow, active = props.allow }),
        Option({ index = 2, label = words.confirm_no .. ", " .. words.confirm_deny, key = props.keys.deny, active = not props.allow }),
        ito.Spacer():height(1),
    })
end)
