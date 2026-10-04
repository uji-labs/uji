local scenario = require("scenario")
local sys = require("uji.sys")
local ui = require("uji.core.ui")

local CHUNKS = 50000
local INTERRUPTS = 20
local QUEUED = 100
local CALLS = 200
local REASONING = 1000
local HUGE = "head -c 10000000 /dev/zero | tr '\\0' x"
local LOG = "seq 1 1000000"
local SETTLE = 0.05

scenario.open()

local function chunk(delta, finish)
    return { choices = { { index = 0, delta = delta, finish_reason = finish or sys.json.null } } }
end

torture("a reply in 50,000 one character chunks", function()
    local tokens = {}
    for index = 1, CHUNKS do
        tokens[index] = index % 80 == 0 and "\n" or "x"
    end
    scenario.serve(scenario.events(scenario.chunks(tokens)))
    scenario.turn("stream it")
end, { budget = 10 })

torture("a 5 MB reply in one event", function()
    scenario.serve(scenario.text(string.rep(scenario.REPLY, 4000)))
    scenario.turn("one big event")
end, { budget = 5 })

torture("garbage between the events", function()
    local good = sys.json.encode(chunk({ content = "intact" }, "stop"))
    scenario.serve({ lines = { ": ping", "data: {nope", "event: noise", "data: [1,2", "data: " .. good, "data: [DONE]" } })
    scenario.turn("survive the noise")
    assert(scenario.last_answer(scenario.messages()) == "intact", "the reply was lost in the noise")
end)

torture("1 MB of reasoning while thinking is shown", function()
    ui:toggle_thinking()
    local chunks = {}
    for index = 1, REASONING do
        chunks[index] = chunk({ reasoning_content = string.rep("think ", 170) })
    end
    chunks[#chunks + 1] = chunk({ content = "done" }, "stop")
    scenario.serve(scenario.events(chunks))
    scenario.turn("think hard")
    ui:render()
    ui:toggle_thinking()
end, { budget = 5 })

torture("a 1 MB prompt", function()
    scenario.serve(scenario.text("read it"))
    scenario.turn(string.rep("please read this carefully ", 40000))
end, { budget = 5 })

torture("interrupt 20 streaming turns", function()
    scenario.serve(scenario.drip("data: " .. sys.json.encode(chunk({ content = "token " })), 0.001))
    for _ = 1, INTERRUPTS do
        uji.session.submit("start and stop")
        sys.sleep(SETTLE)
        uji.session.interrupt()
    end
    scenario.idle()
end, { budget = 10 })

torture("queue 100 prompts during a turn", function()
    scenario.serve(scenario.text("noted"))
    for index = 1, QUEUED do
        uji.session.submit("prompt " .. index)
    end
    scenario.idle()
end, { budget = 10 })

torture("200 tool calls in one reply", function()
    local calls = {}
    for index = 1, CALLS do
        calls[index] = { "read_file", sys.json.encode({ path = "missing-" .. index .. ".txt" }) }
    end
    scenario.serve(function(round)
        return round == 0 and scenario.tool_calls(round, calls) or scenario.text("done")
    end)
    scenario.turn("read them all")
end, { budget = 10 })

torture("a command that prints one 10 MB line", function()
    scenario.call("run_command", { command = HUGE })
end, { budget = 10 })

torture("a command that prints 1,000,000 lines", function()
    scenario.call("run_command", { command = LOG })
end, { budget = 10 })
