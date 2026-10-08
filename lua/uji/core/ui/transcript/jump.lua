local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local style = ctx.styles.chosen_name
    return ito.Text(ctx.symbols.jump .. " " .. ctx.text.jump)
        :style(style)
        :padding({ horizontal = 1 })
        :background(style)
        :on_tap(props.follow)
end)
