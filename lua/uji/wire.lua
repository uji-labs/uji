local Registry = require("uji.registry")
local plugin = require("uji.plugin")

local M = { registry = plugin.track(Registry(plugin.current)) }

function M.add(name, spec)
    if type(name) ~= "string" or name == "" then
        error("uji.wire.add needs a name", 2)
    end
    if type(spec) ~= "table" or type(spec.stream) ~= "function" then
        error("wire " .. name .. " needs a stream function", 2)
    end
    return M.registry:add(name, spec)
end

function M.remove(name)
    return M.registry:remove(name)
end

function M.list()
    local names = M.registry:names()
    table.sort(names)
    return names
end

function M.get(name)
    return M.registry:get(name)
end

return M
