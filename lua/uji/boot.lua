local notices = require("uji.notices")
local sys = require("uji.sys")

local function fail(message)
    io.stderr:write("uji: error: " .. message .. "\n")
    sys.os.exit(1)
end

local function open_session(store, parsed)
    local cli = require("uji.cli")
    local Store = require("uji.store")
    if parsed.command == "new" then
        return store:create_session(Store.UNTITLED), "session_created"
    end
    local id = parsed.flags.id
    if not id then
        return store:latest(sys.os.cwd()) or store:create_session(Store.UNTITLED), "session_resumed"
    end
    if not cli.valid_id(id) then
        return fail("invalid session id: " .. id)
    end
    local found = store:session(id)
    if not found then
        return fail("no session with id: " .. id)
    end
    return found, "session_resumed"
end

local function start(session, created)
    local app = require("uji.app")
    local Agent = require("uji.agent")
    app.session = session
    app.agent = Agent(session)
    require("uji.event").emit(created, { session_id = session.id })
    require("uji.ui"):start()
    app.agent:repair()
    require("uji.config").refresh()
    require("uji.task").release()
end

local function run(args)
    require("uji.api").install()
    local cli = require("uji.cli")
    local paths = require("uji.paths")
    local parsed = cli.parse(args)
    paths.overrides.config = parsed.flags["config-dir"]
    paths.overrides.data = parsed.flags["data-dir"]
    paths.overrides.db = parsed.flags.db
    if parsed.command == "help" then
        io.stdout:write(cli.USAGE, "\n")
        return
    end
    if parsed.command == "version" then
        io.stdout:write("uji ", require("uji.version"), "\n")
        return
    end
    local db = paths.db()
    if not db then
        return fail("$HOME is not set")
    end
    local Store = require("uji.store")
    local ok, store = pcall(Store, db)
    if not ok then
        return fail(tostring(store))
    end
    if parsed.command == "delete" then
        local id = parsed.positional and parsed.positional[1]
        if not cli.valid_id(id) then
            return fail("invalid session id: " .. tostring(id))
        end
        store:delete(id)
        return
    end
    local command = parsed.command
    if command ~= "new" and command ~= "resume" and command ~= "list" then
        return fail("unrecognized subcommand '" .. command .. "'")
    end
    require("uji.task").hold()
    require("uji.app").store = store
    require("uji.model").attach(store)
    require("uji.commands")
    require("uji.config").load()
    if command == "list" then
        local session = require("uji.ui.sessions").pick(store)
        if not session then
            return require("uji.ui"):quit()
        end
        return start(session, "session_resumed")
    end
    local session, created = open_session(store, parsed)
    if session then
        start(session, created)
    end
end

return function(args)
    sys.task.on_error(function(message)
        notices.push(message)
    end)
    local ok, err = pcall(run, args)
    if not ok then
        fail(tostring(err))
    end
end
