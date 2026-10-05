local class = require("uji.core.class")
local highlight = require("uji.core.ui.markdown.highlight")
local latex = require("uji.core.ui.markdown.latex")
local sys = require("uji.sys")
local text = require("ito").text

local MODIFIERS = { "emphasis", "strong", "strikethrough", "link" }

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
        table.insert(spans, 1, { indent })
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
            spans[#spans + 1] = { " " }
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

local function item_marker(ctx, list)
    local last = list[#list]
    if type(last) == "number" then
        list[#list] = last + 1
        return string.format(ctx.text.ordered, last)
    end
    local bullets = ctx.symbols.bullets
    return bullets[(#list - 1) % #bullets + 1]
end

local Renderer = class()

function Renderer:init(ctx, width)
    self.lines = {}
    self.block = Block()
    self.ctx = ctx
    self.style = ctx.styles.text
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

function Renderer:gap()
    for _ = 1, self.ctx.limits.block_gap do
        self.lines[#self.lines + 1] = {}
    end
end

function Renderer:blank()
    local last = self.lines[#self.lines]
    if last and width_of(last) > 0 then
        self:gap()
    end
end

function Renderer:element(name, data)
    for _, line in ipairs(self.ctx:element(name, data, self.width)) do
        self.lines[#self.lines + 1] = line
    end
end

function Renderer:break_block()
    self:flush()
    self:blank()
end

function Renderer:indents(marker)
    local ctx = self.ctx
    local step = string.rep(" ", ctx.limits.indent)
    local pad = string.rep(step, math.max(#self.list - 1, 0))
    if self.quote > 0 then
        pad = string.rep(step, self.quote - 1) .. ctx.symbols.quote .. " "
    end
    if marker then
        return pad .. marker .. " ", pad .. string.rep(" ", text.length(marker) + 1)
    end
    return pad, pad
end

function Renderer:open()
    local marker = self.marker
    self.marker = nil
    self.block:open(self:indents(marker))
end

function Renderer:push_style(role)
    self.stack[#self.stack + 1] = self.style
    self.style = self.style:merge(self.ctx.styles[role])
end

function Renderer:cell(value, style)
    local cells = self.row.cells
    local cell = cells[#cells]
    cell[#cell + 1] = { value, style }
end

function Renderer:finish_row()
    local row = self.row
    self.row = nil
    self:element("table_row", row)
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
    local lines = self.code_block.lines
    lines[#lines + 1] = self.highlighter and self.highlighter:line(raw) or { { raw, self.ctx.styles.code } }
end

function Renderer:close_heading()
    local heading = self.heading
    if not heading then
        return
    end
    self.heading = nil
    local lines = {}
    for index = heading.from, #self.lines do
        lines[#lines + 1] = self.lines[index]
        self.lines[index] = nil
    end
    self:element("heading", { level = heading.level, lines = lines })
end

function Renderer:close_code()
    local block = self.code_block
    if block then
        self.code_block = nil
        self:element("code_block", block)
    end
end

function Renderer:math(source, display)
    local rendered = latex.render(source)
    if not display or self.row then
        self:inline((rendered:gsub("\n", " ")), self.ctx.styles.code)
        return
    end
    self:break_block()
    self:element("math_block", { lines = text.lines(rendered) })
end

local START = {}
local STOP = {}

for _, tag in ipairs(MODIFIERS) do
    START[tag] = function(self)
        self:push_style(tag)
    end
    STOP[tag] = function(self)
        self.style = table.remove(self.stack) or self.ctx.styles.text
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
    self.marker = item_marker(self.ctx, self.list)
end

function START.heading(self, level)
    self:break_block()
    self.heading = { level = level, from = #self.lines + 1 }
    self.style = self.ctx.styles["heading" .. level]
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
    local styles = self.ctx.styles
    self.highlighter = highlight.new(language, {
        plain = styles.text,
        keyword = styles.code_keyword,
        string = styles.code_string,
        number = styles.code_number,
        comment = styles.code_comment,
    })
    self.code_block = { language = language ~= "" and language or nil, lines = {} }
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
    self:close_heading()
    self.style = self.ctx.styles.text
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
    self:close_code()
end

function STOP.table_head(self)
    self:finish_row()
end

STOP.table_row = STOP.table_head

local EVENTS = {
    start = function(self, tag, detail)
        local handle = START[tag]
        if handle then
            handle(self, detail)
        end
    end,
    ["end"] = function(self, tag)
        local handle = STOP[tag]
        if handle then
            handle(self)
        end
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
        self:inline(body, self.ctx.styles.code)
    end,
    math = function(self, body, display)
        self:math(body, display)
    end,
    task = function(self, done)
        local symbols = self.ctx.symbols
        self:inline((done and symbols.task_done or symbols.task_open) .. " ", self.style)
    end,
    ["break"] = function(self, kind)
        if kind == "soft" then
            return self:inline(" ", self.style)
        end
        self:flush()
    end,
    rule = function(self)
        self:break_block()
        self:element("rule", {})
    end,
}

function Renderer:event(event)
    local handle = EVENTS[event[1]]
    if handle then
        handle(self, event[2], event[3])
    end
end

function Renderer:finish()
    self:flush()
    self:close_heading()
    self:close_code()
    while #self.lines > 0 and width_of(self.lines[#self.lines]) == 0 do
        self.lines[#self.lines] = nil
    end
    return self.lines
end

local M = {}

M.width_of = width_of

M.parse = sys.markdown

function M.render(ctx, opts)
    local renderer = Renderer(ctx, opts.width)
    if opts.continuing then
        renderer:gap()
    end
    for _, event in ipairs(opts.events) do
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
