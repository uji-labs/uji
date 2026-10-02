local MIN_ANSWER = 1024
local MIN_BUDGET = 1024
local BUDGET = { minimal = 1024, low = 2048, medium = 8192, high = 16384 }
local ARRAY = getmetatable(uji.json.array({}))

local M = { MIN_ANSWER = MIN_ANSWER }

function M.fit_thinking(effort, max_output)
    local max_tokens = math.max(max_output, MIN_ANSWER)
    local budget = BUDGET[effort] or 0
    if budget > 0 and max_tokens <= budget then
        budget = math.min(budget, math.max(max_tokens - MIN_ANSWER, 0))
    end
    if budget < MIN_BUDGET then
        budget = 0
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

function M.translate(messages, shapes, show)
    local out = uji.json.array({})
    local pending = {}
    local function flush()
        if #pending > 0 then
            for _, message in ipairs(show(pending)) do
                out[#out + 1] = message
            end
            pending = {}
        end
    end
    for _, item in ipairs(messages) do
        local shape = shapes[item.type]
        if shape then
            if item.type ~= "tool" then
                flush()
            end
            out[#out + 1] = shape(item)
            if show and item.type == "tool" then
                for _, image in ipairs(item.images or {}) do
                    pending[#pending + 1] = image
                end
            end
        end
    end
    flush()
    return out
end

M.SHOWN = "These are the images the tool calls above returned."

function M.parts(images, picture, text, word)
    local parts = M.map(images, picture)
    if text ~= "" or #parts == 0 then
        parts[#parts + 1] = word(text)
    end
    return parts
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
