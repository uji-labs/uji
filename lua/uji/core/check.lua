local M = {}

function M.name(value, api)
    if type(value) ~= "string" or value == "" then
        error(api .. " needs a name", 3)
    end
end

function M.callable(value)
    local meta = type(value) == "table" and getmetatable(value)
    return type(value) == "function" or (meta and meta.__call ~= nil) or false
end

function M.options(value, api)
    if type(value) ~= "table" then
        error(api .. " needs a table", 3)
    end
    return value
end

return M
