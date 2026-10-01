local class = require("uji.class")
local markdown = require("uji.ui.markdown")
local tables = require("uji.tables")

local Streamed = class()

function Streamed:init()
    self:clear()
end

function Streamed:clear()
    self.key = ""
    self.settled = 0
    self.scanned = 0
    self.whole = false
    self.lines = {}
    self.open = {}
end

function Streamed:scan(value)
    if self.whole then
        return
    end
    if markdown.defines_reference(value:sub(self.scanned + 1)) then
        self.whole = true
        return
    end
    self.scanned = value:find("\n[^\n]*$") or 0
end

function Streamed:update(value, split, render)
    if self.key == value then
        return
    end
    if not split or value:sub(1, #self.key) ~= self.key then
        self:clear()
    end
    self:scan(value)
    self.key = value
    if value == "" then
        return
    end
    if not split or self.whole then
        self.settled = 0
        self.lines = {}
        self.open = {}
        render(self.open, value, false)
        return
    end
    local tail = value:sub(self.settled + 1)
    local events = markdown.parse(tail)
    local cut = markdown.settled(events)
    if cut > 0 then
        local head
        head, events = markdown.split(events, cut)
        render(self.lines, tail:sub(1, cut), #self.lines > 0, head)
        self.settled = self.settled + cut
    end
    self.open = {}
    if self.settled < #value then
        render(self.open, value:sub(self.settled + 1), #self.lines > 0, events)
    end
end

local Cached = class()

function Cached:init()
    self:clear()
end

function Cached:clear()
    self.key = {}
    self.lines = {}
end

function Cached:get(key, render)
    if not tables.same(self.key, key) then
        self.key = { unpack(key) }
        self.lines = {}
        render(self.lines)
    end
    return self.lines
end

local Transcript = class()

local function opens_group(message)
    return message.type == "tool" or (message.type == "assistant" and #(message.tool_calls or {}) > 0)
end

function Transcript:init()
    self.width = -1
    self.thinking = false
    self.revision = -1
    self.notices = Cached()
    self.queued = Cached()
    self.pending = Streamed()
    self.reasoning = Streamed()
    self:reset()
end

function Transcript:reset()
    self.blocks = {}
    self.first = 1
    self.last = 0
    self.count = 0
    self.last_seq = nil
    self.fresh = true
end

function Transcript:block(entries, index, render)
    local lines = {}
    local message = entries[index].message
    if message.type == "context" then
        return lines
    end
    local previous
    for at = index - 1, 1, -1 do
        if entries[at].message.type ~= "context" then
            previous = entries[at].message
            break
        end
    end
    if previous and not (opens_group(previous) and message.type == "tool") then
        lines[1] = {}
    end
    if self.thinking and message.reasoning and message.reasoning ~= "" then
        render(lines, { kind = "thinking", text = message.reasoning })
    end
    render(lines, { kind = "message", message = message })
    return lines
end

function Transcript:sync(entries, render)
    local total = #entries
    if self.last > total or (self.last > 0 and entries[self.last].seq ~= self.last_seq) then
        self:reset()
    end
    if self.first > self.last then
        self.first = total + 1
    else
        for index = self.last + 1, total do
            local lines = self:block(entries, index, render)
            self.blocks[index] = lines
            self.count = self.count + #lines
        end
    end
    self.last = total
    self.last_seq = total > 0 and entries[total].seq or nil
end

function Transcript:extend(entries, want, render)
    local before = self.count
    while self.count < want and self.first > 1 do
        self.first = self.first - 1
        local lines = self:block(entries, self.first, render)
        self.blocks[self.first] = lines
        self.count = self.count + #lines
    end
    return self.count - before
end

function Transcript:rows()
    local rows = {}
    for index = self.first, self.last do
        for _, line in ipairs(self.blocks[index]) do
            rows[#rows + 1] = line
        end
    end
    return rows
end

function Transcript:frame(input, split, render, want)
    if self.width ~= input.width or self.revision ~= input.revision or self.thinking ~= input.thinking then
        self.width = input.width
        self.revision = input.revision
        self.thinking = input.thinking
        self:reset()
        self.notices:clear()
        self.queued:clear()
        self.pending:clear()
        self.reasoning:clear()
    end
    self:sync(input.entries, render)
    local prepended = self:extend(input.entries, want, render)
    if self.fresh then
        prepended = nil
        self.fresh = false
    end
    local notices = self.notices:get(input.notices, function(lines)
        for _, notice in ipairs(input.notices) do
            render(lines, { kind = "notice", text = notice })
        end
    end)
    local queued = self.queued:get(input.queued, function(lines)
        for _, queued in ipairs(input.queued) do
            render(lines, { kind = "queued", text = queued.text })
        end
    end)
    self.reasoning:update(input.thinking and input.reasoning or "", split, function(lines, chunk)
        render(lines, { kind = "thinking", text = chunk })
    end)
    self.pending:update(input.pending, split, function(lines, chunk, continuing, events)
        render(lines, { kind = "pending", text = chunk, continuing = continuing, events = events })
    end)
    return {
        prepended = prepended,
        notices = notices,
        queued = queued,
        folded = self:rows(),
        live = { self.reasoning.lines, self.reasoning.open, self.pending.lines, self.pending.open },
    }
end

return Transcript
