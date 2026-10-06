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
        base_url = "",
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

it("lists the loop on the provider row and skips the login questions", { timeout = 10 }, function()
    start(function(loop)
        loop.agent:done({ type = "assistant", text = "", tool_calls = {} })
    end)
    assert.is_true(uji.provider.get("fake").loop)
    assert.is_false(uji.provider.get("openai").loop)
end)
