local ito = require("ito")

local GAP = "  "
local RECENT = 10
local MILLIS = 1000
local AGES = {
    { 60, 1, "second" },
    { 3600, 60, "minute" },
    { 86400, 3600, "hour" },
    { 604800, 86400, "day" },
    { 2592000, 604800, "week" },
    { 31536000, 2592000, "month" },
    { math.huge, 31536000, "year" },
}

local function ago(now, millis)
    local seconds = math.max(math.floor((now - (millis or 0)) / MILLIS), 0)
    if seconds < RECENT then
        return "now"
    end
    for _, unit in ipairs(AGES) do
        if seconds < unit[1] then
            local count = math.floor(seconds / unit[2])
            if count <= 1 then
                return (unit[3] == "hour" and "an " or "a ") .. unit[3] .. " ago"
            end
            return count .. " " .. unit[3] .. "s ago"
        end
    end
end

local function columns(ctx, values, width)
    local limits = ctx.limits
    local title = math.max(width - limits.sessions_updated - limits.sessions_id - #GAP * 2, 0)
    local widths = { title, limits.sessions_updated, limits.sessions_id }
    local cells = {}
    for index, value in ipairs(values) do
        cells[index] = ctx:pad(ctx:clip(value, widths[index]), widths[index])
    end
    return ctx:clip(table.concat(cells, GAP), width)
end

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, words = ctx.styles, ctx.text
    local sessions = props.sessions
    local hint
    if #sessions == 0 then
        hint = { { words.key_quit, styles.highlight }, { " " .. words.quit, styles.muted } }
    else
        hint = {
            { words.key_move, styles.highlight },
            { " " .. words.navigate .. "   ", styles.muted },
            { words.key_open, styles.highlight },
            { " " .. words.resume .. "   ", styles.muted },
            { words.key_quit, styles.highlight },
            { " " .. words.quit, styles.muted },
        }
    end
    local listed = ito.Lines(function(width)
        local header = { words.column_title, words.column_updated, words.column_id }
        local lines = { { { columns(ctx, header, width), styles.muted:merge(styles.table_head) } } }
        if #sessions == 0 then
            lines[2] = { { words.sessions_empty, styles.muted } }
            return lines
        end
        local available = math.max(props.height - 3 - 1, 1)
        local start = 0
        if props.cursor > available then
            start = math.min(props.cursor - available, #sessions - available)
        end
        for at = start + 1, math.min(start + available, #sessions) do
            local session = sessions[at]
            local chosen = at == props.cursor
            local row = columns(ctx, { session.title, ago(props.now, session.updated), session.id }, width)
            local line = { { row, chosen and styles.chosen or styles.text } }
            if chosen then
                line[2] = { string.rep(" ", math.max(width - ctx:measure(row), 0)), styles.selected }
            end
            lines[#lines + 1] = line
        end
        return lines
    end)
    local title = " " .. string.format(words.sessions_title, props.directory) .. " "
    return ito.VStack({
        listed:border(ctx.borders.plain, { color = ctx.colors.accent }):title(title):grow(),
        ito.Lines({ hint }):height(1),
    })
end)
