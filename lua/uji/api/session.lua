local app = require("uji.core.app")
local check = require("uji.core.check")
local cli = require("uji.core.cli")
local model = require("uji.core.model")
local sys = require("uji.sys")
local tokens = require("uji.core.agent.tokens")

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
        return { id = "", title = "", directory = "", short_directory = "" }
    end
    return {
        id = session.id,
        title = session.title,
        directory = session.directory,
        short_directory = sys.os.shorten(session.directory),
    }
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
    local tally = app.session and app.session.tally
        or {
            usage = { input = 0, output = 0, cache_read = 0, cache_write = 0 },
            last = { input = 0, output = 0, cache_read = 0, cache_write = 0 },
            turns = 0,
        }
    local out = usage(tally.usage)
    out.last = usage(tally.last)
    out.requests = tally.turns
    return out
end

function M.context()
    return {
        used = app.session and app.session:used_tokens() or 0,
        window = model.window(),
    }
end

function M.queue()
    local out = {}
    for index, queued in ipairs(app.agent and app.agent.queue or {}) do
        out[index] = queued.text
    end
    return out
end

function M.state()
    return app.agent and app.agent:working() and "working" or "idle"
end

function M.elapsed()
    return app.agent and app.agent:elapsed()
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

function M.compact()
    local started, reason = app.agent:compact()
    return started == true, reason
end

function M.list(opts)
    opts = check.options(opts or {}, "uji.session.list")
    if opts.directory ~= nil and type(opts.directory) ~= "string" then
        error("uji.session.list needs directory to be a string", 2)
    end
    local rows = {}
    for index, session in ipairs(app.store:sessions(opts.directory)) do
        rows[index] = {
            id = session.id,
            title = session.title,
            directory = session.directory,
            updated = session.updated,
        }
    end
    return rows
end

function M.delete(key)
    if type(key) ~= "string" then
        error("uji.session.delete needs a session id", 2)
    end
    if not cli.valid_id(key) then
        return nil, "invalid session id: " .. key
    end
    local current = app.session and app.session.id
    if current == key then
        return nil, "the open session cannot be deleted"
    end
    while current do
        local session = app.store:session(current)
        current = session and session.parent
        if current == key then
            return nil, "deleting it would delete the open session too"
        end
    end
    if not app.store:delete(key) then
        return nil, "no session with id " .. key
    end
    return true
end

uji.session = M
