local ito = require("ito")

local GAP = 2
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

local function columns(ctx, values, style)
    local limits = ctx.limits
    return ito.HStack({
        ito.Text(values[1]):style(style):grow(),
        ito.Text(values[2]):style(style):width(limits.sessions_updated + GAP):padding({ leading = GAP }),
        ito.Text(values[3]):style(style):width(limits.sessions_id + GAP):padding({ leading = GAP }),
    })
end

local function keys(styles, pairs)
    local out = {}
    for index, pair in ipairs(pairs) do
        out[#out + 1] = ito.Text(pair[1]):style(styles.highlight)
        out[#out + 1] = ito.Text(pair[2]):style(styles.muted):padding({ leading = 1, trailing = index < #pairs and 3 or 0 })
    end
    return ito.HStack(out)
end

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, words = ctx.styles, ctx.text
    local sessions = props.sessions
    local hint
    if #sessions == 0 then
        hint = keys(styles, { { words.key_quit, words.quit } })
    else
        hint = keys(styles, {
            { words.key_move, words.navigate },
            { words.key_open, words.resume },
            { words.key_quit, words.quit },
        })
    end
    local rows = {
        columns(ctx, { words.column_title, words.column_updated, words.column_id }, styles.muted:merge(styles.table_head)),
    }
    if #sessions == 0 then
        rows[2] = ito.Text(words.sessions_empty):style(styles.muted)
    else
        local available = math.max(props.height - 3 - 1, 1)
        local start = 0
        if props.cursor > available then
            start = math.min(props.cursor - available, #sessions - available)
        end
        for at = start + 1, math.min(start + available, #sessions) do
            local session = sessions[at]
            local chosen = at == props.cursor
            local row =
                columns(ctx, { session.title, ago(props.now, session.updated), session.id }, chosen and styles.chosen or styles.text)
            rows[#rows + 1] = chosen and row:background(styles.selected) or row
        end
    end
    local title = " " .. string.format(words.sessions_title, props.directory) .. " "
    return ito.VStack({
        ito.VStack(rows):border(ctx.borders.plain, { color = ctx.colors.accent }):title(title):grow(),
        hint:height(1),
    })
end)
