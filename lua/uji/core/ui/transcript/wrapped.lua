local ito = require("ito")

return ito.view(function(props)
    local text = ito.Text(props.text):style(props.style):wrap():grow()
    return ito.HStack({
        props.mark ~= nil and ito.Text(props.mark):style(props.style):repeating(),
        props.fill and text:padding({ trailing = 1 }) or text,
    })
        :spacing(1)
        :padding({ leading = 1 })
end)
