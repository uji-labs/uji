local app = require("uji.core.app")
local Blocks = require("uji.core.ui.blocks")
local class = require("uji.core.class")
local layout = require("ito").layout
local text = require("ito").text
local Transcript = require("uji.core.ui.transcript")

local function split_committed(pending)
    local at = pending:find("\n[^\n]*$")
    if not at then
        return "", pending
    end
    return pending:sub(1, at), pending:sub(at + 1)
end

local function follow(ui)
    ui.scroll:follow()
end

local function append(into, lines)
    for _, line in ipairs(lines) do
        into[#into + 1] = line
    end
end

local function gap(into, rows)
    for _ = 1, rows do
        into[#into + 1] = {}
    end
end

local function width_of(line)
    local total = 0
    for _, span in ipairs(line) do
        total = total + text.width(span[1])
    end
    return total
end

local Messages = class()

function Messages:init()
    self.blocks = Blocks()
    self.transcript = Transcript(self.blocks)
end

function Messages:draw(ui, area, ctx)
    local limits = ctx.limits
    local inner = layout.rect(area.x, area.y, area.width, area.height)
    local floor = inner.y + inner.height - 1
    inner.height = math.max(inner.height - limits.bottom_gap, 0)
    local width, height = inner.width, inner.height
    local split = not self.blocks:prepare(ctx, width)
    local committed, partial = split_committed(ui.stream:visible())
    local parts = self.transcript:frame({
        entries = app.session and app.session:entries() or {},
        notices = ui.notices,
        queued = app.agent and app.agent.queue or {},
        thinking = ui.theme.show_thinking,
        pending = committed,
        reasoning = ui.reasoning,
        width = width,
        revision = ui.theme.revision,
        split = split,
        want = height + (ui.scroll.anchor or 0),
    })
    if parts.toggled then
        ui.scroll.anchor = ui.scroll.anchor or 0
    end
    if parts.prepended then
        self.base = self.base + parts.prepended
    else
        self.base, self.pane = 0, {}
    end

    local tail = {}
    if partial ~= "" then
        tail = ctx:element("partial", { text = partial }, width)
    end
    local live = 0
    for _, lines in ipairs(parts.live) do
        live = live + #lines
    end
    local lead = {}
    if (live > 0 or #tail > 0) and #parts.folded > 0 then
        gap(lead, limits.section_gap)
    end

    local below = {}
    local running = ui.running
    if running then
        gap(below, limits.section_gap)
        append(below, ctx:element("running", { name = running.name, line = running.line }, width))
    end
    if #parts.queued > 0 then
        gap(below, limits.section_gap)
        append(below, parts.queued)
    end
    local notes = {}
    if #parts.notices > 0 then
        gap(notes, limits.section_gap)
        append(notes, parts.notices)
    end

    local body = math.max(height - #below - #notes, 0)
    local segments = { parts.folded, lead, parts.live[1], parts.live[2], parts.live[3], parts.live[4], tail }
    local total = 0
    for _, lines in ipairs(segments) do
        total = total + #lines
    end
    local start = ui.scroll:resolve(math.max(total - body, 0), body, parts.prepended)
    local finish = math.min(start + body, total)

    local rows = {}
    local offset = 0
    for _, lines in ipairs(segments) do
        local from = math.max(start - offset, 0) + 1
        local to = math.min(finish - offset, #lines)
        for index = from, to do
            rows[#rows + 1] = lines[index]
        end
        offset = offset + #lines
        if offset >= finish then
            break
        end
    end
    append(rows, notes)
    append(rows, below)
    local jump
    if ui.scroll.anchor and floor >= inner.y then
        local line = ctx:element("jump", { follow = follow }, width)[1] or {}
        local size = math.min(width_of(line), width)
        jump = { row = floor, col = inner.x + math.floor((width - size) / 2), line = line, width = size }
    end
    local pane = self.pane
    pane.top, pane.height, pane.shift = inner.y, finish - start, inner.y - start + self.base
    return { area = inner, rows = rows, jump = jump, pane = pane }
end

return Messages
