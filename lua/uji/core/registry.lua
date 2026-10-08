local class = require("uji.core.class")
local ito = require("ito")
local list = require("uji.utils.list")

local DEFAULT_PRIORITY = 50

local Handle = class()

function Handle:init(registry, entry)
    self.registry = registry
    self.entry = entry
    self.name = entry.name
end

function Handle:remove()
    return self.registry:drop_entry(self.entry)
end

local Registry = class()

Registry.DEFAULT_PRIORITY = DEFAULT_PRIORITY

function Registry:init(owner)
    self.entries = {}
    self.owner = owner
    ito.observable(self)
end

function Registry:add(name, value, opts)
    local entry = {
        name = name,
        value = value,
        priority = opts and opts.priority or DEFAULT_PRIORITY,
        owner = self.owner and self.owner() or nil,
    }
    self:remove(name)
    local at = #self.entries + 1
    for index, existing in ipairs(self.entries) do
        if existing.priority > entry.priority then
            at = index
            break
        end
    end
    self.entries = list.inserted(self.entries, at, entry)
    return Handle(self, entry)
end

function Registry:find(name)
    for index, entry in ipairs(self.entries) do
        if entry.name == name then
            return entry, index
        end
    end
end

function Registry:get(name)
    local entry = self:find(name)
    return entry and entry.value
end

function Registry:remove(name)
    local _, index = self:find(name)
    if not index then
        return false
    end
    self.entries = list.removed(self.entries, index)
    return true
end

function Registry:drop_entry(entry)
    for index, existing in ipairs(self.entries) do
        if existing == entry then
            self.entries = list.removed(self.entries, index)
            return true
        end
    end
    return false
end

function Registry:drop_owner(owner)
    self.entries = list.filtered(self.entries, function(entry)
        return entry.owner ~= owner
    end)
end

function Registry:names()
    return list.mapped(self.entries, function(entry)
        return entry.name
    end)
end

function Registry:sorted()
    local names = self:names()
    table.sort(names)
    return names
end

function Registry:values()
    return list.mapped(self.entries, function(entry)
        return entry.value
    end)
end

function Registry:each()
    local index = 0
    local entries = { unpack(self.entries) }
    return function()
        index = index + 1
        local entry = entries[index]
        if entry then
            return entry.name, entry.value
        end
    end
end

function Registry:empty()
    return #self.entries == 0
end

return Registry
