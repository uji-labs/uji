local ito = require("ito")

local text = ito.text

local function wrapped(tokens, indent, hanging, width)
    if #tokens == 0 then
        return {}
    end
    local line = {}
    for _, token in ipairs(tokens) do
        if token.spaced and #line > 0 then
            line[#line + 1] = { " " }
        end
        line[#line + 1] = { token.text, token.style }
    end
    local rows = ito.spans.wrap(line, math.max(width - text.width(indent), 1))
    for index, row in ipairs(rows) do
        table.insert(row, 1, { index == 1 and indent or hanging })
    end
    return rows
end

local function lines(width, props)
    return wrapped(props.tokens, props.indent, props.hanging, width)
end

return ito.view(function(props)
    return ito.Lines(lines, props)
end)
