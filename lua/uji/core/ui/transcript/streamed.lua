local class = require("uji.core.class")
local markdown = require("uji.core.ui.markdown")

local Streamed = class()

function Streamed:init()
    self:clear()
end

function Streamed:clear()
    self.key = ""
    self.settled = 0
    self.scanned = 0
    self.whole = false
    self.done = {}
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
        self.done = {}
        self.open = render({ text = value, continuing = false })
        return
    end
    local tail = value:sub(self.settled + 1)
    local events = markdown.parse(tail)
    local cut = markdown.settled(events)
    if cut > 0 then
        local head
        head, events = markdown.split(events, cut)
        self.done[#self.done + 1] = render({ text = tail:sub(1, cut), continuing = #self.done > 0, events = head })
        self.settled = self.settled + cut
    end
    self.open = {}
    if self.settled < #value then
        self.open = render({ text = value:sub(self.settled + 1), continuing = #self.done > 0, events = events })
    end
end

function Streamed:items(into)
    for _, chunk in ipairs(self.done) do
        for _, view in ipairs(chunk) do
            into[#into + 1] = view
        end
    end
    for _, view in ipairs(self.open) do
        into[#into + 1] = view
    end
end

return Streamed
