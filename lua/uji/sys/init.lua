local PREFIX = "uji.sys."

local absent = {}

local function found(module)
    for _, searcher in ipairs(package.searchers) do
        if type(searcher(module)) == "function" then
            return true
        end
    end
    return false
end

local sys = setmetatable({}, {
    __index = function(loaded, name)
        if type(name) ~= "string" then
            return nil
        end
        local module = PREFIX .. name
        if absent[name] or (package.loaded[module] == nil and not found(module)) then
            absent[name] = true
            return nil
        end
        local value = require(module)
        rawset(loaded, name, value)
        return value
    end,
})

uji = uji or {}
setmetatable(uji, { __index = sys })

return sys
