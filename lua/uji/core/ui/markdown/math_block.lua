local ito = require("ito")

return ito.view(function(props)
    return ito.HStack({
        ito.Spacer():width(2),
        ito.Text(table.concat(props.lines, "\n")):style(ito.theme().styles.code):grow(),
    })
end)
