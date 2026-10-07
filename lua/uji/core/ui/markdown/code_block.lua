local highlight = require("uji.core.ui.highlight")
local ito = require("ito")

local function wrapped(width, value)
    local out = {}
    for index, line in ipairs(value.lines) do
        local tokens = value.tokens[index]
        local spans = tokens and highlight.spans(tokens, value.styles) or { { line, value.styles.code } }
        for _, row in ipairs(ito.spans.wrap(spans, width)) do
            out[#out + 1] = row
        end
    end
    return out
end

return ito.view(function(props)
    local styles = ito.theme().styles
    local tokens = highlight.tokens(props.language, props.lines)
    local rows = {}
    if props.language then
        rows[1] = ito.Text("  " .. props.language):style(styles.dim)
    end
    if #props.lines > 0 then
        rows[#rows + 1] = ito.Lines(wrapped, { lines = props.lines, tokens = tokens, styles = styles }):padding({ leading = 2 })
    end
    return ito.VStack(rows)
end)
