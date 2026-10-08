local branch = require("uji.core.ui.transcript.branch")
local Diff = require("uji.core.ui.transcript.diff")
local ito = require("ito")
local list = require("uji.utils.list")

local function counted(lines, kind)
    return #list.filtered(lines, function(line)
        return line.kind == kind
    end)
end

local function changed(words, diff)
    local lines = list.flattened(diff.changes)
    local added, removed = counted(lines, "added"), counted(lines, "removed")
    local parts = {}
    if added > 0 then
        parts[#parts + 1] = string.format(words.added, added, added == 1 and words.line or words.lines)
    end
    if removed > 0 then
        parts[#parts + 1] = string.format(words.removed, removed, removed == 1 and words.line or words.lines)
    end
    return (table.concat(parts, ", "):gsub("^%l", string.upper))
end

local function tapped(view, toggle)
    return toggle and view:on_tap(toggle) or view
end

local function body(ctx, props)
    if props.diff and props.diff.changes[1] then
        return ito.VStack({
            tapped(ito.Text(changed(ctx.text, props.diff)):style(ctx.styles.muted), props.toggle),
            Diff({
                diff = props.diff,
                limit = not props.expanded and ctx.limits.diff_preview or nil,
                toggle = props.toggle,
            }),
        })
    end
    local style = props.failed and ctx.styles.error or ctx.styles.muted
    if props.summary and not props.expanded then
        return tapped(ito.Text(props.summary):style(style), props.toggle)
    end
    local folded = ito.Fold(ito.Text(props.content):style(style):wrap(), {
        rows = not props.expanded and ctx.limits.tool_preview or nil,
        more = function(hidden)
            return branch.hidden(ctx, hidden)
        end,
    })
    return tapped(folded, props.toggle)
end

return ito.view(function(props)
    local ctx = ito.theme()
    return ito.HStack({ branch.mark(ctx), body(ctx, props):grow() })
end)
