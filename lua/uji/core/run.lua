local Session = require("uji.core.store.session")
local app = require("uji.core.app")
local catalog = require("uji.core.catalog")
local cli = require("uji.core.cli")
local event = require("uji.core.event")
local model = require("uji.core.model")
local notices = require("uji.core.notices")
local sys = require("uji.sys")
local task = require("uji.core.task")
local title = require("uji.core.agent.title")

local function write(stream, line)
    stream:write(line, "\n")
    stream:flush()
end

local function chosen(flags)
    if not flags.model then
        return { effort = flags.effort }
    end
    local provider, name = flags.model:match("^([^/]+)/(.+)$")
    if not provider then
        return nil, "--model is written as provider/model"
    end
    if not catalog.get(provider) then
        return nil, "there is no provider `" .. provider .. "`"
    end
    return { provider = provider, model = name, effort = flags.effort }
end

local function listed(names)
    local out = {}
    for name in names:gmatch("[^,%s]+") do
        out[#out + 1] = name
    end
    return out
end

local function listen(session, json)
    local function emit(line)
        if json then
            write(io.stdout, line)
        end
    end
    local function notice(message)
        if json then
            emit(sys.json.encode({ type = "notice", text = message }))
        else
            write(io.stderr, "uji: " .. message)
        end
    end
    local handlers = {
        message_appended = function()
            local entries = session:entries()
            emit('{"type":"message","message":' .. Session.encode(entries[#entries].message) .. "}")
        end,
        tool_progress = function(payload)
            if payload.name and payload.line and payload.line ~= "" then
                emit(sys.json.encode({ type = "progress", tool = payload.name, line = payload.line }))
            end
        end,
        notice = function(payload)
            notice(payload.text)
        end,
        turn_finished = function(payload)
            local entries = session:entries()
            local last = entries[#entries] and entries[#entries].message
            local problem = payload.error
            if not problem and last and last.type == "error" then
                problem = last.text
            end
            if not last and not problem then
                problem = "the turn finished without a saved result"
            end
            local failed = problem ~= nil
            local result = problem or last.text
            if json then
                local done = { type = "done", usage = session.tally.usage }
                done[failed and "error" or "text"] = result
                emit(sys.json.encode(done))
            elseif failed then
                return cli.fail(result)
            else
                write(io.stdout, result)
            end
            sys.os.exit(failed and 1 or 0)
        end,
    }
    for name, handler in pairs(handlers) do
        event.on(name, handler, { name = "uji.run." .. name })
    end
    emit(sys.json.encode({ type = "session", id = session.id }))
    for _, message in ipairs(notices.take()) do
        notice(message)
    end
end

return function(store, parsed)
    local flags = parsed.flags
    local prompt = table.concat(parsed.positional or {}, " ")
    if not prompt:find("%S") then
        return cli.fail("uji run needs a prompt")
    end
    if flags.parent and not cli.session(store, flags.parent) then
        return
    end
    local choice, problem = chosen(flags)
    if not choice then
        return cli.fail(problem)
    end
    model.resolve(choice)
    if flags["append-prompt"] then
        event.on("before_turn", function(turn)
            return turn.system .. "\n\n" .. flags["append-prompt"]
        end, { name = "uji.run.prompt", priority = 1000 })
    end
    local session = store:create_session(title.sanitize(flags.title or prompt), flags.parent)
    local agent = app.attach(session)
    agent.tools = flags.tools and listed(flags.tools)
    agent.confirm = function()
        return true
    end
    listen(session, flags.json)
    event.emit("session_created", { session_id = session.id })
    task.release()
    agent:submit(prompt)
end
