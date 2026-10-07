local M = {}

function M.inserted(list, at, value)
    local out = {}
    for index = 1, at - 1 do
        out[index] = list[index]
    end
    out[at] = value
    for index = at, #list do
        out[index + 1] = list[index]
    end
    return out
end

function M.appended(list, value)
    return M.inserted(list, #list + 1, value)
end

function M.removed(list, at)
    local out = {}
    for index, value in ipairs(list) do
        if index ~= at then
            out[#out + 1] = value
        end
    end
    return out
end

function M.extended(list, more)
    local out = {}
    for index, value in ipairs(list) do
        out[index] = value
    end
    for _, value in ipairs(more) do
        out[#out + 1] = value
    end
    return out
end

function M.mapped(list, change)
    local out = {}
    for index, value in ipairs(list) do
        out[index] = change(value, index)
    end
    return out
end

function M.filtered(list, keep)
    local out = {}
    for _, value in ipairs(list) do
        if keep(value) then
            out[#out + 1] = value
        end
    end
    return out
end

function M.flattened(lists)
    local out = {}
    for _, inner in ipairs(lists) do
        for _, value in ipairs(inner) do
            out[#out + 1] = value
        end
    end
    return out
end

return M
