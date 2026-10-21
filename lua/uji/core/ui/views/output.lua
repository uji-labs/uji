local ito = require("ito")

return ito.view(function(props)
    local ctx, job = ito.theme(), props.job
    return ito.VStack({
        ito.Spacer():height(1),
        ito.Text(props.name .. "  " .. job:status()):style(ctx.styles.confirm_title):wrap():padding({ leading = 2 }),
        ito.Spacer():height(1),
        ito.Text(job:tail()):style(ctx.styles.dim):wrap():padding({ leading = 2 }),
        ito.Spacer():height(1),
    })
end)
