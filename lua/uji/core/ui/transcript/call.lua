local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local look = ctx.styles.call
    local spans = { { props.label, look.label } }
    if props.detail and props.detail ~= "" then
        spans[2] = { "(" .. props.detail:gsub("\n", " ") .. ")", look.detail }
    end
    if props.note then
        spans[3] = { " " .. props.note, look.detail }
    end
    return ito.HStack({
        ito.Text(ctx.symbols.tool):style(look[props.status]):padding({ trailing = 1 }),
        ito.Text(spans):wrap():grow(),
    })
end)
