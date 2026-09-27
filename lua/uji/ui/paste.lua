local class = require("uji.class")
local text = require("uji.ui.text")

local MAX_LINES = 1
local MAX_CHARS = 80

local Pastes = class()

function Pastes:init()
    self:clear()
end

function Pastes:clear()
    self.entries = {}
    self.counter = 0
end

function Pastes:stash(value)
    local lines = #text.lines(value)
    local chars = text.length(value)
    if lines <= MAX_LINES and chars <= MAX_CHARS then
        return value
    end
    self.counter = self.counter + 1
    local marker
    if lines > MAX_LINES then
        marker = string.format("[paste #%d +%d lines]", self.counter, lines)
    else
        marker = string.format("[paste #%d %d chars]", self.counter, chars)
    end
    self.entries[#self.entries + 1] = { id = self.counter, marker = marker, content = value }
    return marker
end

function Pastes:expand(value)
    for _, entry in ipairs(self.entries) do
        local from, to = value:find(entry.marker, 1, true)
        while from do
            value = value:sub(1, from - 1) .. entry.content .. value:sub(to + 1)
            from, to = value:find(entry.marker, from + #entry.content, true)
        end
    end
    return value
end

function Pastes:marker_ending_at(value)
    for _, entry in ipairs(self.entries) do
        if value:sub(-#entry.marker) == entry.marker then
            return entry.id, #entry.marker
        end
    end
end

function Pastes:forget(id)
    for index, entry in ipairs(self.entries) do
        if entry.id == id then
            table.remove(self.entries, index)
            return
        end
    end
end

function Pastes:prune(value)
    local kept = {}
    for _, entry in ipairs(self.entries) do
        if value:find(entry.marker, 1, true) then
            kept[#kept + 1] = entry
        end
    end
    self.entries = kept
end

Pastes.clean = function(value)
    value = value:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\t", "    ")
    return (value:gsub("%c", function(char)
        if char == "\n" then
            return char
        end
        return ""
    end))
end

Pastes.single_line = function(value)
    return (text.trim(Pastes.clean(value)):gsub("\n", " "))
end

return Pastes
