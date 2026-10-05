local app = require("uji.core.app")
local Blocks = require("uji.core.ui.blocks")
local canvas = require("uji.core.ui.canvas")
local class = require("uji.core.class")
local text = require("uji.core.ui.text")
local Transcript = require("uji.core.ui.transcript")

local TRAILING_GAP = 1
local JUMP = " ↓ Jump to bottom "

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

local Messages = class()

function Messages:init()
    self.blocks = Blocks()
    self.transcript = Transcript(self.blocks)
end

function Messages:draw(ui, screen, area, window)
    local palette = ui.palette
    local inner = canvas.block(screen, area, ui:chrome(window))
    local floor = inner.y + inner.height - 1
    inner.height = math.max(inner.height - TRAILING_GAP, 0)
    local width, height = inner.width, inner.height
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
        split = not self.blocks:prepare(palette, ui.styles),
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
        Blocks.wrapped(tail, partial, width, palette.text, " ", false)
    end
    local live = 0
    for _, lines in ipairs(parts.live) do
        live = live + #lines
    end
    local lead = {}
    if (live > 0 or #tail > 0) and #parts.folded > 0 then
        lead[1] = {}
    end

    local below = {}
    local running = ui.running
    if running then
        below[1] = {}
        Blocks.wrapped(below, running.name .. "  " .. text.clip(running.line, width), width, palette.dim, " ⋯ ", false)
    end
    if #parts.queued > 0 then
        below[#below + 1] = {}
        append(below, parts.queued)
    end
    local notes = {}
    if #parts.notices > 0 then
        notes[1] = {}
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
    canvas.lines(screen, inner, rows)
    if ui.scroll.anchor and floor >= inner.y then
        local size = math.min(text.width(JUMP), width)
        local col = inner.x + math.floor((width - size) / 2)
        screen:line(floor, col, { { JUMP, palette.chosen_name }, on_click = follow }, size)
    end
    local pane = self.pane
    pane.top, pane.height, pane.shift = inner.y, finish - start, inner.y - start + self.base
    return pane
end

return Messages
