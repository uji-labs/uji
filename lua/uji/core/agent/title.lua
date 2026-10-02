local model = require("uji.core.model")

local PROMPT = "You name coding sessions. Read the user's first message and reply "
    .. "with a title of at most six words that says what the work is about. Reply with the title "
    .. "alone: no quotes, no trailing punctuation, no markdown, no preamble."

local MAX_INPUT = 2000
local MAX_TITLE = 60

local M = {}

local function clip(value, max)
    local count = 0
    for at in value:gmatch("()[^\128-\191]") do
        count = count + 1
        if count > max then
            return value:sub(1, at - 1):gsub("%s+$", "")
        end
    end
    return value
end

function M.sanitize(raw)
    local line
    for candidate in (raw or ""):gmatch("[^\n]+") do
        if candidate:find("%S") then
            line = candidate
            break
        end
    end
    if not line then
        return nil
    end
    local trimmed = line:match("^%s*(.-)%s*$")
    trimmed = trimmed:gsub("^[#%-%* ]+", "")
    trimmed = trimmed:gsub("^[\"'` ]+", ""):gsub("[\"'` ]+$", "")
    trimmed = trimmed:gsub("[%.!%?]+$", "")
    trimmed = trimmed:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return (clip(trimmed, MAX_TITLE))
end

function M.generate(first_message)
    local answer = model.generate({
        system = PROMPT,
        messages = { { type = "user", text = (clip(first_message, MAX_INPUT)) } },
    })
    if not answer then
        return nil
    end
    local title = M.sanitize(answer.text)
    if not title then
        return nil
    end
    return { title = title, usage = answer.usage }
end

return M
