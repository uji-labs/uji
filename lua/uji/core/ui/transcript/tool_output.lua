local branch = require("uji.core.ui.transcript.branch")
local Diff = require("uji.core.ui.transcript.diff")
local ito = require("ito")

local function counts(diff)
    local added, removed = 0, 0
    for _, change in ipairs(diff.changes) do
        for _, line in ipairs(change) do
            added = added + (line.kind == "added" and 1 or 0)
            removed = removed + (line.kind == "removed" and 1 or 0)
        end
    end
    return added, removed
end

local function changed(words, diff)
    local added, removed = counts(diff)
    local parts = {}
    if added > 0 then
        parts[#parts + 1] = string.format(words.added, added, added == 1 and words.line or words.lines)
    end
    if removed > 0 then
        parts[#parts + 1] = string.format(words.removed, removed, removed == 1 and words.line or words.lines)
    end
    return (table.concat(parts, ", "):gsub("^%l", string.upper))
end

local function lines(width, value)
    local ctx, props = value.ctx, value.props
    local style = props.failed and ctx.styles.error or ctx.styles.muted
    local head, indent = branch.prefix(ctx)
    if props.summary and not props.expanded then
        return { { { head .. props.summary, style }, on_click = props.toggle } }
    end
    local limit = not props.expanded and ctx.limits.tool_preview or nil
    local rows, hidden = ctx:fold(props.content, { width = math.max(width - ctx:measure(head), 1), limit = limit })
    local toggle = (props.expanded or hidden > 0) and props.toggle or nil
    local out = {}
    for index, row in ipairs(rows) do
        out[index] = { { (index == 1 and head or indent) .. row, style }, on_click = toggle }
    end
    if hidden > 0 then
        out[#out + 1] = branch.hidden(ctx, indent, hidden, toggle)
    end
    return out
end

return ito.view(function(props)
    local ctx = ito.theme()
    if not props.diff or not props.diff.changes[1] then
        return ito.Lines(lines, { ctx = ctx, props = props })
    end
    local head, indent = branch.prefix(ctx)
    local line = ito.Text(head .. changed(ctx.text, props.diff)):style(ctx.styles.muted)
    return ito.VStack({
        props.toggle and line:on_tap(props.toggle) or line,
        Diff({
            diff = props.diff,
            indent = indent,
            limit = not props.expanded and ctx.limits.diff_preview or nil,
            toggle = props.toggle,
        }),
    })
end)
