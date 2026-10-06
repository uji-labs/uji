local agent = require("support.agent")
local app = require("uji.core.app")
local sys = require("uji.sys")

local seen = {}

local function Fake(script)
    local Loop = uji.class()

    function Loop:init(owner, turn)
        self.agent = owner
        self.turn = turn
    end

    function Loop:interrupt()
        seen[#seen + 1] = "interrupt"
    end

    function Loop:run()
        return script(self)
    end

    return Loop
end

local function start(script)
    uji.provider.add({
        id = "fake",
        name = "Fake",
        api = uji.api.openai(),
        loop = Fake(script),
        models = { "m" },
    })
    uji.model.use({ provider = "fake", model = "m" })
    app.session:rename("test")
    agent.answer({ "y" })
end

local function submit(text)
    local finished = sys.promise()
    uji.on("turn_finished", function()
        if #app.agent.queue == 0 then
            finished:resolve()
        end
    end)
    uji.session.submit(text)
    finished:await()
    return agent.messages()
end

it("runs the turn through the provider's loop", { timeout = 10 }, function()
    start(function(loop)
        seen[#seen + 1] = loop.turn.prompt.text
        loop.agent:delta("text", "hel")
        loop.agent:assistant_step({
            type = "assistant",
            text = "step",
            tool_calls = { { id = "c1", name = "Bash", arguments = '{"command":"ls"}' } },
        })
        local decision = loop.agent:approve("Bash", { command = "ls" })
        loop.agent:tool_result({ id = "c1", name = "Bash" }, decision.allow and "ok" or "denied")
        loop.agent:usage({ input = 5, output = 2 })
        loop.agent:done({ type = "assistant", text = "hello", tool_calls = {} })
    end)
    local messages = submit("hi there")
    assert.same({ "hi there" }, seen)
    assert.same({ "ok" }, agent.tool_results(messages))
    assert.equal("hello", agent.last_answer(messages))
    assert.equal("Bash", messages[2].tool_calls[1].name)
    assert.equal(7, uji.session.usage().total)
end)

it("forwards an interrupt to the loop", { timeout = 10 }, function()
    start(function(loop)
        local call = { id = "c1", name = "Bash", arguments = "{}" }
        loop.agent:assistant_step({ type = "assistant", text = "", tool_calls = { call } })
        loop.agent:tool_running(call)
        sys.sleep(60)
    end)
    uji.defer(0.3, uji.session.interrupt)
    local messages = submit("go")
    assert.same({ "interrupt" }, seen)
    assert.same({ "error: interrupted by the user while this tool ran" }, agent.tool_results(messages))
    assert.equal("interrupted", agent.last_error(messages))
end)

it("reports a loop that raises", { timeout = 10 }, function()
    start(function()
        error("boom", 0)
    end)
    assert.equal("loop: boom", agent.last_error(submit("go")))
end)

it("ends a turn whose loop returns without an answer", { timeout = 10 }, function()
    start(function() end)
    assert.equal("loop: the turn ended without an answer", agent.last_error(submit("go")))
    assert.is_false(app.agent:working())
end)

it("keeps the next turn running when a finished loop raises", { timeout = 10 }, function()
    local runs = 0
    start(function(loop)
        runs = runs + 1
        if runs == 1 then
            uji.session.submit("second")
            loop.agent:done({ type = "assistant", text = "one", tool_calls = {} })
            error("late", 0)
        end
        loop.agent:done({ type = "assistant", text = "two", tool_calls = {} })
    end)
    local messages = submit("first")
    assert.equal(2, runs)
    assert.equal("two", agent.last_answer(messages))
    for _, message in ipairs(messages) do
        assert.is_not.equal("error", message.type)
    end
end)

it("rejects a loop that is not a class", function()
    local ok, err = pcall(uji.provider.add, {
        id = "odd",
        name = "Odd",
        api = uji.api.openai(),
        loop = { run = function() end },
        models = { "m" },
    })
    assert.is_false(ok)
    assert.truthy(tostring(err):find("the loop of provider odd must be a class with a run method", 1, true))
end)

it("lists the loop on the provider row and needs no base_url", { timeout = 10 }, function()
    start(function(loop)
        loop.agent:done({ type = "assistant", text = "", tool_calls = {} })
    end)
    local row = uji.provider.get("fake")
    assert.is_true(row.loop)
    assert.equal("", row.base_url)
    assert.is_false(uji.provider.get("openai").loop)
end)

it("leaves the context to a provider with its own loop", { timeout = 10 }, function()
    start(function(loop)
        loop.agent:done({ type = "assistant", text = "", tool_calls = {} })
    end)
    local started, reason = uji.session.compact()
    assert.is_false(started)
    assert.equal("Fake keeps its own context", reason)
end)

it("switches to a provider with its own loop at login without asking for a url or key", { timeout = 10 }, function()
    uji.provider.add({ id = "fake", name = "Fake", api = uji.api.openai(), loop = Fake(function() end), models = { "m" } })
    local asked = {}
    uji.ui.select = function(opts)
        asked[#asked + 1] = opts.title
        return opts.title == "Provider" and "Fake" or nil
    end
    uji.ui.prompt = function(opts)
        asked[#asked + 1] = opts.title
    end
    require("uji.core.command").run("login")
    assert.same({ "Provider" }, asked)
    assert.equal("fake", uji.model.current().provider)
end)
