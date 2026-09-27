local app = require("uji.app")
local tokens = require("uji.agent.tokens")

local M = {}

local function usage(value)
    return {
        input = value.input,
        output = value.output,
        cache_read = value.cache_read,
        cache_write = value.cache_write,
        total = value.input + value.output + value.cache_read + value.cache_write,
    }
end

function M.info()
    local session = app.session
    if not session then
        return { id = "", title = "", directory = "" }
    end
    return { id = session.id, title = session.title, directory = session.directory }
end

function M.messages()
    local rows = {}
    if not app.session then
        return rows
    end
    for index, message in ipairs(app.session:messages()) do
        rows[index] = { type = message.type, text = tokens.text(message), name = message.type == "tool" and message.name or nil }
    end
    return rows
end

function M.usage()
    local tally = app.session and app.session.tally or {
        usage = { input = 0, output = 0, cache_read = 0, cache_write = 0 },
        last = { input = 0, output = 0, cache_read = 0, cache_write = 0 },
        turns = 0,
    }
    local out = usage(tally.usage)
    out.last = usage(tally.last)
    out.requests = tally.turns
    return out
end

function M.set_title(title)
    local text = type(title) == "string" and title:match("^%s*(.-)%s*$") or ""
    if text == "" then
        error("set_title needs non-empty text", 2)
    end
    app.agent:set_title(text)
end

function M.submit(text)
    if type(text) ~= "string" or not text:find("%S") then
        error("submit needs non-empty text", 2)
    end
    app.agent:submit(text)
end

function M.interrupt()
    app.agent:interrupt()
end

return M
