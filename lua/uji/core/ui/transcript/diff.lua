local branch = require("uji.core.ui.transcript.branch")
local highlight = require("uji.core.ui.highlight")
local ito = require("ito")
local list = require("uji.utils.list")

local SIGNS = { context = " ", removed = "-", added = "+" }

local function looks(styles)
    local diff = styles.diff
    return {
        context = { sign = styles.dim },
        removed = { sign = diff.removed_sign, fill = diff.removed, word = diff.removed_word },
        added = { sign = diff.added_sign, fill = diff.added, word = diff.added_word },
    }
end

local function source(line)
    return table.concat(list.mapped(line.parts, function(part)
        return part.text
    end))
end

local function marked(line)
    local changed = #list.filtered(line.parts, function(part)
        return part.changed
    end)
    return changed > 0 and changed < #line.parts
end

local function overlay(spans, line, word)
    local bounds, offset = {}, 0
    for _, part in ipairs(line.parts) do
        offset = offset + #part.text
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

local function newer(diff)
    local kept = list.filtered(list.flattened(diff.changes), function(line)
        return line.kind ~= "removed"
    end)
    return list.mapped(kept, source)
end

local function painted(line, look, tokens, styles)
    local spans = tokens and highlight.spans(tokens, styles) or { { source(line), styles.text } }
    if look.word and marked(line) then
        return overlay(spans, line, look.word)
    end
    return spans
end

local function row(ctx, line, tokens)
    local look = looks(ctx.styles)[line.kind]
    local mark = look.fill and look.sign or ctx.styles.dim
    local number = tostring(line.kind == "removed" and line.old or line.new)
    local shown = ito.GridRow({
        ito.Text(number):style(mark):padding({ leading = 1 }):align(ito.Alignment.top_trailing),
        ito.Text(SIGNS[line.kind]):style(mark):padding({ horizontal = 1 }),
        ito.Text(painted(line, look, tokens, ctx.styles)):wrap():grow(),
    })
    return look.fill and shown:background(look.fill) or shown
end

return ito.view(function(props)
    local ctx = ito.theme()
    local diff = props.diff
    local path = diff.path
    local language = path and (path:match("%.([%w_+#-]+)$") or path:match("[^/\\]+$"))
    local tokens = highlight.tokens(language, newer(diff))
    local rows, seen = {}, 0
    for index, change in ipairs(diff.changes) do
        if index > 1 then
            rows[#rows + 1] = ito.Text(ctx.symbols.more):style(ctx.styles.dim)
        end
        for _, line in ipairs(change) do
            local coloured = false
            if line.kind ~= "removed" then
                seen = seen + 1
                coloured = tokens[seen]
            end
            rows[#rows + 1] = row(ctx, line, coloured)
        end
    end
    local folded = ito.Fold(ito.Grid(rows), {
        rows = props.limit,
        more = function(hidden)
            return branch.hidden(ctx, hidden)
        end,
    })
    return props.toggle and folded:on_tap(props.toggle) or folded
end)
