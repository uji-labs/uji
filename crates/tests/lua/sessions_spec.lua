local app = require("uji.core.app")
local Sessions = require("uji.core.ui.sessions").Sessions
local sys = require("uji.sys")

before_each(function()
    app.session.directory = sys.os.cwd()
end)

local function watch_restarts()
    local captured = {}
    sys.os.restart = function(opts)
        captured[#captured + 1] = opts
    end
    return captured
end

local function resumed(opts)
    assert.equal("resume", opts.args[2])
    assert.equal("--id", opts.args[3])
    return opts.args[4]
end

local function ran(line)
    require("uji.core.command").run(line)
end

local function added(title)
    local session = app.store:create_session(title)
    session:append({ type = "user", text = title })
    return session
end

it("lists the sessions here and resumes the one you pick", function()
    local launched = watch_restarts()
    local other = added("Another session")
    local asked
    uji.ui.pick = function(opts)
        asked = opts
        return other
    end
    ran("list")
    assert.equal("Sessions", asked.title)
    local ids = {}
    for _, item in ipairs(asked.items) do
        ids[#ids + 1] = item.id
    end
    assert.is_true(table.concat(ids, ","):find(other.id, 1, true) ~= nil, "the other session is on the list")
    assert.equal(other.id, resumed(launched[1]))
end)

it("resumes the session an id names, or the latest here", function()
    local launched = watch_restarts()
    local other = added("Newer session")
    ran("resume " .. other.id)
    assert.equal(other.id, resumed(launched[1]))
    ran("resume")
    assert.equal(other.id, resumed(launched[2]), "the latest session in this directory")
end)

it("wants an id that names a session", function()
    local launched = watch_restarts()
    local ok, problem = uji.session.resume("not-a-uuid")
    assert.is_nil(ok)
    assert.equal("invalid session id: not-a-uuid", problem)
    ok, problem = uji.session.resume("00000000-0000-4000-8000-000000000000")
    assert.is_nil(ok)
    assert.equal("no session with id 00000000-0000-4000-8000-000000000000", problem)
    ok, problem = uji.session.resume(app.session.id)
    assert.is_nil(ok)
    assert.equal("that session is already open", problem)
    assert.equal(0, #launched)
end)

it("refuses to switch sessions mid-turn", function()
    local launched = watch_restarts()
    local other = added("Waiting session")
    app.agent.state = "working"
    local ok, problem = uji.session.resume(other.id)
    app.agent.state = "idle"
    assert.is_nil(ok)
    assert.equal("finish or interrupt the current turn before resuming another session", problem)
    assert.equal(0, #launched)
end)

local function picker()
    return Sessions(uji.session.list({ directory = app.session.directory }), app.session.directory)
end

local function choose(instance, id)
    for index, item in ipairs(instance.sessions) do
        if item.id == id then
            instance.selection.value = index
        end
    end
end

it("deletes the session D asks about, once you say yes", function()
    local other = added("Delete me")
    local instance = picker()
    choose(instance, other.id)
    instance:key({ key = "D" })
    assert.equal(other.id, instance.asking.id)
    instance:key({ key = "y" })
    assert.is_nil(instance.asking)
    assert.is_nil(app.store:session(other.id))
    for _, item in ipairs(instance.sessions) do
        assert.is_true(item.id ~= other.id, "the deleted session left the list")
    end
end)

it("keeps the session when the delete is answered no", function()
    local other = added("Keep me")
    local instance = picker()
    choose(instance, other.id)
    instance:key({ key = "D" })
    instance:key({ key = "n" })
    assert.is_nil(instance.asking)
    assert.is_not_nil(app.store:session(other.id))
end)

it("saves a new session with its first message", function()
    assert.is_nil(app.store:session(app.session.id))
    assert.equal(0, #uji.session.list({ directory = app.session.directory }))
    local ok, problem = uji.session.resume(app.session.id)
    assert.is_nil(ok)
    assert.equal("that session is already open", problem)
    app.session:append({ type = "user", text = "hello" })
    assert.is_not_nil(app.store:session(app.session.id), "the first message saves the session")
    assert.equal(1, #uji.session.list({ directory = app.session.directory }))
end)
