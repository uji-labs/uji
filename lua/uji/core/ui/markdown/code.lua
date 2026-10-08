local highlight = require("uji.core.ui.highlight")
local ito = require("ito")

local function spans(lines, tokens, styles)
    local out = {}
    for index, line in ipairs(lines) do
        if index > 1 then
            out[#out + 1] = { "\n" }
        end
        local found = tokens[index]
        for _, span in ipairs(found and highlight.spans(found, styles) or { { line, styles.code } }) do
            out[#out + 1] = span
        end
    end
    return out
end

return ito.view(function(props)
    if #props.lines == 0 then
        return nil
    end
    local styles = ito.theme().styles
    local tokens = highlight.tokens(props.language, props.lines)
    return ito.Text(spans(props.lines, tokens, styles)):wrap():padding({ leading = 2 })
end)
