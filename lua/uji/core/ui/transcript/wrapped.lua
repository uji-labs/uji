local ito = require("ito")

return ito.view(function(props)
    local text = ito.Text(props.text):style(props.style):wrap():grow()
    return ito.HStack({
        ito.Text(props.mark or ""):style(props.style):padding({ leading = 1, trailing = props.mark and 1 or 0 }):repeating(),
        props.fill and text:padding({ trailing = 1 }) or text,
    })
end)
