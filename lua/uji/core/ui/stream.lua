local class = require("uji.core.class")
local ito = require("ito")

local EASE = 6
local MIN = 3
local MAX = 120
local BURST = 4096

local Stream = class()

function Stream:init()
    ito.observable(self)
    self:clear()
end

function Stream:clear()
    rawset(self, "parts", {})
    rawset(self, "joined", "")
    self.length = 0
    self.revealed = 0
end

function Stream:push(delta)
    self.parts[#self.parts + 1] = delta
    self.length = self.length + #delta
end

function Stream:text()
    if #self.parts > 0 then
        rawset(self, "joined", self.joined .. table.concat(self.parts))
        rawset(self, "parts", {})
    end
    return self.joined
end

function Stream:visible()
    return self:text():sub(1, self.revealed)
end

function Stream:revealing()
    return self.revealed < self.length
end

function Stream:reveal_all()
    self.revealed = self.length
end

function Stream:reveal_step()
    local backlog = self.length - self.revealed
    if backlog <= 0 then
        return false
    end
    local step = backlog
    if backlog <= BURST then
        step = math.min(math.max(math.ceil(backlog / EASE), MIN), MAX)
    end
    local value = self:text()
    local at = math.min(self.revealed + step, self.length)
    while at < self.length do
        local byte = value:byte(at + 1)
        if byte < 128 or byte >= 192 then
            break
        end
        at = at + 1
    end
    self.revealed = at
    return true
end

return Stream
