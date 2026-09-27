local M = {}

local MIN_ANSWER = 1024
local BUDGET = { off = 0, minimal = 1024, low = 2048, medium = 8192, high = 16384 }
local ARRAY = getmetatable(uji.json.array({}))

function M.fit_thinking(effort, max_output)
    local max_tokens = math.max(max_output, MIN_ANSWER)
    local budget = BUDGET[effort] or 0
    if budget > 0 and max_tokens <= budget then
        budget = math.min(budget, math.max(max_tokens - MIN_ANSWER, 0))
    end
    return max_tokens, budget
end

function M.arguments(raw)
    local ok, value = pcall(uji.json.decode, raw)
    if ok and type(value) == "table" and getmetatable(value) ~= ARRAY then
        return value
    end
    return {}
end

function M.map(list, shape)
    local out = uji.json.array({})
    for _, item in ipairs(list or {}) do
        out[#out + 1] = shape(item)
    end
    return out
end

function M.nonempty(list)
    if #list > 0 then
        return list
    end
end

function M.translate(messages, shapes)
    local out = uji.json.array({})
    for _, item in ipairs(messages) do
        local shape = shapes[item.type]
        if shape then
            out[#out + 1] = shape(item)
        end
    end
    return out
end

function M.system(request)
    local system = request.system or ""
    for _, item in ipairs(request.messages) do
        if item.type == "system" then
            system = system ~= "" and system .. "\n" .. item.text or item.text
        end
    end
    return system
end

function M.bearer(token)
    return token and "Bearer " .. token
end

return M
