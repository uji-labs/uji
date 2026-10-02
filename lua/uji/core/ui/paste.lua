local class = require("uji.core.class")
local text = require("uji.core.ui.text")

local MAX_LINES = 1
local MAX_CHARS = 80

local Pastes = class()

function Pastes:init()
    self:clear()
end

function Pastes:clear()
    self.entries = {}
    self.counter = 0
    self.pasted = 0
    self.attached = 0
end

function Pastes:add(entry)
    self.counter = self.counter + 1
    entry.id = self.counter
    self.entries[#self.entries + 1] = entry
    return entry.marker
end

function Pastes:stash(value)
    local lines = #text.lines(value)
    local chars = text.length(value)
    if lines <= MAX_LINES and chars <= MAX_CHARS then
        return value
    end
    self.pasted = self.pasted + 1
    local marker
    if lines > MAX_LINES then
        marker = string.format("[paste #%d +%d lines]", self.pasted, lines)
    else
        marker = string.format("[paste #%d %d chars]", self.pasted, chars)
    end
    return self:add({ marker = marker, content = value })
end

function Pastes:attach(image)
    self.attached = self.attached + 1
    return self:add({ marker = string.format("[image #%d]", self.attached), image = image })
end

function Pastes:images(value)
    local found = {}
    for _, entry in ipairs(self.entries) do
        if entry.image and value:find(entry.marker, 1, true) then
            found[#found + 1] = entry.image
        end
    end
    return found
end

function Pastes:expand(value)
    for _, entry in ipairs(self.entries) do
        if entry.content then
            local from, to = value:find(entry.marker, 1, true)
            while from do
                value = value:sub(1, from - 1) .. entry.content .. value:sub(to + 1)
                from, to = value:find(entry.marker, from + #entry.content, true)
            end
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
