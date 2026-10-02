local M = {}

function M.name(value, api)
    if type(value) ~= "string" or value == "" then
        error(api .. " needs a name", 3)
    end
end

function M.options(value, api)
    if type(value) ~= "table" then
        error(api .. " needs a table", 3)
    end
    return value
end

return M
