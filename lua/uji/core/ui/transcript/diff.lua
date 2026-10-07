local branch = require("uji.core.ui.transcript.branch")
local highlight = require("uji.core.ui.markdown.highlight")
local ito = require("ito")

local text = ito.text

local TAB = "    "
local SIGNS = { context = " ", removed = "-", added = "+" }

local function looks(styles)
    local diff = styles.diff
    return {
        context = { sign = styles.dim },
        removed = { sign = diff.removed_sign, fill = diff.removed, word = diff.removed_word },
        added = { sign = diff.added_sign, fill = diff.added, word = diff.added_word },
    }
end

local function expanded(value)
    return (value:gsub("\t", TAB))
end

local function source(line)
    local out = {}
    for index, part in ipairs(line.parts) do
        out[index] = expanded(part.text)
    end
    return table.concat(out)
end

local function marked(line)
    local changed, kept = false, false
    for _, part in ipairs(line.parts) do
        changed = changed or part.changed
        kept = kept or not part.changed
    end
    return changed and kept
end

local function overlay(spans, line, word)
    local bounds, offset = {}, 0
    for _, part in ipairs(line.parts) do
        offset = offset + #expanded(part.text)
        bounds[#bounds + 1] = { offset, part.changed }
    end
    local out, position, at = {}, 0, 1
    for _, span in ipairs(spans) do
        local rest = span[1]
        while rest ~= "" do
            local bound = bounds[at]
            local taken = rest:sub(1, bound[1] - position)
            out[#out + 1] = { taken, bound[2] and span[2]:merge(word) or span[2] }
            position = position + #taken
            rest = rest:sub(#taken + 1)
            if position >= bound[1] and at < #bounds then
                at = at + 1
            end
        end
    end
    return out
end

local function painted(line, look, highlighter, styles)
    local raw = source(line)
    local spans = (line.kind ~= "removed" and highlighter) and highlighter:line(raw) or { { raw, styles.text } }
    if look.fill then
        for index, span in ipairs(spans) do
            spans[index] = { span[1], span[2]:merge(look.fill) }
        end
    end
    if look.word and marked(line) then
        return overlay(spans, line, look.word)
    end
    return spans
end

local function digits(diff)
    local most = 0
    for _, change in ipairs(diff.changes) do
        for _, line in ipairs(change) do
            most = math.max(most, line.old or 0, line.new or 0)
        end
    end
    return #tostring(most)
end

local function measured(spans)
    local used = 0
    for _, span in ipairs(spans) do
        used = used + text.width(span[1])
    end
    return used
end

local function rows(ctx, diff, indent, width)
    local styles = ctx.styles
    local look = looks(styles)
    local numbers = digits(diff)
    local gutter = string.rep(" ", numbers + 4)
    local room = math.max(width - text.width(indent) - #gutter, 1)
    local extension = diff.path and (diff.path:match("%.([%w_+#-]+)$") or diff.path:match("[^/]+$"))
    local out = {}
    for index, change in ipairs(diff.changes) do
        if index > 1 then
            out[#out + 1] = { { indent .. ctx.symbols.more, styles.dim } }
        end
        local highlighter = highlight.new(extension, styles)
        for _, line in ipairs(change) do
            local style = look[line.kind]
            local number = tostring(line.kind == "removed" and line.old or line.new)
            local head = " " .. string.rep(" ", numbers - #number) .. number .. " " .. SIGNS[line.kind] .. " "
            for at, piece in ipairs(ito.spans.wrap(painted(line, style, highlighter, styles), room)) do
                local row = { { indent }, { at == 1 and head or gutter, style.fill and style.sign or styles.dim } }
                for _, span in ipairs(piece) do
                    row[#row + 1] = span
                end
                if style.fill then
                    row[#row + 1] = { string.rep(" ", room - measured(piece)), style.fill }
                end
                out[#out + 1] = row
            end
        end
    end
    return out
end

local function lines(width, value)
    local ctx, props = value.ctx, value.props
    local out = rows(ctx, props.diff, props.indent, width)
    local hidden = props.limit and math.max(#out - props.limit, 0) or 0
    for index = #out, #out - hidden + 1, -1 do
        out[index] = nil
    end
    for _, row in ipairs(out) do
        row.on_click = props.toggle
    end
    if hidden > 0 then
        out[#out + 1] = branch.hidden(ctx, props.indent, hidden, props.toggle)
    end
    return out
end

return ito.view(function(props)
    return ito.Lines(lines, { ctx = ito.theme(), props = props })
end)
