local class = require("uji.core.class")

local Scroll = class()

function Scroll:init()
    self.anchor = nil
    self.resolved = 0
    self.viewport = 0
    self.max = nil
end

function Scroll:resolve(max, viewport, prepended)
    if self.anchor and self.max and prepended then
        self.anchor = self.anchor + max - self.max - prepended
    end
    self.max = max
    local anchor = math.max(math.min(self.anchor or 0, max), 0)
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
