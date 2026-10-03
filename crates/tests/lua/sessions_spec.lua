local sandbox = require("support.sandbox")
local sys = require("uji.sys")

local function core(name)
    return require("uji.core." .. name)
end

it("keeps blank sessions transient and reloads the full first message", function()
    local app = core("app")
    local store, session = app.store, app.session
    assert.is_true(session.pending)
    assert.equal(0, #store:sessions())
    session:rename("a draft")
    assert.equal(0, #store.db:query("SELECT id FROM sessions"))
    local message = { type = "user", text = "saved text" }
    local entry = assert(session:append(message))
    assert.is_false(session.pending)
    assert.equal(1, #store:sessions())
    assert.equal(session.id, store:latest(session.directory).id)
    local reopened = core("store")(sandbox.db)
    local blank = reopened:create_session()
    assert.is_true(blank.pending)
    assert.equal(1, #reopened:sessions())
    local saved = assert(reopened:session(session.id))
    assert.equal(session.id, saved.id)
    assert.equal("a draft", saved.title)
    assert.falsy(saved.pending)
    assert.same({ entry }, saved:entries())
    assert.same({ message }, saved:messages())
    assert.equal(saved.id, reopened:latest(saved.directory).id)
    reopened.db:close()
end)

it("selects directory roots with descendant history ahead of empty sessions", function()
    local store = core("app").store
    local root = store:create_session("root")
    local child = root:child("child")
    local grandchild = child:child("grandchild")
    assert(grandchild:append({ type = "user", text = "deep history" }))
    local direct = store:create_session("direct")
    assert(direct:append({ type = "user", text = "direct history" }))
    local foreign = store:create_session("foreign")
    foreign.directory = root.directory .. "/other"
    assert(foreign:append({ type = "user", text = "other directory" }))
    store.db:exec("UPDATE sessions SET time_updated = ? WHERE id = ?", { 100, root.id })
    store.db:exec("UPDATE sessions SET time_updated = ? WHERE id = ?", { 50, direct.id })
    store.db:exec("UPDATE sessions SET time_updated = ? WHERE id = ?", { 1000, foreign.id })
    for index = 1, 40 do
        store.db:exec(
            [[INSERT INTO sessions
            (id,title,directory,time_created,time_updated) VALUES (?,?,?,?,?)]],
            { "empty-" .. index, "empty", root.directory, 0, 2000 + index }
        )
    end
    assert.equal(root.id, store:latest(root.directory).id)
    assert.equal(foreign.id, store:latest(foreign.directory).id)
    assert.falsy(store:latest(root.directory .. "/missing"))
    assert.is_true(store:has_history(root.id))
    assert.is_true(store:has_history(child.id))
    assert.is_true(store:has_history(grandchild.id))
    assert.is_true(store:has_history(direct.id))
    assert.is_false(store:has_history("empty-1"))
    assert.is_false(store:has_history("missing"))
end)

it("publishes nothing when the first message is rejected and recovers on retry", function()
    local app, event = core("app"), core("event")
    local db, session = app.store.db, app.session
    local events = 0
    event.on("message_appended", function()
        events = events + 1
    end)
    assert(db:exec([[CREATE TRIGGER reject_first BEFORE INSERT ON messages
        BEGIN SELECT RAISE(ABORT, 'rejected message'); END]]))
    local entry, err = session:append({ type = "user", text = "must not persist" })
    assert.falsy(entry)
    assert.truthy(err:find("rejected message", 1, true))
    assert.is_true(session.pending)
    assert.equal(0, #session:entries())
    assert.equal(0, events)
    assert.equal(0, #db:query("SELECT id FROM sessions"))
    assert.equal(0, #db:query("SELECT id FROM messages"))
    assert(db:exec("DROP TRIGGER reject_first"))
    assert.equal(1, assert(session:append({ type = "shell", text = "saved shell result" })).seq)
    assert.is_false(session.pending)
    assert.equal(1, events)
end)

it("persists child history and deletes its tree without deleting other sessions", function()
    local store = core("app").store
    local parent = store:create_session("parent")
    local child = parent:child("child")
    local other = store:create_session("other")
    assert.equal(0, #store.db:query("SELECT id FROM sessions"))
    assert(child:append({ type = "user", text = "child work" }))
    assert.is_false(child.pending)
    assert.is_false(parent.pending)
    assert.is_true(store:has_history(parent.id))
    assert.equal(2, #store:tree(parent.id))
    assert.equal(parent.id, store:latest(parent.directory).id)
    assert(other:append({ type = "error", text = "retain errors" }))
    assert(store:delete(parent.id))
    assert.falsy(store:session(parent.id))
    assert.falsy(store:session(child.id))
    assert.equal("retain errors", store:session(other.id):messages()[1].text)
    assert.equal(1, #store.db:query("SELECT id FROM messages"))
end)

it("keeps legacy empty sessions deletable but excludes them from latest", function()
    local store = core("app").store
    local saved = store:create_session("saved")
    assert(saved:append({ type = "user", text = "keep" }))
    assert(
        store.db:exec(
            [[INSERT INTO sessions
        (id,title,directory,time_created,time_updated) VALUES (?,?,?,?,?)]],
            { "legacy-empty", "untitled", saved.directory, sys.os.now(), sys.os.now() + 10000 }
        )
    )
    assert.equal(2, #store:sessions())
    assert.is_false(store:has_history("legacy-empty"))
    assert.equal(saved.id, store:latest(saved.directory).id)
    assert(store:delete("legacy-empty"))
    assert.equal(1, #store:sessions())
    assert.equal("keep", store:session(saved.id):messages()[1].text)
end)

it("stops inference on failed writes, carries drafts on reload, and retries", function()
    local app = core("app")
    local calls = 0
    uji.provider.add({
        id = "session-fixture",
        name = "Fixture",
        base_url = "https://fixture.invalid",
        auth_env = { "FIXTURE_KEY" },
        models = { "m" },
        api = {
            stream = function(_, _, reply)
                calls = calls + 1
                reply.done({ text = "done", tool_calls = {} })
            end,
        },
    })
    core("auth").save_key("session-fixture", "synthetic-test-key")
    uji.model.use({ provider = "session-fixture", model = "m" })
    app.session:rename("fixture")
    assert(app.store.db:exec([[CREATE TRIGGER reject_first BEFORE INSERT ON messages
        BEGIN SELECT RAISE(ABORT, 'rejected user'); END]]))
    local ok = pcall(uji.session.submit, "do not send")
    sys.sleep(0)
    assert.is_false(ok)
    assert.equal(0, calls)
    assert.is_true(app.session.pending)
    assert.equal(0, #app.store:sessions())
    assert.equal(0, #app.session:messages())
    local restarted
    sys.os.restart = function(options)
        restarted = options
    end
    uji.input.set("unsent draft")
    core("config").reload()
    assert.equal("new", restarted.args[2])
    assert.equal("unsent draft", sys.json.decode(restarted.carry).draft)
    local flags = {}
    for index = 3, #restarted.args, 2 do
        flags[restarted.args[index]] = restarted.args[index + 1]
    end
    assert.equal(sandbox.db, flags["--db"])
    assert.equal(sandbox.cfg, flags["--config-dir"])
    assert.equal(sandbox.data, flags["--data-dir"])
    assert(app.store.db:exec("DROP TRIGGER reject_first"))
    local finished = sys.promise()
    core("event").on("turn_finished", function()
        finished:resolve(true)
    end)
    uji.session.submit("now save")
    finished:await()
    assert.equal(1, calls)
    assert.is_false(app.session.pending)
    assert.equal("assistant", app.session:messages()[2].type)
    assert.equal("done", app.session:messages()[2].text)
    assert.equal(1, #app.store:sessions())
    assert.equal(2, #app.session:messages())
end)

it("retains rejected UI submissions without overwriting newer drafts or replaying committed input", function()
    local app, ui, event = core("app"), core("ui"), core("event")
    local image = { media_type = "image/png", data = "opaque-image", name = "draft.png" }
    local calls = 0
    uji.provider.add({
        id = "ui-retry",
        name = "Fixture",
        base_url = "https://fixture.invalid",
        auth_env = { "FIXTURE_KEY" },
        models = { { id = "m", images = true, context = 10000, output = 1000 } },
        api = {
            stream = function(_, request, reply)
                calls = calls + 1
                assert.same(image, request.messages[1].images[1])
                reply.fail({ kind = "provider", message = "failure after committed input" })
            end,
        },
    })
    core("auth").save_key("ui-retry", "synthetic-test-key")
    uji.model.use({ provider = "ui-retry", model = "m" })
    app.session:rename("fixture")
    app.store.db:exec([[CREATE TRIGGER reject_ui BEFORE INSERT ON messages
        WHEN NEW.type='user' BEGIN SELECT RAISE(ABORT,'UI write rejected'); END]])
    local rejected = sys.promise()
    event.on("notice", function(payload)
        if payload.text:find("UI write rejected", 1, true) then
            rejected:resolve()
        end
    end)
    ui.composer:paste("first line\nsecond line")
    ui.composer:attach(image)
    local original = ui.composer.pastes:expand(ui.composer:text())
    ui:submit()
    uji.input.set("newer draft")
    rejected:await()
    assert.equal(0, calls)
    assert.equal(0, #app.session:messages())
    assert.equal(0, #app.store:sessions())
    assert.equal("newer draft", ui.composer:text())
    assert.equal(1, #app.agent.queue)
    assert.equal(original, app.agent.queue[1].text)
    assert.same(image, app.agent.queue[1].images[1])
    app.store.db:exec("DROP TRIGGER reject_ui")
    local finished = sys.promise()
    event.on("turn_finished", function()
        finished:resolve()
    end)
    app.agent:send_queued()
    finished:await()
    assert.equal(1, calls)
    assert.equal(0, #app.agent.queue)
    assert.equal("newer draft", ui.composer:text())
    local messages = app.session:messages()
    assert.equal(2, #messages)
    assert.equal("user", messages[1].type)
    assert.equal(original, messages[1].text)
    assert.same(image, messages[1].images[1])
    assert.equal("error", messages[2].type)
end)

it("blocks navigation while submitted images are being prepared", function()
    local app, ui, manager = core("app"), core("ui"), core("ui.sessions")
    local preparing, release, completed = sys.promise(), sys.promise(), sys.promise()
    local image = { media_type = "image/png", data = "synthetic-image", name = "diagram.png" }
    core("images").mentioned = function()
        preparing:resolve()
        release:await()
        return { image }
    end
    local calls, restarts = 0, 0
    sys.os.restart = function()
        restarts = restarts + 1
    end
    uji.provider.add({
        id = "preparation-fixture",
        name = "Fixture",
        base_url = "https://fixture.invalid",
        models = { { id = "m", images = true, context = 10000, output = 1000 } },
        api = {
            stream = function(_, request, reply)
                calls = calls + 1
                assert.equal("read @diagram.png", request.messages[1].text)
                assert.same(image, request.messages[1].images[1])
                reply.done({ text = "done", tool_calls = {} })
            end,
        },
    })
    core("auth").save_key("preparation-fixture", "synthetic-test-key")
    uji.model.use({ provider = "preparation-fixture", model = "m" })
    app.session:rename("fixture")
    core("event").on("turn_finished", function()
        completed:resolve()
    end)
    uji.input.set("read @diagram.png")
    ui:submit()
    uji.input.set("newer draft")
    preparing:await()
    assert.equal(0, #app.agent.queue)
    assert.is_true(manager.busy())
    for _, operation in ipairs({
        function()
            manager.restart(nil, true)
        end,
        function()
            manager.switch({ id = "another-session" })
        end,
    }) do
        assert.is_false(pcall(operation))
    end
    core("config").reload()
    assert.equal(0, restarts)
    assert.equal("newer draft", ui.composer:text())
    release:resolve()
    completed:await()
    assert.equal(1, calls)
    assert.equal(0, #app.agent.queue)
    assert.is_false(manager.busy())
    assert.equal("newer draft", ui.composer:text())
    assert.equal("read @diagram.png", app.session:messages()[1].text)
end)

it("requires an unmodified y to delete a selected session", function()
    local app, ui, manager = core("app"), core("ui"), core("ui.sessions")
    local saved = app.store:create_session("selected")
    assert(saved:append({ type = "user", text = "history" }))
    local picker = manager.Picker(app.store, saved.directory, app.session.id)
    for _, modifiers in ipairs({ { shift = true }, { alt = true }, { ctrl = true } }) do
        picker:delete_prompt()
        ui:present(picker)
        ui:handle({ type = "key", key = "y", shift = modifiers.shift, alt = modifiers.alt, ctrl = modifiers.ctrl })
        sys.sleep(0)
        assert.is_not_nil(app.store:session(saved.id))
    end
    picker:key({ key = "y" }, ui)
    assert.is_nil(app.store:session(saved.id))
end)

it("carries drafts on switching and blocks running shells and attached images", function()
    local app, manager, ui = core("app"), core("ui.sessions"), core("ui")
    local saved = app.store:create_session("target")
    assert(saved:append({ type = "user", text = "target history" }))
    local restarted, opened = nil, false
    sys.os.restart = function(options)
        restarted = options
    end
    ui.ask = function()
        opened = true
    end
    app.agent.shell = {}
    core("command").run("sessions")
    assert.is_false(opened)
    assert.is_false((pcall(manager.switch, saved)))
    assert.is_nil(restarted)
    app.agent.shell = nil
    ui.composer:paste("first line\nsecond line")
    manager.switch(saved)
    assert.equal("first line\nsecond line", sys.json.decode(restarted.carry).draft)
    restarted = nil
    ui.composer:attach({ name = "fixture image" })
    local draft = ui.composer:text()
    assert.is_false((pcall(manager.switch, saved)))
    assert.is_nil(restarted)
    assert.is_false((pcall(core("config").reload)))
    assert.is_nil(restarted)
    assert.equal(draft, ui.composer:text())
    assert.equal(1, #ui.composer.pastes:images(draft))
end)

it("starts fresh without losing drafts or pending work", function()
    local app, ui, command = core("app"), core("ui"), core("command")
    local restarted
    sys.os.restart = function(options)
        restarted = options
    end
    assert.is_true(app.session.pending)
    ui.composer:paste("first line\nsecond line")
    command.run("new")
    assert.equal("new", restarted.args[2])
    local carried = sys.json.decode(restarted.carry)
    assert.equal("first line\nsecond line", carried.draft)
    assert.is_nil(carried.session)
    assert.equal(0, #app.store:sessions())
    restarted = nil
    app.agent:enqueue("pending input")
    command.run("new")
    assert.is_nil(restarted)
    assert.equal("pending input", app.agent.queue[1].text)
    app.agent.queue = {}
    ui.composer:attach({ name = "fixture image" })
    command.run("new")
    assert.is_nil(restarted)
    assert.equal(1, #ui.composer.pastes:images(ui.composer:text()))
    assert.equal(0, #app.store:sessions())
end)

it("leaves the agent idle after failed compaction and interrupt writes", function()
    local app, event = core("app"), core("event")
    local agent, db = app.agent, app.store.db
    app.session:rename("fixture")
    assert(app.session:append({ type = "user", text = string.rep("old ", 100) }))
    assert(app.session:append({ type = "user", text = "recent" }))
    assert(db:exec([[CREATE TRIGGER reject_compaction BEFORE INSERT ON messages
        WHEN NEW.type='compaction' BEGIN SELECT RAISE(ABORT,'compaction rejected'); END]]))
    core("agent.compactor").generate = function()
        return "summary", {}
    end
    local idle = sys.promise()
    event.on("status_changed", function()
        if not agent:working() then
            idle:resolve(true)
        end
    end)
    assert(agent:compact(0))
    idle:await()
    assert.is_false(agent:working())
    assert.equal(2, #app.session:messages())
    assert(db:exec("DROP TRIGGER reject_compaction"))
    local entered, reply = sys.promise(), nil
    uji.provider.add({
        id = "interrupt-fixture",
        name = "Fixture",
        base_url = "https://fixture.invalid",
        auth_env = { "FIXTURE_KEY" },
        models = { "m" },
        api = {
            stream = function(_, _, out)
                reply = out
                entered:resolve(true)
            end,
        },
    })
    core("auth").save_key("interrupt-fixture", "synthetic-test-key")
    uji.model.use({ provider = "interrupt-fixture", model = "m" })
    assert(db:exec([[CREATE TRIGGER reject_interrupt BEFORE INSERT ON messages
        WHEN NEW.type='error' BEGIN SELECT RAISE(ABORT,'interrupt rejected'); END]]))
    uji.session.submit("wait")
    entered:await()
    assert.is_true(agent:working())
    assert.is_false((pcall(agent.interrupt, agent)))
    assert.is_false(agent:working())
    reply.done({ text = "late answer", tool_calls = {} })
    sys.sleep(0)
    assert.equal(3, #app.session:messages())
    assert(db:exec("DROP TRIGGER reject_interrupt"))
    assert(app.session:append({ type = "user", text = "can persist again" }))
end)

it("retains queued input after automatic compaction fails and blocks navigation", function()
    local app, event = core("app"), core("event")
    local agent, db, manager = app.agent, app.store.db, core("ui.sessions")
    app.session:rename("fixture")
    assert(app.session:append({ type = "user", text = string.rep("old ", 300) }))
    assert(app.session:append({ type = "user", text = "recent" }))
    local target = app.store:create_session("target")
    assert(target:append({ type = "user", text = "other history" }))
    local calls = 0
    uji.provider.add({
        id = "queued-fixture",
        name = "Fixture",
        base_url = "https://fixture.invalid",
        models = { { id = "m", context = 64, output = 16 } },
        api = {
            stream = function()
                calls = calls + 1
                error("inference must not start")
            end,
        },
    })
    uji.model.use({ provider = "queued-fixture", model = "m" })
    uji.context.configure({ compaction = { keep_recent = 0, reserve = 0 } })
    assert(db:exec([[CREATE TRIGGER reject_auto_compaction BEFORE INSERT ON messages
        WHEN NEW.type='compaction' BEGIN SELECT RAISE(ABORT,'compaction rejected'); END]]))
    core("agent.compactor").generate = function()
        return "summary", {}
    end
    local idle = sys.promise()
    event.on("status_changed", function()
        if not agent:working() then
            idle:resolve(true)
        end
    end)
    uji.session.submit("queued input must survive")
    idle:await()
    assert.is_false(agent:working())
    assert.equal(0, calls)
    assert.equal(2, #app.session:messages())
    assert.equal(1, #agent.queue)
    assert.equal("queued input must survive", agent.queue[1].text)
    local restarted, opened = false, false
    sys.os.restart = function()
        restarted = true
    end
    core("ui").ask = function()
        opened = true
    end
    assert.is_false((pcall(manager.switch, target)))
    core("config").reload()
    core("command").run("sessions")
    assert.is_false(restarted)
    assert.is_false(opened)
    assert.equal(1, #agent.queue)
    assert.equal("queued input must survive", agent.queue[1].text)
end)

it("retains queued text and images after rejected steering for retry", function()
    local app = core("app")
    local agent, db = app.agent, app.store.db
    local image = { media_type = "image/png", data = "opaque-image", name = "queued.png" }
    agent:enqueue("queued text", { image })
    assert(db:exec([[CREATE TRIGGER reject_queued BEFORE INSERT ON messages
        WHEN NEW.type='user' BEGIN SELECT RAISE(ABORT,'queued write rejected'); END]]))
    assert.is_false((pcall(agent.steer, agent)))
    assert.equal(1, #agent.queue)
    assert.equal("queued text", agent.queue[1].text)
    assert.same(image, agent.queue[1].images[1])
    assert.equal(0, #app.session:messages())
    assert.is_true(app.session.pending)
    assert(db:exec("DROP TRIGGER reject_queued"))
    local message = agent:steer()
    assert.equal("queued text", message.text)
    assert.same(image, message.images[1])
    assert.equal(0, #agent.queue)
    assert.equal(1, #app.session:messages())
    local loaded = assert(app.store:session(app.session.id))
    assert.same(image, loaded:messages()[1].images[1])
end)

it("requires committed queued input before inference and recovers after rejection", function()
    local app, event = core("app"), core("event")
    local agent, db = app.agent, app.store.db
    local calls = 0
    local image = { media_type = "image/png", data = "opaque-image", name = "queued.png" }
    uji.provider.add({
        id = "queued-retry",
        name = "Fixture",
        base_url = "https://fixture.invalid",
        auth_env = { "FIXTURE_KEY" },
        models = { { id = "m", images = true, context = 10000, output = 1000 } },
        api = {
            stream = function(_, request, reply)
                calls = calls + 1
                assert.same(image, request.messages[1].images[1])
                reply.fail({ kind = "provider", message = "failure after committed input" })
            end,
        },
    })
    core("auth").save_key("queued-retry", "synthetic-test-key")
    uji.model.use({ provider = "queued-retry", model = "m" })
    app.session:rename("fixture")
    agent:enqueue("queued text", { image })
    assert(db:exec([[CREATE TRIGGER reject_queued BEFORE INSERT ON messages
        WHEN NEW.type='user' BEGIN SELECT RAISE(ABORT,'queued write rejected'); END]]))
    assert.is_false((pcall(agent.send_queued, agent)))
    assert.equal(0, calls)
    assert.equal(1, #agent.queue)
    assert.same(image, agent.queue[1].images[1])
    assert.equal(0, #app.session:messages())
    assert.is_true(app.session.pending)
    assert(db:exec("DROP TRIGGER reject_queued"))
    local finished = sys.promise()
    event.on("turn_finished", function()
        finished:resolve(true)
    end)
    agent:send_queued()
    finished:await()
    assert.equal(1, calls)
    assert.equal(0, #agent.queue)
    assert.equal(2, #app.session:messages())
    assert.equal("queued text", app.session:messages()[1].text)
    assert.same(image, app.session:messages()[1].images[1])
    assert.equal("error", app.session:messages()[2].type)
    assert.is_false(agent:working())
end)
