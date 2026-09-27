local class = require("uji.class")

local Scroll = class()

function Scroll:init()
    self.anchor = nil
    self.resolved = 0
    self.viewport = 0
end

function Scroll:resolve(max, viewport)
    local anchor = math.min(self.anchor or 0, max)
    self.anchor = anchor > 0 and anchor or nil
    self.resolved = max - anchor
    self.viewport = viewport
    return self.resolved
end

function Scroll:follow()
    self.anchor = nil
end

function Scroll:top()
    self.anchor = math.huge
end

function Scroll:up(lines)
    self.anchor = (self.anchor or 0) + lines
end

function Scroll:down(lines)
    local anchor = (self.anchor or 0) - lines
    self.anchor = anchor > 0 and anchor or nil
end

return Scroll
