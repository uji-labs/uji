local class = require("uji.core.class")
local highlight = require("uji.core.ui.markdown.highlight")
local latex = require("uji.core.ui.markdown.latex")
local sys = require("uji.sys")
local text = require("uji.core.ui.text")

local BULLETS = { "•", "◦", "▪" }

local MODIFIERS = {
    emphasis = { italic = true },
    strong = { bold = true },
    strikethrough = { strikethrough = true },
    link = { underline = true },
}

local function width_of(line)
    local total = 0
    for _, span in ipairs(line) do
        total = total + text.width(span[1])
    end
    return total
end

local Block = class()

function Block:init()
    self.tokens = {}
    self.indent = ""
    self.hanging = ""
    self.pending_space = false
end

function Block:open(indent, hanging)
    if #self.tokens == 0 then
        self.indent = indent
        self.hanging = hanging
    end
end

function Block:push(value, style)
    local spaced = self.pending_space
    local at = 1
    while at <= #value + 1 do
        local stop = value:find(" ", at, true) or #value + 1
        local word = value:sub(at, stop - 1)
        if word == "" then
            spaced = true
        else
            self.tokens[#self.tokens + 1] = { text = word, style = style, spaced = spaced and #self.tokens > 0 }
            spaced = true
        end
        at = stop + 1
    end
    self.pending_space = value:sub(-1) == " "
end

local function finish_line(spans, indent)
    if indent ~= "" then
        table.insert(spans, 1, { indent, 0 })
    end
    return spans
end

function Block:drain(width)
    local tokens, indent, hanging = self.tokens, self.indent, self.hanging
    self:init()
    local usable = math.max(width - text.width(indent), 1)
    local lines, spans, used, first = {}, {}, 0, true
    for _, token in ipairs(tokens) do
        local size = text.width(token.text)
        local gap = (token.spaced and used > 0) and 1 or 0
        if used > 0 and used + gap + size > usable then
            lines[#lines + 1] = finish_line(spans, first and indent or hanging)
            spans, used, first = {}, 0, false
        end
        if used > 0 and token.spaced then
            spans[#spans + 1] = { " ", 0 }
            used = used + 1
        end
        spans[#spans + 1] = { token.text, token.style }
        used = used + size
    end
    if #spans > 0 then
        lines[#lines + 1] = finish_line(spans, first and indent or hanging)
    end
    return lines
end

local function item_marker(list)
    local last = list[#list]
    if type(last) == "number" then
        list[#list] = last + 1
        return last .. "."
    end
    return BULLETS[(#list - 1) % #BULLETS + 1]
end

local function indents(depth, quote, marker)
    local pad = string.rep("  ", math.max(depth - 1, 0))
    if quote > 0 then
        pad = string.rep("  ", quote - 1) .. "│ "
    end
    if marker then
        return pad .. marker .. " ", pad .. string.rep(" ", text.length(marker) + 1)
    end
    return pad, pad
end

local Renderer = class()

function Renderer:init(width, palette, styles)
    self.lines = {}
    self.block = Block()
    self.palette = palette
    self.styles = styles
    self.style = palette.text
    self.stack = {}
    self.list = {}
    self.quote = 0
    self.in_code = false
    self.highlighter = nil
    self.marker = nil
    self.width = width
    self.row = nil
end

function Renderer:flush()
    if #self.block.tokens > 0 then
        for _, line in ipairs(self.block:drain(self.width)) do
            self.lines[#self.lines + 1] = line
        end
    end
end

function Renderer:blank()
    local last = self.lines[#self.lines]
    if last and width_of(last) > 0 then
        self.lines[#self.lines + 1] = {}
    end
end

function Renderer:break_block()
    self:flush()
    self:blank()
end

function Renderer:open()
    local marker = self.marker
    self.marker = nil
    self.block:open(indents(#self.list, self.quote, marker))
end

function Renderer:push_style(extra)
    self.stack[#self.stack + 1] = self.style
    self.style = self.styles:with(self.style, extra)
end

function Renderer:cell(value, style)
    local cells = self.row.cells
    local cell = cells[#cells]
    cell[#cell + 1] = { value, style }
end

function Renderer:finish_row()
    local row = self.row
    self.row = nil
    local line = { { "  ", 0 } }
    for index, cell in ipairs(row.cells) do
        if index > 1 then
            line[#line + 1] = { " │ ", self.palette.muted }
        end
        for _, span in ipairs(cell) do
            line[#line + 1] = row.head and { span[1], self.styles:with(span[2], { bold = true }) } or span
        end
    end
    self.lines[#self.lines + 1] = line
end

function Renderer:inline(value, style)
    if self.row then
        self:cell(value, style)
        return
    end
    self:open()
    self.block:push(value, style)
end

function Renderer:code(raw)
    local spans = self.highlighter and self.highlighter:line(raw) or { { raw, self.palette.code } }
    table.insert(spans, 1, { "  ", 0 })
    self.lines[#self.lines + 1] = spans
end

function Renderer:math(source, display)
    local rendered = latex.render(source)
    if not display or self.row then
        self:inline((rendered:gsub("\n", " ")), self.palette.code)
        return
    end
    self:break_block()
    for _, line in ipairs(text.lines(rendered)) do
        self.lines[#self.lines + 1] = { { "  " .. line, self.palette.code } }
    end
end

local START = {}
local STOP = {}

for tag, extra in pairs(MODIFIERS) do
    START[tag] = function(self)
        self:push_style(extra)
    end
    STOP[tag] = function(self)
        self.style = table.remove(self.stack) or self.palette.text
    end
end

function START.paragraph(self)
    self:flush()
    if #self.list == 0 then
        self:blank()
    end
end

function START.item(self)
    self:flush()
    self.marker = item_marker(self.list)
end

function START.heading(self, level)
    self:break_block()
    self.style = level <= 2 and self.palette.accent or self.palette.bold
end

function START.list(self, start)
    START.paragraph(self)
    self.list[#self.list + 1] = start or false
end

function START.blockquote(self)
    self:break_block()
    self.quote = self.quote + 1
end

function START.code_block(self, language)
    self:break_block()
    self.in_code = true
    self.highlighter = highlight.new(language, self.palette)
    if language and language ~= "" then
        self.lines[#self.lines + 1] = { { "  " .. language, self.palette.dim } }
    end
end

function START.table(self)
    self:break_block()
end

function START.table_head(self)
    self.row = { cells = {}, head = true }
end

function START.table_row(self)
    self.row = { cells = {}, head = false }
end

function START.table_cell(self)
    local cells = self.row.cells
    cells[#cells + 1] = {}
end

function STOP.paragraph(self)
    self:flush()
end

STOP.item = STOP.paragraph

function STOP.heading(self)
    self:flush()
    self.style = self.palette.text
end

function STOP.list(self)
    self.list[#self.list] = nil
end

function STOP.blockquote(self)
    self.quote = math.max(self.quote - 1, 0)
end

function STOP.code_block(self)
    self.in_code = false
    self.highlighter = nil
end

function STOP.table_head(self)
    self:finish_row()
end

STOP.table_row = STOP.table_head

local function run(handlers, self, key, ...)
    local handle = handlers[key]
    if handle then
        handle(self, ...)
    end
end

local EVENTS = {
    start = function(self, tag, detail)
        run(START, self, tag, detail)
    end,
    ["end"] = function(self, tag)
        run(STOP, self, tag)
    end,
    text = function(self, body)
        if not self.in_code then
            return self:inline(body, self.style)
        end
        for _, raw in ipairs(text.lines(body)) do
            self:code(raw)
        end
    end,
    code = function(self, body)
        self:inline(body, self.palette.code)
    end,
    math = function(self, body, display)
        self:math(body, display)
    end,
    task = function(self, done)
        self:inline(done and "[x] " or "[ ] ", self.style)
    end,
    ["break"] = function(self, kind)
        if kind == "soft" then
            return self:inline(" ", self.style)
        end
        self:flush()
    end,
    rule = function(self)
        self:break_block()
        self.lines[#self.lines + 1] = { { string.rep("─", math.min(self.width, 60)), self.palette.muted } }
    end,
}

function Renderer:event(event)
    run(EVENTS, self, event[1], event[2], event[3])
end

function Renderer:finish()
    self:flush()
    while #self.lines > 0 and width_of(self.lines[#self.lines]) == 0 do
        self.lines[#self.lines] = nil
    end
    return self.lines
end

local M = {}

M.width_of = width_of

M.parse = sys.markdown

function M.render(events, width, palette, styles, continuing)
    local renderer = Renderer(width, palette, styles)
    if continuing then
        renderer.lines[1] = {}
    end
    for _, event in ipairs(events) do
        renderer:event(event)
    end
    return renderer:finish()
end

function M.split(events, cut)
    local head, rest = {}, {}
    for _, event in ipairs(events) do
        if event[4] <= cut then
            head[#head + 1] = event
        else
            rest[#rest + 1] = event
        end
    end
    return head, rest
end

function M.settled(events)
    local depth, settled, closed = 0, 0, 0
    for _, event in ipairs(events) do
        local kind = event[1]
        if kind == "start" then
            if depth == 0 then
                settled = closed
            end
            depth = depth + 1
        elseif kind == "end" then
            depth = math.max(depth - 1, 0)
            if depth == 0 then
                closed = event[5]
            end
        elseif kind == "rule" and depth == 0 then
            settled = closed
            closed = event[5]
        end
    end
    return settled
end

function M.defines_reference(source)
    for line in source:gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.*)$")
        if trimmed:sub(1, 1) == "[" and trimmed:find("]:", 1, true) then
            return true
        end
    end
    return false
end

return M
