local images = require("uji.core.images")

local M = {}

local CHARS_PER_TOKEN = 4

local function chars(text)
    if not text then
        return 0
    end
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

M.chars = chars

function M.text(message)
    local kind = message.type
    if kind == "tool" then
        return message.content or ""
    elseif kind == "shell" then
        return message.output or ""
    elseif kind == "job" then
        return message.output or ""
    elseif kind == "compaction" then
        return message.summary or ""
    end
    return message.text or ""
end

function M.estimate(text)
    return math.floor(chars(text) / CHARS_PER_TOKEN)
end

function M.weigh(message)
    local count = chars(M.text(message))
    if message.type == "assistant" then
        for _, call in ipairs(message.tool_calls or {}) do
            count = count + chars(call.name) + chars(call.arguments)
        end
    end
    local pictures = 0
    for _, image in ipairs(message.images or {}) do
        pictures = pictures + images.tokens(image)
    end
    return math.floor(count / CHARS_PER_TOKEN) + pictures
end

function M.last_compaction(stored)
    for index = #stored, 1, -1 do
        if stored[index].message.type == "compaction" then
            return index
        end
    end
end

function M.after(stored, seq)
    local total = 0
    for _, entry in ipairs(stored) do
        if entry.seq > seq then
            total = total + M.weigh(entry.message)
        end
    end
    return total
end

function M.total(stored)
    local at = M.last_compaction(stored)
    local total = at and M.estimate(stored[at].message.summary) or 0
    for index = (at or 0) + 1, #stored do
        total = total + M.weigh(stored[index].message)
    end
    return total
end

function M.messages(messages)
    local total = 0
    for _, message in ipairs(messages) do
        total = total + M.weigh(message)
    end
    return total
end

return M
