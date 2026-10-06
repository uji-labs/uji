local ito = require("ito")

return ito.view(function(props)
    local styles = ito.theme().styles
    local rows = {}
    if props.language then
        rows[1] = ito.Text("  " .. props.language):style(styles.dim)
    end
    if #props.lines > 0 then
        rows[#rows + 1] = ito.Lines(props.lines):padding({ leading = 2 })
    end
    return ito.VStack(rows)
end)
