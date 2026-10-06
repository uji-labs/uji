local ito = require("ito")

local text = ito.text

local function wrapped(tokens, indent, hanging, width)
    local usable = math.max(width - text.width(indent), 1)
    local lines, spans, used, first = {}, { { indent } }, 0, true
    for _, token in ipairs(tokens) do
        local size = text.width(token.text)
        local gap = (token.spaced and used > 0) and 1 or 0
        if used > 0 and used + gap + size > usable then
            lines[#lines + 1] = spans
            spans, used, first = { { hanging } }, 0, false
        end
        if used > 0 and token.spaced then
            spans[#spans + 1] = { " " }
            used = used + 1
        end
        spans[#spans + 1] = { token.text, token.style }
        used = used + size
    end
    if used > 0 or not first then
        lines[#lines + 1] = spans
    end
    return lines
end

local function lines(width, props)
    return wrapped(props.tokens, props.indent, props.hanging, width)
end

return ito.view(function(props)
    return ito.Lines(lines, props)
end)
