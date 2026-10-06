local host = require("uji.core.ui.host")
local ito = require("ito")
local sys = require("uji.sys")

local RANK = { running = 1, failed = 2, queued = 3, done = 4 }
local COUNTED = { "running", "failed", "queued", "done" }

local function flat(text)
    return (text:gsub("%s+", " "))
end

local function seconds(task, now)
    if not task.started then
        return nil
    end
    local total = math.max(math.floor((task.finished or now) - task.started), 0)
    if total < 60 then
        return total .. "s"
    end
    return string.format("%dm%02ds", math.floor(total / 60), total % 60)
end

local function shown(tasks, limit)
    if #tasks <= limit then
        return tasks, {}
    end
    local ranked = {}
    for index, task in ipairs(tasks) do
        ranked[index] = { index = index, rank = RANK[task.status] or #COUNTED + 1 }
    end
    table.sort(ranked, function(left, right)
        if left.rank ~= right.rank then
            return left.rank < right.rank
        end
        return left.index < right.index
    end)
    local keep = {}
    for at = 1, math.max(limit - 1, 0) do
        keep[ranked[at].index] = true
    end
    local out, hidden = {}, {}
    for index, task in ipairs(tasks) do
        if keep[index] then
            out[#out + 1] = task
        else
            hidden[task.status] = (hidden[task.status] or 0) + 1
        end
    end
    return out, hidden
end

local function marker(ctx, status, frame)
    local symbols, styles = ctx.symbols, ctx.styles
    if status == "running" then
        return frame or symbols.running, styles.highlight
    elseif status == "failed" then
        return symbols.job_failed, styles.error
    elseif status == "done" then
        return symbols.job_done, styles.muted
    end
    return symbols.job_queued, styles.dim
end

local function about(ctx, task, now)
    local parts = {}
    if task.status == "queued" then
        parts[#parts + 1] = ctx.text.task_queued
    else
        parts[#parts + 1] = seconds(task, now)
    end
    for _, field in ipairs({ task.detail or "", task.status == "running" and task.line or "" }) do
        if field:find("%S") then
            parts[#parts + 1] = flat(field)
        end
    end
    return table.concat(parts, ctx.text.task_separator)
end

local function row(ctx, task, indent, width, frame, now)
    local symbol, tone = marker(ctx, task.status, frame)
    local room = math.max(width - ctx:measure(indent .. symbol .. " "), 1)
    local label = ctx:clip(flat(task.label), math.max(math.floor(room / 2), math.min(room, 24)))
    local rest = ctx:clip(about(ctx, task, now), math.max(room - ctx:measure(label) - 2, 0))
    local style = task.status == "running" and ctx.styles.text or ctx.styles.muted
    return {
        { indent, ctx.styles.dim },
        { symbol .. " ", tone },
        { label, style },
        { rest ~= "" and "  " .. rest or "", ctx.styles.dim },
    }
end

local function summary(ctx, hidden, indent, width)
    local total, counts = 0, {}
    for _, status in ipairs(COUNTED) do
        local count = hidden[status]
        if count then
            total = total + count
            counts[#counts + 1] = count .. " " .. ctx.text["task_" .. status]
        end
    end
    if total == 0 then
        return nil
    end
    local text = string.format(ctx.text.tasks_more, total, table.concat(counts, ctx.text.task_separator))
    return { { ctx:clip(indent .. text, width), ctx.styles.dim } }
end

local function tree(ctx, tasks, width, frame, now)
    local base = string.rep(" ", ctx.limits.indent + 1)
    local visible, hidden = shown(tasks, ctx.limits.tasks)
    local out, group = {}, nil
    for _, task in ipairs(visible) do
        local indent = base
        if task.group and task.group ~= "" then
            if task.group ~= group then
                out[#out + 1] = { { ctx:clip(base .. flat(task.group), width), ctx.styles.bold } }
            end
            indent = base .. string.rep(" ", ctx.limits.indent)
        end
        group = task.group
        out[#out + 1] = row(ctx, task, indent, width, frame, now)
    end
    out[#out + 1] = summary(ctx, hidden, base, width)
    return out
end

local function lines(width, value)
    local ctx, props = value.ctx, value.props
    local text = props.name .. "  " .. ctx:clip(props.line, width)
    local out = ctx:wrap(text, { prefix = " " .. ctx.symbols.running .. " ", style = ctx.styles.dim, width = width })
    for _, line in ipairs(tree(ctx, props.tasks or {}, width, value.frame, value.now)) do
        out[#out + 1] = line
    end
    return out
end

return ito.view(function(props)
    local activity = host.Host.current.activity
    return ito.Lines(lines, { ctx = ito.theme(), props = props, frame = activity and activity.frame, now = sys.os.clock() })
end)
