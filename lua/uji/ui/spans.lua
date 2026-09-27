local text = require("uji.ui.text")

local M = {}

local function coalesce(cells)
    local spans = {}
    local current, parts = nil, {}
    for _, cell in ipairs(cells) do
        if cell[2] ~= current then
            if #parts > 0 then
                spans[#spans + 1] = { table.concat(parts), current }
                parts = {}
            end
            current = cell[2]
        end
        parts[#parts + 1] = cell[1]
    end
    if #parts > 0 then
        spans[#spans + 1] = { table.concat(parts), current }
    end
    return spans
end

function M.wrap(spans, width)
    if width <= 0 or #spans == 0 then
        return { spans }
    end
    local lines, current = {}, {}
    for _, span in ipairs(spans) do
        for char in span[1]:gmatch(text.CHAR) do
            if #current >= width then
                local space
                for index = #current, 1, -1 do
                    if current[index][1] == " " then
                        space = index
                        break
                    end
                end
                if space then
                    local rest = { unpack(current, space + 1) }
                    for index = #current, space + 1, -1 do
                        current[index] = nil
                    end
                    lines[#lines + 1] = coalesce(current)
                    current = rest
                else
                    lines[#lines + 1] = coalesce(current)
                    current = {}
                end
            end
            current[#current + 1] = { char, span[2] }
        end
    end
    if #current > 0 then
        lines[#lines + 1] = coalesce(current)
    end
    if #lines == 0 then
        lines[1] = spans
    end
    return lines
end

local function uniform_bg(spans)
    local bg
    for _, span in ipairs(spans) do
        local spec = span[2]
        if not spec or not spec.bg then
            return nil
        end
        if bg and bg ~= spec.bg then
            return nil
        end
        bg = spec.bg
    end
    return bg
end

function M.resolve(spans, width, styles)
    local out, used = {}, 0
    for index, span in ipairs(spans) do
        out[index] = { span[1], styles:get(span[2]) }
        used = used + text.width(span[1])
    end
    local bg = uniform_bg(spans)
    if bg and used < width then
        out[#out + 1] = { string.rep(" ", width - used), styles:get({ bg = bg }) }
    end
    return out
end

function M.lines(lines, width, wrap, styles, into)
    into = into or {}
    for _, line in ipairs(lines) do
        if wrap then
            for _, piece in ipairs(M.wrap(line, width)) do
                into[#into + 1] = M.resolve(piece, width, styles)
            end
        else
            into[#into + 1] = M.resolve(line, width, styles)
        end
    end
    return into
end

return M
