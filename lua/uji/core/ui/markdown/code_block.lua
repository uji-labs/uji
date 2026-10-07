local ito = require("ito")

local function wrapped(width, lines)
    local out = {}
    for _, line in ipairs(lines) do
        for _, row in ipairs(ito.spans.wrap(line, width)) do
            out[#out + 1] = row
        end
    end
    return out
end

return ito.view(function(props)
    local styles = ito.theme().styles
    local rows = {}
    if props.language then
        rows[1] = ito.Text("  " .. props.language):style(styles.dim)
    end
    if #props.lines > 0 then
        rows[#rows + 1] = ito.Lines(wrapped, props.lines):padding({ leading = 2 })
    end
    return ito.VStack(rows)
end)
