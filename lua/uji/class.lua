return function(parent)
    local class = {}
    class.__index = class
    return setmetatable(class, {
        __index = parent,
        __call = function(self, ...)
            local object = setmetatable({}, self)
            if object.init then
                object:init(...)
            end
            return object
        end,
    })
end
