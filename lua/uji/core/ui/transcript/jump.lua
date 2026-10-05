local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local label = " " .. ctx.symbols.jump .. " " .. ctx.text.jump .. " "
    return ito.Text(label):style(ctx.styles.chosen_name):on_tap(props.follow)
end)
