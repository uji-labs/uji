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
    local body = rows(ctx:chunks(props.body, inner), styles.confirm_body)
    local room = math.max(props.height - #head - 2 - 4, 1)
    local hidden = #body - room
    local hint
    local shown = ito.Lines(body)
    if hidden > 0 then
        local offset = props.scroll:resolve(hidden)
        hint = ito.Text("  " .. string.format(words.scroll, offset + 1, offset + room, #body)):style(styles.dim)
        shown = ito.ScrollView(shown):state(props.scroll):height(room)
    end
    return ito.VStack({
        ito.Spacer():height(1),
        ito.Lines(head),
        ito.Spacer():height(1),
        shown,
        hint or ito.Spacer():height(1),
        Option({ index = 1, label = words.confirm_yes .. ", " .. words.confirm_allow, key = props.keys.allow, active = props.allow }),
        Option({ index = 2, label = words.confirm_no .. ", " .. words.confirm_deny, key = props.keys.deny, active = not props.allow }),
        ito.Spacer():height(1),
    })
end)
