local cli = require("uji.core.cli")
local notices = require("uji.core.notices")
local sys = require("uji.sys")
local tables = require("uji.core.tables")

local function open_session(store, parsed)
    local Store = require("uji.core.store")
    if parsed.command == "new" then
        local ok, carry = pcall(sys.json.decode, sys.os.carry or "null", { nulls = false })
        local pending = ok and type(carry) == "table" and carry.session
        if type(pending) == "table" and cli.valid_id(pending.id)
            and type(pending.title) == "string" and type(pending.directory) == "string"
            and pending.directory ~= "" then
            local saved = store:session(pending.id)
            if saved then return saved, "session_resumed" end
            local session = store:create_session(pending.title, nil, pending.id)
            session.directory = pending.directory
            return session, "session_created"
        end
        return store:create_session(Store.UNTITLED), "session_created"
    end
    local id = parsed.flags.id
    if not id then
        return store:latest(sys.os.cwd()) or store:create_session(Store.UNTITLED), "session_resumed"
    end
    return cli.session(store, id), "session_resumed"
end

local function restore()
    local ok, carried = pcall(sys.json.decode, sys.os.carry or "null", { nulls = false })
    if ok and type(carried) == "table" and type(carried.draft) == "string" and carried.draft ~= "" then
        require("uji.core.ui"):set_input(carried.draft)
    end
end

local function start(session, created)
    local agent = require("uji.core.app").attach(session)
    require("uji.core.event").emit(created, { session_id = session.id })
    require("uji.core.ui"):start()
    restore()
    agent:repair()
    require("uji.core.config").refresh()
    require("uji.core.task").release()
end

local function run(args)
    local cli = require("uji.core.cli")
    local paths = require("uji.core.paths")
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
    local packs = require("uji.core.packs")
    local expected = packs.expected()
    if not tables.same(expected, sys.os.roots) then
        return sys.os.restart({ args = args, roots = expected, carry = sys.os.carry })
    end
    require("uji.api")
    local db = paths.db()
    if not db then
        return cli.fail("$HOME is not set")
    end
    local Store = require("uji.core.store")
    local ok, store = pcall(Store, db)
    if not ok then
        return cli.fail(sys.message(store))
    end
    if parsed.command == "delete" then
        local id = parsed.positional and parsed.positional[1]
        if not cli.valid_id(id) then
            return cli.fail("invalid session id: " .. tostring(id))
        end
        store:delete(id)
        return
    end
    local command = parsed.command
    if command ~= "new" and command ~= "resume" and command ~= "list" and command ~= "run" then
        return cli.fail("unrecognized subcommand '" .. command .. "'")
    end
    require("uji.core.task").hold()
    local app = require("uji.core.app")
    app.store = store
    app.argv = args
    app.flags = parsed.flags
    require("uji.core.model").attach(store)
    require("uji.builtin.commands")
    local config = require("uji.core.config")
    config.load()
    if config.settle(args) then
        return
    end
    if command == "run" then
        return require("uji.core.run")(store, parsed)
    end
    if command == "list" then
        local session = require("uji.core.ui.sessions").pick(store)
        if not session then
            return require("uji.core.ui"):quit()
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
        cli.fail(sys.message(err))
    end
end
