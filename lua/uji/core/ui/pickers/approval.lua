local Diff = require("uji.core.ui.transcript.diff")
local ito = require("ito")
local Option = require("uji.core.ui.pickers.option")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, words = ctx.styles, ctx.text
    local body = { ito.Text(props.body):style(styles.confirm_body):wrap():padding({ leading = 2 }) }
    if props.preview then
        body[2] = Diff({ diff = props.preview }):padding({ leading = 2 })
    end
    local scroll = props.scroll
    local hint = ito.SubcomposeLayout(function()
        if scroll.total <= scroll.page then
            return ito.Spacer():height(1)
        end
        local shown = string.format(words.scroll, scroll.offset + 1, scroll.offset + scroll.page, scroll.total)
        return ito.Text(shown):style(styles.dim):padding({ leading = 2 })
    end)
    return ito.VStack({
        ito.Spacer():height(1),
        ito.Text(props.title):style(styles.confirm_title):wrap():padding({ leading = 2 }),
        ito.Spacer():height(1),
        ito.ScrollView(ito.VStack(body)):state(scroll):shrink(),
        hint,
        Option({ index = 1, label = words.confirm_yes .. ", " .. words.confirm_allow, key = props.keys.allow, active = props.allow }),
        Option({ index = 2, label = words.confirm_no .. ", " .. words.confirm_deny, key = props.keys.deny, active = not props.allow }),
        ito.Spacer():height(1),
    })
end)
