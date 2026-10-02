uji.api = setmetatable({}, {
    __index = function(apis, name)
        local found = require("uji.builtin.apis." .. name)
        rawset(apis, name, found)
        return found
    end,
})
