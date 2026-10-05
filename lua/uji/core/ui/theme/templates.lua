local ito = require("ito")

local M = {}

local function joined(...)
    local lines = {}
    for _, part in ipairs({ ... }) do
        for _, line in ipairs(part) do
            lines[#lines + 1] = line
        end
    end
    return lines
end

function M.screen(ctx, screen)
    local placement = ito.ToolbarPlacement
    return ito.VStack({
        ito.HStack({
            ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
            ito.Spacer(),
            ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
        }),
        screen.transcript():grow(),
        screen.activity():padding({ vertical = 1 }),
        screen.modals(),
        ito.ToolbarItems(placement.keyboard),
        screen.composer():border(ctx.borders.plain, { edges = ito.Edges.horizontal }),
        ito.ToolbarItems(placement.bottom_bar),
    })
end

function M.user(ctx, message)
    local style = ctx.styles.user
    local blank = { { string.rep(" ", ctx.width), style } }
    return joined({ blank }, ctx:wrap(message.text, { prefix = " ", style = style, fill = true }), { blank })
end

function M.assistant(ctx, message)
    local lines = joined(message.body)
    for _, call in ipairs(message.calls) do
        if message.text ~= "" then
            lines[#lines + 1] = {}
        end
        lines = joined(lines, ctx.templates.tool_header(ctx, call))
    end
    return lines
end

function M.tool_header(ctx, call)
    local called = ctx.text.called
    local head
    if call.verb and call.detail then
        head = call.verb .. " " .. call.detail
    elseif call.verb then
        head = call.verb .. " " .. call.name
    elseif call.detail then
        head = called .. " " .. call.name .. " " .. call.detail
    else
        head = called .. " " .. call.name .. " " .. ctx:first(call.arguments, ctx.limits.argument_preview)
    end
    local marker = " " .. ctx.symbols.tool .. " "
    local indent = string.rep(" ", ctx:measure(marker))
    local chunks = ctx:chunks((head:gsub("\n", " ")), math.max(ctx.width - ctx:measure(marker) - 1, 1))
    local lines = { { { marker, ctx.styles.muted }, { chunks[1] or "", ctx.styles.bold } } }
    for index = 2, #chunks do
        lines[index] = { { indent .. chunks[index], ctx.styles.text } }
    end
    return lines
end

function M.tool_output(ctx, output)
    local style = output.failed and ctx.styles.error or ctx.styles.muted
    local branch = "   " .. ctx.symbols.branch .. " "
    local indent = string.rep(" ", ctx:measure(branch))
    local width = math.max(ctx.width - ctx:measure(branch), 1)
    local limit = not output.expanded and ctx.limits.tool_preview or nil
    local rows, hidden = ctx:fold(output.content, { width = width, limit = limit })
    local toggle = (output.expanded or hidden > 0) and output.toggle or nil
    local lines = {}
    for index, row in ipairs(rows) do
        lines[index] = { { (index == 1 and branch or indent) .. row, style }, on_click = toggle }
    end
    if hidden > 0 then
        local more = indent .. ctx.symbols.more .. " " .. string.format(ctx.text.hidden, hidden)
        lines[#lines + 1] = { { more, ctx.styles.dim }, on_click = toggle }
    end
    return lines
end

function M.shell(ctx, run)
    local header = ctx.symbols.shell .. " " .. run.command
    if run.code ~= 0 then
        header = header .. "  (" .. ctx.text.exit .. " " .. tostring(run.code) .. ")"
    end
    local lines = ctx:wrap(header, { prefix = " ", style = ctx.styles.accent })
    if run.output == "" then
        return lines
    end
    local output = { content = run.output, failed = run.failed, expanded = run.expanded, toggle = run.toggle }
    return joined(lines, ctx.templates.tool_output(ctx, output))
end

function M.system(ctx, message)
    return ctx:wrap(message.text, { prefix = " ", style = ctx.styles.system })
end

function M.error(ctx, message)
    return ctx:wrap(message.text, { prefix = " ", style = ctx.styles.error })
end

function M.compaction(ctx)
    local label = " " .. ctx.text.compacted .. " "
    local bar = string.rep(ctx.symbols.rule, math.floor(math.max(ctx.width - ctx:measure(label) - 2, 0) / 2))
    return { { { " " .. bar .. label .. bar, ctx.styles.dim } } }
end

function M.notice(ctx, notice)
    return ctx:wrap(notice.text, { prefix = " " .. ctx.symbols.notice .. " ", style = ctx.styles.notice })
end

function M.thinking(ctx, thought)
    return ctx:wrap(thought.text, { prefix = " " .. ctx.symbols.thinking .. " ", style = ctx.styles.faint })
end

function M.queued(ctx, queued)
    return ctx:wrap(queued.text, { prefix = " " .. ctx.symbols.queued .. " ", style = ctx.styles.dim })
end

function M.partial(ctx, partial)
    return ctx:wrap(partial.text, { prefix = " ", style = ctx.styles.text })
end

function M.running(ctx, running)
    local value = running.name .. "  " .. ctx:clip(running.line, ctx.width)
    return ctx:wrap(value, { prefix = " " .. ctx.symbols.running .. " ", style = ctx.styles.dim })
end

function M.heading(_, heading)
    return heading.lines
end

function M.code_block(ctx, block)
    local lines = {}
    if block.language then
        lines[1] = { { "  " .. block.language, ctx.styles.dim } }
    end
    for _, spans in ipairs(block.lines) do
        lines[#lines + 1] = joined({ { "  ", ctx.styles.plain } }, spans)
    end
    return lines
end

function M.math_block(ctx, block)
    local lines = {}
    for index, line in ipairs(block.lines) do
        lines[index] = { { "  " .. line, ctx.styles.code } }
    end
    return lines
end

function M.table_row(ctx, row)
    local line = { { "  ", ctx.styles.plain } }
    for index, cell in ipairs(row.cells) do
        if index > 1 then
            line[#line + 1] = { " " .. ctx.symbols.column .. " ", ctx.styles.muted }
        end
        for _, span in ipairs(cell) do
            line[#line + 1] = row.head and { span[1], (span[2] or ctx.styles.plain):merge(ctx.styles.table_head) } or span
        end
    end
    return { line }
end

function M.rule(ctx)
    return { { { string.rep(ctx.symbols.rule, math.min(ctx.width, ctx.limits.rule_width)), ctx.styles.muted } } }
end

function M.flash(ctx, flash)
    return { { { " " .. flash.text .. " ", ctx.styles.reverse } } }
end

function M.input(ctx, input)
    local styles = ctx.styles
    local lines = {}
    for index, row in ipairs(input.rows) do
        if row.after then
            lines[index] = { { row.before, styles.input }, { ctx.symbols.cursor, styles.cursor }, { row.after, styles.input } }
        else
            lines[index] = { { row.before, styles.input } }
        end
    end
    return lines
end

local function query(ctx, field, marker)
    local styles = ctx.styles
    return joined(
        { { marker .. ctx.symbols.prompt .. " ", styles.accent } },
        ctx:typed(field, { text = styles.text, cursor = styles.muted })
    )
end

local function titled(ctx, title, field)
    return { {}, { { "  " .. title, ctx.styles.bold } }, {}, query(ctx, field, "  ") }
end

function M.select(ctx, select)
    local styles = ctx.styles
    local head = titled(ctx, select.title, select.query)
    if select.height < #head then
        return {}
    end
    local count = #select.matches
    local visible = math.min(count, ctx.limits.select_rows, select.height - #head)
    local list = ito.List(select.matches, function(match, _, active)
        local item = select.items[match]
        local marker = active and ctx.symbols.pointer .. " " or "  "
        local line = { { marker .. item, active and styles.accent or styles.text } }
        if item == select.current then
            line[#line + 1] = { " " .. ctx.text.current, styles.muted }
        end
        return ito.Lines({ line })
    end)
        :selection(select.selection)
        :passive()
    if count > visible then
        list:footer(function(first, last, total)
            return ito.Lines({ { { "  " .. string.format(ctx.text.range, first, last, total), styles.dim } } })
        end)
    end
    return ito.VStack({ ito.Lines(head), list:height(visible + (count > visible and 1 or 0)) })
end

function M.prompt(ctx, prompt)
    return titled(ctx, prompt.title, prompt.value)
end

function M.suggest(ctx, suggest)
    local styles, limits = ctx.styles, ctx.limits
    local items = suggest.items
    local visible = math.max(math.min(#items, math.max(limits.suggest_rows, 1), suggest.height), 1)
    return ito.List(items, function(item, _, active)
        local name = "  " .. ctx:pad(item.name, limits.suggest_name)
        if active then
            local line = { { name, styles.chosen_name }, { item.desc, styles.chosen_desc } }
            return ito.Lines({ line }):background(ctx.colors.selected_bg)
        end
        return ito.Lines({ { { name, styles.text }, { item.desc, styles.muted } } })
    end)
        :selection(suggest.selection)
        :passive()
        :height(math.min(visible, #items))
end

local function option(ctx, choice)
    local style = choice.active and ctx.styles.confirm_selected or ctx.styles.confirm_unselected
    return {
        { choice.active and ctx.symbols.pointer .. " " or "  ", style },
        { choice.index .. ". " .. choice.label, style },
        { " (" .. choice.key .. ")", ctx.styles.dim },
    }
end

function M.confirm(ctx, confirm)
    local styles, words = ctx.styles, ctx.text
    local inner = math.max(ctx.width - 2, 1)
    local head = { {} }
    for _, chunk in ipairs(ctx:chunks(confirm.title, inner)) do
        head[#head + 1] = { { "  " .. chunk, styles.confirm_title } }
    end
    head[#head + 1] = {}
    local body = {}
    for _, chunk in ipairs(ctx:chunks(confirm.body, inner)) do
        body[#body + 1] = { { "  " .. chunk, styles.confirm_body } }
    end
    local scroll = confirm.scroll
    local hint = scroll and { { "  " .. string.format(words.scroll, scroll.first, scroll.last, scroll.total), styles.dim } } or {}
    local foot = {
        hint,
        option(ctx, {
            index = 1,
            label = words.confirm_yes .. ", " .. words.confirm_allow,
            key = confirm.keys.allow,
            active = confirm.allow,
        }),
        option(ctx, {
            index = 2,
            label = words.confirm_no .. ", " .. words.confirm_deny,
            key = confirm.keys.deny,
            active = not confirm.allow,
        }),
        {},
    }
    return { head = head, body = body, foot = foot }
end

local PROMPT_ROWS = 3
local NARROWEST = 20

function M.pick(ctx, pick)
    if pick.height < PROMPT_ROWS + 3 or ctx.width < NARROWEST then
        return {}
    end
    local styles, plain = ctx.styles, ctx.borders.plain
    local split = ctx.width < ctx.limits.preview_min * 2 and ctx.width or math.floor(ctx.width / 2)
    local results = ito.List(pick.matches, function(match, _, active)
        local item = pick.items[match]
        if active then
            return ito.Lines({ { { ctx.symbols.prompt .. " " .. item, styles.chosen } } })
        end
        return ito.Lines({ { { "  " .. item, styles.text } } })
    end)
        :selection(pick.selection)
        :passive()
        :border(plain)
        :title({ { " " .. pick.title .. " ", styles.accent } })
        :width(split)
    local preview = {}
    for index, line in ipairs(pick.preview) do
        preview[index] = { { tostring(line), styles.muted } }
    end
    local count = { { string.format("   %d/%d", #pick.matches, pick.total), styles.dim } }
    return ito.VStack({
        ito.HStack({ results, ito.Lines(preview):border(plain):grow() }):grow(),
        ito.Lines({ joined(query(ctx, pick.query, ""), count) }):border(plain):height(PROMPT_ROWS),
    })
end

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

local function cell(ctx, value, width)
    return ctx:pad(ctx:clip(value, width), width)
end

local function session_row(ctx, values, style)
    local limits = ctx.limits
    local width = ctx.width - 2
    local title = math.max(width - limits.sessions_updated - limits.sessions_id - #GAP * 2, 0)
    local line = cell(ctx, values[1], title)
        .. GAP
        .. cell(ctx, values[2], limits.sessions_updated)
        .. GAP
        .. cell(ctx, values[3], limits.sessions_id)
    return { { ctx:clip(line, width), style } }
end

function M.sessions(ctx, data)
    local styles, words = ctx.styles, ctx.text
    local width = ctx.width - 2
    local header = { words.column_title, words.column_updated, words.column_id }
    local lines = { session_row(ctx, header, styles.muted:merge(styles.table_head)) }
    local sessions = data.sessions
    local hint
    if #sessions == 0 then
        lines[2] = { { words.sessions_empty, styles.muted } }
        hint = { { words.key_quit, styles.highlight }, { " " .. words.quit, styles.muted } }
    else
        local available = math.max(data.height - 3 - 1, 1)
        local start = 0
        if data.cursor > available then
            start = math.min(data.cursor - available, #sessions - available)
        end
        for at = start + 1, math.min(start + available, #sessions) do
            local session = sessions[at]
            local chosen = at == data.cursor
            local values = { session.title, ago(data.now, session.updated), session.id }
            local line = session_row(ctx, values, chosen and styles.chosen or styles.text)
            if chosen then
                line[2] = { string.rep(" ", math.max(width - ctx:measure(line[1][1]), 0)), styles.selected }
            end
            lines[#lines + 1] = line
        end
        hint = {
            { words.key_move, styles.highlight },
            { " " .. words.navigate .. "   ", styles.muted },
            { words.key_open, styles.highlight },
            { " " .. words.resume .. "   ", styles.muted },
            { words.key_quit, styles.highlight },
            { " " .. words.quit, styles.muted },
        }
    end
    local title = " " .. string.format(words.sessions_title, data.directory) .. " "
    return ito.VStack({
        ito.Lines(lines):border(ctx.borders.plain, { color = ctx.colors.accent }):title(title):grow(),
        ito.Lines({ hint }):height(1),
    })
end

function M.activity(ctx, activity)
    local waiting = string.format(ctx.text.working, activity.elapsed)
    return { { { activity.frame .. " ", ctx.styles.accent }, { waiting, ctx.styles.muted } } }
end

function M.jump(ctx, jump)
    local label = " " .. ctx.symbols.jump .. " " .. ctx.text.jump .. " "
    return { { { label, ctx.styles.chosen_name }, on_click = jump.follow } }
end

return M
