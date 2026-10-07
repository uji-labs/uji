local M = {}

function M.keys(map)
    local keys = {}
    for key in pairs(map) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

function M.copy(map)
    local copy = {}
    for key, value in pairs(map) do
        copy[key] = value
    end
    return copy
end

function M.with(map, key, value)
    local copy = M.copy(map)
    copy[key] = value
    return copy
end

function M.merged(base, changes)
    local copy = M.copy(base)
    for key, value in pairs(changes or {}) do
        copy[key] = value
    end
    return copy
end

function M.same(left, right)
    if #left ~= #right then
        return false
    end
    for index = 1, #left do
        if left[index] ~= right[index] then
            return false
        end
    end
    return true
end

return M
