local ito = require("ito")
local list = require("uji.utils.list")

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
        ito.Text(values[2]):style(style):width(limits.sessions_updated),
        ito.Text(values[3]):style(style):width(limits.sessions_id),
    }):spacing(GAP)
end

local function hints(styles, entries)
    return ito.HStack(list.mapped(entries, function(entry)
        return ito.HStack({ ito.Text(entry[1]):style(styles.highlight), ito.Text(entry[2]):style(styles.muted) }):spacing(1)
    end)):spacing(3)
end

return ito.view(function(props)
    local ctx = ito.theme()
    local styles, words = ctx.styles, ctx.text
    local sessions = props.sessions
    local hint
    if #sessions == 0 then
        hint = hints(styles, { { words.key_quit, words.quit } })
    else
        hint = hints(styles, {
            { words.key_move, words.navigate },
            { words.key_open, words.resume },
            { words.key_quit, words.quit },
        })
    end
    local header = columns(ctx, { words.column_title, words.column_updated, words.column_id }, styles.muted:merge(styles.table_head))
    local listed = ito.Text(words.sessions_empty):style(styles.muted)
    if #sessions > 0 then
        listed = ito.List(sessions, function(session, _, chosen)
            local row =
                columns(ctx, { session.title, ago(props.now, session.updated), session.id }, chosen and styles.chosen or styles.text)
            return chosen and row:background(styles.selected) or row
        end)
            :selection(props.selection)
            :passive()
            :grow()
    end
    return ito.VStack({
        ito.VStack({ header, listed })
            :border(ctx.borders.plain, { color = ctx.colors.accent })
            :title(string.format(words.sessions_title, props.directory))
            :grow(),
        hint,
    })
end)
